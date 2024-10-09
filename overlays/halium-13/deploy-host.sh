#!/bin/bash
pkg_suffix=${HALIUM_ARM32:+-arm32}
chroot_exec_sh "apk add halium-gsi-13.0${pkg_suffix}@hybris-cports"
