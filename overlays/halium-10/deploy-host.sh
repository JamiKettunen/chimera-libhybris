#!/bin/bash
pkg_suffix=${HALIUM_ARM32:+-arm32}
[ "$ARCH" = "armv7" ] && pkg_suffix="-arm32"
chroot_exec_sh "apk add halium-gsi-10.0${pkg_suffix}@hybris-cports"
