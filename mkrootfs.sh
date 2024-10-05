#!/bin/bash
: "${DATE:=20240707}"
: "${SIZE:=2G}"
: "${OUT_ROOTFS:=/tmp/chimera-rootfs.img}"
: "${WORKDIR:=/tmp/chimera-rootfs}" # /mnt
[ -z "${SUDO+x}" ] && SUDO="sudo"
: "${CPORTS:=$HOME/cports}"
: "${CPORTS_PACKAGES_DIR:=packages}"
: "${CHROOT_WRAPPER:=chimera-chroot}" # xchroot arch-chroot
[ -z "${APK_CACHE+x}" ] && APK_CACHE="apk-cache"
: "${ARCH:=aarch64}"
[ -z ${PASSWD+x} ] && PASSWD="1234" # "" = only login via SSH pubkey (or on-device autologin)
if [ -z "$OVERLAYS" ]; then
	OVERLAYS=(
		base # Most default file-based configuration shared across all devices
		usbnet # RNDIS + internet over USB
	)
else
	OVERLAYS=($OVERLAYS)
fi

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
qemu_bin=""

set -x # log every executed command
mountpoint -q "$WORKDIR" && $SUDO umount -R "$WORKDIR"
rm -f "$OUT_ROOTFS"

fallocate -l $SIZE "$OUT_ROOTFS"
# NOTE: features disabled that makes halium initrd & recoveries unhappy to work with the ext4 image files
# FEATURE_C12 (orphan_file): https://www.mail-archive.com/debian-bugs-dist@lists.debian.org/msg1896675.html
# The below works with Halium 9 recovery + e2fsck 1.42.9 (28-Dec-2013)
mkfs.ext4 -b 4096 -O '^metadata_csum,^orphan_file' -m 0 -F "$OUT_ROOTFS"

[ ! -d "$WORKDIR" ] && mkdir -p "$WORKDIR"
$SUDO mount "$OUT_ROOTFS" "$WORKDIR"

[ -f "$tarball" ] || wget "$url"
$SUDO tar xfp "$tarball" -C "$WORKDIR"

if [ "$host_arch" != "$ARCH" ]; then
	qemu_bin="$(command -v qemu-$ARCH-static)"
	[ -z "$qemu_bin" ] && qemu_bin="$(command -v qemu-$ARCH)"
	if [ -z "$qemu_bin" ]; then
		echo "ERROR: Missing proper binfmt + QEMU user setup for $ARCH (cmd:qemu-$ARCH{-static,})"
		exit 1
	fi
	$SUDO cp "$qemu_bin" "$WORKDIR/usr/bin"
fi

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
  ncdu ripgrep strace llvm-binutils erofs-utils lsof vulkan-tools mesa-utils conspy bluez libinput evtest upower \
  greetd xwayland hicolor-icon-theme fonts-cantarell-otf gnome-console gsettings-desktop-schemas wtype wlr-randr wayland-utils

# FIXME: while we need pulseaudio-modules-droid or a similar pipewire replacement for proper audio
#        routing to internal speakers etc this is mandatory for waydroid to launch (:
apk add pipewire iptables

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

# /tmp as tmpfs
tee -a /etc/fstab >/dev/null <<'EOF'
tmpfs /tmp tmpfs nosuid,nodev 0 0
tmpfs /var/log tmpfs nosuid,nodev,noexec,size=2% 0 0
EOF
EOC

# hacks mostly for downstream kernels and other scuffed configuration..
$SUDO $CHROOT_WRAPPER "$WORKDIR" <<'EOC'
set -ex

# let's make a relative /data symlink instead of absolute one by default coming from Halium initrd :^)
ln -sr /android/data /data

# get a read-write rootfs by default when using Halium initrd (without having to create this in userdata root otherwise)
touch /.writable_image

# we only care about tty1 (if even that) for conspy -> GUI launch; used to apk add !base-full-console dmesg
sed -i '' 's:ACTIVE_CONSOLES=.*:ACTIVE_CONSOLES="/dev/tty1":' /etc/default/console-setup

# HACK: facilitate booting from rootfs.img loopback mounted from userdata
sed -i '' 's/exec //; /dinit_early_root_remount/ s/$/ || :/' /usr/lib/dinit.d/early/scripts/root-remount.sh

# HACK: facilitate booting on version <=v4.12 kernels, fixes:
# - cgroup2: unknown option "nsdelegate"
#   -> is this already a default mount option when running on modern kernels? drop always if so
#   - cheeseburger/dumpling?: mount without the option
# - mount: /sys/fs/cgroup: unknown filesystem type 'cgroup2'
#   - yggdrasil: fallback mount legacy non-unified cgroup hierarchy
#   - cgroups-v1.sh source: https://github.com/chimera-linux/dinit-chimera/commit/c43985d
sed -i '' '/cgroup2/ s;$; || mount -t cgroup2 cgroup2 "/sys/fs/cgroup" || ./early/scripts/cgroups-v1.sh;' /usr/lib/dinit.d/early/scripts/cgroups.sh

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

# deploy host cports public key for target device apk to avoid need for spamming
# "--allow-untrusted" as well as configuration to allow for overlays/*/deploy.sh
# to "apk add <package>@hybris-cports"
if [ -d "$CPORTS" ]; then
	email="$(git -C "$CPORTS" config user.email)"
	$SUDO cp "$CPORTS/etc/keys/$email-"*".rsa.pub" "$WORKDIR/etc/apk/keys"

	$SUDO mkdir "$WORKDIR/hybris-cports-packages"
	$SUDO mount --bind "$CPORTS/$CPORTS_PACKAGES_DIR" "$WORKDIR/hybris-cports-packages"
	for entry in "$CPORTS/$CPORTS_PACKAGES_DIR"/*; do
		[ -d "$entry" ] || continue # ignore "cbuild-aarch64.lock" etc files

		entries="@hybris-cports /hybris-cports-packages/${entry##*/}"
		if [ -d "$entry/debug" ]; then
			entries+="
@hybris-cports /hybris-cports-packages/${entry##*/}/debug"
		fi
		$SUDO tee -a "$WORKDIR/etc/apk/repositories.d/99-chimera-libhybris.list" >/dev/null <<EOF
$entries
EOF
	done
fi

# apply overlay files on top of rootfs
for overlay in "${OVERLAYS[@]}"; do
	[ -d "overlays/$overlay" ] || continue
	$SUDO cp -r "overlays/$overlay"/* "$WORKDIR"
	if [ -f "$WORKDIR/deploy-host.sh" ]; then
		(. "$WORKDIR/deploy-host.sh")
		$SUDO rm "$WORKDIR/deploy-host.sh"
	fi
	if [ -f "$WORKDIR/deploy.sh" ]; then
		$SUDO chmod +x "$WORKDIR/deploy.sh"
		$SUDO $CHROOT_WRAPPER "$WORKDIR" /deploy.sh
		$SUDO rm "$WORKDIR/deploy.sh"
	fi
done

if [ -d "$CPORTS" ]; then
	$SUDO umount "$WORKDIR/hybris-cports-packages"
	# now that we no longer have host apks around convince the rootfs apk to
	# stay happy with the @hybris-cports tagged custom packages in /etc/apk/world
	while read -r host_apkindex; do
		rootfs_apkindex="$WORKDIR/hybris-cports-packages/${host_apkindex#"$CPORTS/$CPORTS_PACKAGES_DIR/"}"
		$SUDO mkdir -p "${rootfs_apkindex%/*}"
		$SUDO cp "$host_apkindex" "$rootfs_apkindex"
	done < <(find "$CPORTS/$CPORTS_PACKAGES_DIR/" -name 'APKINDEX*')
fi

$SUDO $CHROOT_WRAPPER "$WORKDIR" <<EOC
set -ex

# setup root & hybris users
chsh -s /bin/bash
cp -r /etc/skel/. /root/
useradd -m -G wheel,network,android_input -s /bin/bash -u 32011 hybris
# TODO: no need for this if /home/hybris didn't exist before useradd
cp -r /etc/skel/. /home/hybris/
chown -R hybris:hybris /home/hybris

# set a default password for e.g. conspy
if [ "$PASSWD" ]; then
	passwd hybris <<EOP
$PASSWD
$PASSWD
EOP
fi

# harden perms (non-root cannot do anything)
chmod 640 /etc/doas.conf
EOC

# Function which can potentially be defined in config files to run at this stage
if type post_mkrootfs &>/dev/null; then
	post_mkrootfs
fi

if [ "$APK_CACHE" ]; then
	$SUDO $CHROOT_WRAPPER "$WORKDIR" <<'EOC'
set -ex

# don't keep "apk add"ed package .apks in /etc/apk/cache (/var/cache/apk) in final rootfs
apk add !apk-tools-cache
EOC
	$SUDO umount "$WORKDIR/var/cache/apk"
	$SUDO rmdir "$WORKDIR/var/cache/apk"
fi
[ "$qemu_bin" ] && $SUDO rm "$WORKDIR/usr/bin/${qemu_bin##*/}"
$SUDO umount "$WORKDIR"

e2fsck -fy "$OUT_ROOTFS"
