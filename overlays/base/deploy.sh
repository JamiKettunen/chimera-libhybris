#!/bin/sh -ex
apk add base-hybris@hybris-cports

# we only care about tty1 (if even that) for conspy -> GUI launch; used to apk add !base-full-console dmesg
[ -f /etc/default/console-setup ] && sed -i '' 's:ACTIVE_CONSOLES=.*:ACTIVE_CONSOLES="/dev/tty1":' /etc/default/console-setup

# create /userdata Halium initrd would normally make with rw rootfs (we don't touch /.writable_image
# to fix both early-root-{remount,fsck} for loopback images at least)
mkdir /userdata

# let's make a relative /data symlink instead of absolute one by default coming from Halium initrd :^)
ln -sr /android/data /data

# HACK: init wrapper to get verbose dinit logs in rootfs /dinit.log by default (typically no functional VT framebuffer)
ln -sf preinit /usr/bin/init # originally pointing to dinit

# HACK: allow (close to) stock android kernel configs to boot without console=tty0 etc(?)
#ln -s /usr/bin/init /init
