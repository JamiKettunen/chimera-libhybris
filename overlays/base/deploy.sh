#!/bin/sh -ex
apk add lxc-android@hybris-cports libgbinder-progs@hybris-cports dinit@hybris-cports \
    libhybris-test-progs@hybris-cports libegl-hybris@hybris-cports libgles2-hybris@hybris-cports libopencl-hybris@hybris-cports \
    libgles1-hybris@hybris-cports

# let's make a relative /data symlink instead of absolute one by default coming from Halium initrd :^)
ln -sr /android/data /data

# get a read-write rootfs by default when using Halium initrd (without having to create this in userdata root otherwise)
touch /.writable_image

# we only care about tty1 (if even that) for conspy -> GUI launch; used to apk add !base-full-console dmesg
[ -f /etc/default/console-setup ] && sed -i '' 's:ACTIVE_CONSOLES=.*:ACTIVE_CONSOLES="/dev/tty1":' /etc/default/console-setup

# HACK: init wrapper to get verbose dinit logs in rootfs /dinit.log by default (typically no functional VT framebuffer)
ln -sf preinit /usr/bin/init # originally pointing to dinit

# HACK: allow (close to) stock android kernel configs to boot without console=tty0 etc(?)
#ln -s /usr/bin/init /init
