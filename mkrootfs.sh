#!/usr/bin/env bash
: "${ARCH:=aarch64}" # everything else untested
: "${DATE:=20240707}" # https://repo.chimera-linux.org/live/
: "${FLAVOR:=bootstrap}" # full
: "${WORKDIR:=/tmp/chimera-rootfs}" # /mnt
: "${OUT_ROOTFS:=/tmp/chimera-rootfs.img}"
: "${SIZE:=2G}"
[ -z "${APK_CACHE+x}" ] && APK_CACHE="apk-cache"
: "${CPORTS:=cports}" # ~/cports
: "${CPORTS_PACKAGES_DIR:=packages}"
[ -z ${PASSWD+x} ] && PASSWD="1234" # "" = only login via SSH pubkey (or on-device autologin)
[ -z ${APK_INTERACTIVE+x} ] && APK_INTERACTIVE="yes" # make empty to disable
[ -z "${SUDO+x}" ] && SUDO="sudo" # doas
: "${FETCH:=wget}" # fetch "curl -O"
: "${QEMU_USER_STATIC:=qemu-$ARCH-static}" # qemu-$ARCH; for cross-architecture rootfs builds
: "${CHROOT_WRAPPER:=chimera-chroot}" # xchroot arch-chroot
if [ -z "$OVERLAYS" ]; then
	OVERLAYS=(
		base # Most default file-based configuration shared across all devices
		usbnet # RNDIS + internet over USB
		host-timezone # Use build host timezone
		host-ssh-pubkey # Seamless SSH login to target device from build host
	)
else
	# shellcheck disable=SC2128,SC2206
	OVERLAYS=($OVERLAYS)
fi
set -e # exit on any error
cd "$(readlink -f "$(dirname "$0")")" # dir of this script

verify_host_cmd() {
	local cmd="$1" cmd_value="${!1}"
	[ -x "$(command -v "${cmd_value%% *}")" ] && return
	local options="$2" error_msg="$3" cmd_opt cmd_error="$cmd_value|"
	while read -r cmd_opt; do
		if [ -x "$(command -v "${cmd_opt%% *}")" ]; then
			eval "$cmd='$cmd_opt'"
			return
		fi
		[[ "${cmd_error}" = *"${cmd_opt%% *}|"* ]] || cmd_error+="${cmd_opt%% *}|"
	done < <(echo "${options//|/$'\n'}")
	: "${error_msg:="No valid $cmd host executable found matching '${cmd_error::-1}'!"}"
	echo "$error_msg"
	exit 1
}
chroot_exec() { $SUDO $CHROOT_WRAPPER "$WORKDIR" "$@"; }
chroot_exec_sh() { chroot_exec /bin/sh -c "$1"; }

if [ ! -f "$1" ]; then
	cat <<EOF
You must specify a config to use, for example:

    $0 config.vidofnir.sh

EOF
	exit 1
fi
# shellcheck disable=SC1090
. "$1"
[ -f config.local.sh ] && . config.local.sh
if [ "$ARCH" = "aarch64" ] && [ "$HALIUM_ARM32" ] && [ -z "$HALIUM_ARM32_FORCE" ]; then
	echo "32-bit Android with 64-bit Chimera Linux userspace is unsupported due to 64-bit libhybris being
unable to link 32-bit Android libraries; set HALIUM_ARM32_FORCE to override this anyway and continue!"
	exit 1
fi

[ "$SUDO" ] && verify_host_cmd SUDO "sudo|doas"
verify_host_cmd FETCH "wget|fetch|curl -O"
verify_host_cmd CHROOT_WRAPPER "chimera-chroot|xchroot|arch-chroot"

[ -d "$CPORTS" ] || CPORTS="$HOME/cports"
if [ ! -d "$CPORTS/user/libhybris" ]; then
	cat <<EOF
${CPORTS/$HOME/\~} isn't an https://github.com/JamiKettunen/cports/tree/hybris clone!
You may configure CPORTS if it's already cloned elsewhere
EOF
	exit 1
fi
if ! compgen -G "$CPORTS/$CPORTS_PACKAGES_DIR/user/*/libhybris*.apk" >/dev/null; then
	cat <<EOF
${CPORTS/$HOME/\~}/$CPORTS_PACKAGES_DIR doesn't contain libhybris package build artifacts, consult
README.md for mandatory extra package building steps before continuing! You may configure
CPORTS_PACKAGES_DIR if you used ./cbuild --repository-path ...
EOF
	exit 1
fi

tarball="chimera-linux-$ARCH-ROOTFS-$DATE-$FLAVOR.tar.gz"
url="https://repo.chimera-linux.org/live/$DATE/$tarball"
host_arch=$(uname -m)

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

[ ! -f "$tarball" ] && $FETCH "$url"
$SUDO tar xfp "$tarball" -C "$WORKDIR"

if [ "$host_arch" != "$ARCH" ]; then
	verify_host_cmd QEMU_USER_STATIC "qemu-$ARCH-static|qemu-$ARCH" \
		"Missing binfmt + QEMU user setup for $ARCH (cmd:qemu-$ARCH{,-static})"
	QEMU_USER_STATIC="$(command -v "$QEMU_USER_STATIC")"
	$SUDO cp "$QEMU_USER_STATIC" "$WORKDIR/usr/bin"
fi

if [ "$APK_CACHE" ]; then
	[ ! -d "$APK_CACHE" ] && mkdir "$APK_CACHE"
	$SUDO mkdir "$WORKDIR/var/cache/apk"
	$SUDO mount --bind "$APK_CACHE" "$WORKDIR/var/cache/apk"
fi

# fix networking with arch-chroot at least which doesn't do anything (bind-mount) otherwise
$SUDO touch "$WORKDIR/etc/resolv.conf"

chroot_exec /bin/sh <<EOC
set -ex

# setup packages
[ "$APK_CACHE" ] || apk add !apk-tools-cache
apk add !apk-tools-interactive !mandoc-apropos
apk upgrade -Ua

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

# hacks mostly for downstream kernels and other scuffed configuration..

# let's make a relative /data symlink instead of absolute one by default coming from Halium initrd :^)
ln -sr /android/data /data

# get a read-write rootfs by default when using Halium initrd (without having to create this in userdata root otherwise)
touch /.writable_image

# we only care about tty1 (if even that) for conspy -> GUI launch; used to apk add !base-full-console dmesg
sed -i '' 's:ACTIVE_CONSOLES=.*:ACTIVE_CONSOLES="/dev/tty1":' /etc/default/console-setup

# HACK: verbose dinit logs into rootfs by default due to most likely no working VT
cat <<'EOF' > /usr/bin/preinit
#!/bin/sh
>/dinit.log
exec /usr/bin/dinit "\$@" --log-level debug --log-file /dinit.log
EOF
chmod +x /usr/bin/preinit
ln -sf preinit /usr/bin/init

# CROSS HACK: workaround wlroots cannot find Xwayland binary "/usr/aarch64-chimera-linux-musl/usr/bin/Xwayland"
# https://github.com/droidian/wlroots/blob/feature/next/upgrade-0-17-4/xwayland/server.c#L454
ln -sr / /usr/aarch64-chimera-linux-musl



# HACK: allow (close to) stock android kernel configs to boot without console=tty0 etc(?)
#ln -s /usr/bin/init /init
EOC

# deploy host cports public key for target device apk to avoid need for spamming
# "--allow-untrusted" as well as configuration to allow for overlays/*/deploy.sh
# to "apk add <package>@hybris-cports"
$SUDO cp "$CPORTS/etc/keys/"*".rsa.pub" "$WORKDIR/etc/apk/keys"

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

# apply overlay files on top of rootfs
for overlay in "${OVERLAYS[@]}"; do
	overlay_dir="$PWD/overlays/$overlay"
	[ -d "$overlay_dir" ] || continue
	$SUDO cp -R "$overlay_dir"/* "$WORKDIR"

	while read -r overlay_symlink; do
		[ -f "$overlay_symlink" ] || continue # ignore non-existing sources and directories
		overlay_source="$(readlink -f "$overlay_symlink")"
		[[ "$overlay_source" = "$overlay_dir/"* ]] && continue # ignore relative symlinks only inside current overlay (rootfs)
		[[ "$overlay_source" = "$PWD/overlays/"* ]] || continue # ignore host files outside other overlays
		echo "Replacing rootfs symlink (pointing outside $overlay overlay) with chimera-libhybris
${overlay_source/$PWD\//}"
		rootfs_symlink="${overlay_symlink/$overlay_dir/$WORKDIR}"
		$SUDO rm "$rootfs_symlink"
		$SUDO cp "$overlay_source" "$rootfs_symlink"
	done < <(find "$overlay_dir" -type l)

	if [ -f "$WORKDIR/deploy-host.sh" ]; then
		(. "$WORKDIR/deploy-host.sh")
		$SUDO rm "$WORKDIR/deploy-host.sh"
	fi
	if [ -f "$WORKDIR/deploy.sh" ]; then
		$SUDO chmod +x "$WORKDIR/deploy.sh"
		chroot_exec /deploy.sh
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

chroot_exec /bin/sh <<EOC
set -ex

# setup root & hybris users
chsh -s /bin/bash
cp -R /etc/skel/. /root/
[ -d /home/hybris ] && user_home_pre=1 || user_home_pre=0
useradd -m -G wheel,network,android_input -s /bin/bash -u 32011 hybris
if [ "\$user_home_pre" -eq 1 ]; then
	# useradd doesn't copy anything from skel directory if the home dir already exists
	cp -R /etc/skel/. /home/hybris/
fi
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

chroot_exec /bin/sh <<EOC
set -ex

# as user preference bring back apk interactive mode by default once all scripts done
if [ "$APK_INTERACTIVE" ]; then
	apk add apk-tools-interactive
fi

# leave some final disk usage info at the end
df -h | grep '^Filesystem\|/$'
EOC

if [ "$APK_CACHE" ]; then
	chroot_exec /bin/sh <<'EOC'
set -ex

# don't keep "apk add"ed package .apks in /etc/apk/cache (/var/cache/apk) in final rootfs
apk add !apk-tools-cache
EOC
	$SUDO umount "$WORKDIR/var/cache/apk"
	chroot_exec /bin/sh <<'EOC'
set -ex

# provide some default catalog of repos in case first booted without networking
apk update
EOC
fi
[ "$host_arch" != "$ARCH" ] && $SUDO rm "$WORKDIR/usr/bin/${QEMU_USER_STATIC##*/}"
$SUDO umount "$WORKDIR"

e2fsck -fy "$OUT_ROOTFS"
