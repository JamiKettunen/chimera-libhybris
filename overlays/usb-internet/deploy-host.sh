#!/bin/bash
: "${DNS:=1.1.1.1}"
chroot_exec_sh "apk add resolvconf-none"
while read -r dns; do
	echo "nameserver $dns" | $SUDO tee -a "$WORKDIR/etc/resolv.conf" >/dev/null
done < <(echo "${DNS//,/$'\n'}")
