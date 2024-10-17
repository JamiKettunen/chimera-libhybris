#!/bin/bash

if [ ! -f "$WORKDIR/etc/elogind/logind.conf" ]; then
    chroot_exec_sh "apk add elogind"
fi
