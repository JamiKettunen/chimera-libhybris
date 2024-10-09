#!/bin/bash

# use build host timezone (or alternatively another configured one) on target device
if [ -z "$TIMEZONE" ]; then
	TIMEZONE=$(readlink -f /etc/localtime)
elif [[ "$TIMEZONE" != "/"* ]]; then
	TIMEZONE="/usr/share/zoneinfo/$TIMEZONE"
fi
chroot_exec_sh "ln -srf $TIMEZONE /etc/localtime"
