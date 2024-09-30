#!/bin/bash
DATE="20240707"
SIZE="4G"
OUT_ROOTFS="/tmp/chimera-rootfs.img"
WORKDIR="/tmp/chimera-rootfs" # /mnt
SUDO="sudo"
CPORTS="$HOME/cports"
CHROOT_WRAPPER="chimera-chroot" # xchroot arch-chroot
APK_CACHE="apk-cache"
ARCH="aarch64"
OVERLAYS=(
	base # Most default file-based configuration shared across all devices
	usbnet # RNDIS + internet over USB
)

if [ ! -f "$1" ]; then
	cat <<EOF
You must specify a config to use, for example:

    $0 config.vidofnir.sh

EOF
	exit 1
fi
. "$1"

set -e # exit on any error
cd "$(readlink -f "$(dirname "$0")")" # dir of this script
[ -f config.local.sh ] && . config.local.sh
tarball="chimera-linux-$ARCH-ROOTFS-$DATE-bootstrap.tar.gz"
url="https://repo.chimera-linux.org/live/$DATE/$tarball"
host_arch=$(uname -m)

set -x # log every executed command
mountpoint -q "$WORKDIR" && $SUDO umount -R "$WORKDIR"
rm -f "$OUT_ROOTFS"

fallocate -l $SIZE "$OUT_ROOTFS"
# NOTE: features disabled that makes halium initrd & recoveries unhappy to work with the ext4 image files
# https://www.mail-archive.com/debian-bugs-dist@lists.debian.org/msg1896675.html
mkfs.ext4 -b 4096 -O '^metadata_csum_seed,^orphan_file' -m 0 -F "$OUT_ROOTFS"

[ ! -d "$WORKDIR" ] && mkdir -p "$WORKDIR"
$SUDO mount "$OUT_ROOTFS" "$WORKDIR"

[ -f "$tarball" ] || wget "$url"
$SUDO tar xfp "$tarball" -C "$WORKDIR"

[ "$host_arch" != "$ARCH" ] && $SUDO cp "$(command -v qemu-$ARCH-static)" "$WORKDIR/usr/bin"

if [ "$APK_CACHE" ]; then
	[ ! -d "$APK_CACHE" ] && mkdir "$APK_CACHE"
	$SUDO mkdir "$WORKDIR/var/cache/apk"
	$SUDO mount --bind "$APK_CACHE" "$WORKDIR/var/cache/apk"
fi

$SUDO $CHROOT_WRAPPER "$WORKDIR" <<EOC
set -ex

# setup packages
apk add !apk-tools-interactive !mandoc-apropos
apk upgrade -Ua

# use build host timezone (TODO: on top with next images)
ln -srf $(readlink -f /etc/localtime) /etc/localtime

apk add chimera-repo-user
apk add -t .base-minimal-custom-hybris base-full \
  !base-full-core base-bootstrap dinit-chimera procps turnstile \
  !base-full-firmware \
  !base-full-fonts \
  !base-full-fs e2fsprogs \
  !base-full-kernel kmod \
  !base-full-locale \
  !base-full-misc chrony file less lscpu syslog-ng opendoas \
  !base-full-net-tools iproute2 iputils rfkill \
  !base-full-net openssh \
  !base-full-sound
apk add \
  bash unudhcpd htop fastfetch neovim psmisc tree networkmanager \
  ncdu ripgrep strace llvm-binutils erofs-utils lsof vulkan-tools mesa-utils conspy bluez libinput upower \
  greetd xwayland hicolor-icon-theme fonts-cantarell-otf gnome-console gsettings-desktop-schemas wtype wlr-randr wayland-utils

# auto-login (at least first time until wayfire crashes/is otherwise killed)
tee -a /etc/greetd/config.toml >/dev/null <<'EOF'

[initial_session]
command = "wayfire"
user = "hybris"
EOF

# hybris as passwordless doas user
tee -a /etc/doas.conf >/dev/null <<'EOF'

# Give hybris user root access without requiring a password.
permit nopass hybris
EOF
chmod 640 /etc/doas.conf

# /tmp as tmpfs
tee -a /etc/fstab >/dev/null <<'EOF'
tmpfs /tmp tmpfs nosuid,nodev 0 0
tmpfs /var/log tmpfs nosuid,nodev,noexec,size=2% 0 0
EOF
EOC

# hacks mostly for downstream kernels and other scuffed configuration..
$SUDO $CHROOT_WRAPPER "$WORKDIR" <<'EOC'
set -ex

# make Halium initrd play ball and mount its stuff in a more sensible place (we want all under /android)..
# this is more or less the ideal cleanest config, rest of the stuff is cleaned up in /usr/lib/lxc-android/mount-android
# for reference: https://github.com/Halium/initramfs-tools-halium/blob/dynparts/scripts/halium
mkdir -p /var/lib/lxc/android/rootfs
touch /var/lib/lxc/android/rootfs/MOUNTED_AT_root-android

# let's make a relative /data symlink by default while at it (instead of absolute one from Halium initrd) :^)
ln -sr /android/data /data

# get a read-write rootfs by default when using Halium initrd (without having to create this in userdata root otherwise)
touch /.writable_image

# we only care about tty1 (if even that) for conspy -> GUI launch; used to apk add !base-full-console dmesg
sed -i '' 's:ACTIVE_CONSOLES=.*:ACTIVE_CONSOLES="/dev/tty1":' /etc/default/console-setup

# HACK: facilitate booting from rootfs.img loopback mounted from userdata
sed -i '' 's/exec //; /dinit_early_root_remount/ s/$/ || :/' /usr/lib/dinit.d/early/scripts/root-remount.sh

# HACK: verbose dinit logs into rootfs by default due to most likely no working VT
cat <<'EOF' > /usr/bin/preinit
#!/bin/sh
>/dinit.log
exec /usr/bin/dinit "$@" --log-level debug --log-file /dinit.log
EOF
chmod +x /usr/bin/preinit
ln -sf preinit /usr/bin/init

# HACK: avoid failing early-udev-trigger on every boot on Volla Phone X23
# - "udevadm trigger --action=add" exits with code 1
#   - X23: sc8551-standalone: Failed to write 'add' to '/sys/devices/platform/soc/11f00000.i2c/i2c-7/7-0066/power_supply/sc8551-standalone/uevent': Invalid argument
sed -i '' 's!exec /usr/bin/udevadm trigger --action=add!/usr/bin/udevadm trigger --action=add; exit 0!' /usr/libexec/dinit-devd

# CROSS HACK: workaround wlroots cannot find Xwayland binary "/usr/aarch64-chimera-linux-musl/usr/bin/Xwayland"
# https://github.com/droidian/wlroots/blob/feature/next/upgrade-0-17-4/xwayland/server.c#L454
ln -sr / /usr/aarch64-chimera-linux-musl



# HACK: facilitate booting on version <=v4.12 kernels, fixes cgroup2: unknown option "nsdelegate"
# -> is this already a default option when running on modern kernels? upstream removal of "-o nsdelegate" if so
#sed -i '' '/cgroup2/ s:$: || mount -t cgroup2 cgroup2 "/sys/fs/cgroup":' /usr/lib/dinit.d/early/scripts/cgroups.sh

# HACK: avoid getting stuck with downstream (as tested on OnePlus 5's v4.4) kernel
#sed -i '' 's!exec /usr/bin/udevadm settle!/usr/bin/udevadm settle --timeout=3; exit 0!' /usr/libexec/dinit-devd

# HACK: allow (close to) stock android kernel configs to boot without console=tty0 etc(?)
#ln -s /usr/bin/init /init
EOC

# deploy host SSH public key for seamless login to target device
pubkeys=($HOME/.ssh/id_rsa.pub)
for user in root hybris; do
	home_dir="/home/$user"
	[ "$user" = "root" ] && home_dir="/root"
	ssh_dir="${WORKDIR}${home_dir}/.ssh"
	[ -e "$ssh_dir" ] || $SUDO mkdir -p "$ssh_dir"
	cat "${pubkeys[@]}" | $SUDO tee -a "$ssh_dir/authorized_keys" >/dev/null
done

# deploy host cports public key for target device apk to avoid need for spamming --allow-untrusted
if [ -d "$CPORTS" ]; then
	email="$(git -C "$CPORTS" config user.email)"
	$SUDO cp "$CPORTS/etc/keys/$email-"*".rsa.pub" "$WORKDIR/etc/apk/keys"
fi

# apply overlay files on top of rootfs
for overlay in "${OVERLAYS[@]}"; do
	[ -d "overlays/$overlay" ] || continue
	$SUDO cp -r "overlays/$overlay"/* "$WORKDIR"
done

$SUDO $CHROOT_WRAPPER "$WORKDIR" <<'EOC'
set -ex

# install custom packages
if [ -d pkgs ]; then
	apk add pkgs/*.apk
	rm -rf pkgs
fi

# setup root & hybris users
chsh -s /bin/bash
cp -r /etc/skel/. /root/
useradd -m -G wheel,network,android_input -s /bin/bash -u 32011 hybris
# TODO: no need for this if /home/hybris didn't exist before useradd
cp -r /etc/skel/. /home/hybris/
chown -R hybris:hybris /home/hybris

# set a default password for e.g. conspy
passwd hybris <<'EOP'
1234
1234
EOP
EOC

if [ "$APK_CACHE" ]; then
	$SUDO $CHROOT_WRAPPER "$WORKDIR" <<'EOC'
set -ex

# don't keep "apk add"ed package .apks in /etc/apk/cache (/var/cache/apk) in final rootfs
apk add !apk-tools-cache
EOC
	$SUDO umount "$WORKDIR/var/cache/apk"
	$SUDO rmdir "$WORKDIR/var/cache/apk"
fi
[ "$host_arch" != "$ARCH" ] && $SUDO rm "$WORKDIR/usr/bin/qemu-$ARCH-static"
$SUDO umount "$WORKDIR"

e2fsck -fy "$OUT_ROOTFS"
