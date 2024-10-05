#!/bin/bash

# deploy host SSH public key for seamless login to target device
if [ "$SSH_PUBKEYS" ]; then
	# shellcheck disable=SC2206
	pubkeys=($SSH_PUBKEYS)
else
	pubkeys=("$HOME/.ssh/id_"*".pub")
fi
for pubkey in "${pubkeys[@]}"; do
	if [ ! -f "$pubkey" ]; then
		cat <<EOF
ERROR: $pubkey doesn't exist! Properly configure SSH_PUBKEYS, run 'ssh-keygen'
or disable the 'host-ssh-pubkey' overlay!
EOF
		exit 1
	fi
done
for user in root hybris; do
	home_dir="/home/$user"
	[ "$user" = "root" ] && home_dir="/root"
	ssh_dir="${WORKDIR}${home_dir}/.ssh"
	[ -e "$ssh_dir" ] || $SUDO mkdir -p "$ssh_dir"
	cat "${pubkeys[@]}" | $SUDO tee -a "$ssh_dir/authorized_keys" >/dev/null
done
