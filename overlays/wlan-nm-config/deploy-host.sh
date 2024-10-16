#!/usr/bash
: "${DNS:=1.1.1.1}"

# preconfigure Wi-Fi network to connect to on initial boot out of the box
if [ -z "$WLAN_SSID" ]; then
    echo "You must configure at least a WLAN_SSID to use wlan-nm-config overlay!"
    exit 1
fi

nmconnections="$WORKDIR/etc/NetworkManager/system-connections"
if [ ! -d "$nmconnections" ]; then
    chroot_exec_sh "apk add networkmanager"
fi

# TODO: determine if WLAN_ADDRESS is IPv4/6 and configure approprietaly
nmconnection="$nmconnections/$WLAN_SSID.nmconnection"
$SUDO tee "$nmconnection" <<EOF >/dev/null
[connection]
id=$WLAN_SSID
uuid=$(uuidgen)
type=wifi

[wifi]
ssid=$WLAN_SSID

[ipv4]
dns=${DNS//,/;};
ignore-auto-dns=true
EOF
if [ "$WLAN_PASSWD" ]; then
    $SUDO tee -a "$nmconnection" <<EOF >/dev/null

[wifi-security]
key-mgmt=wpa-psk
psk=$WLAN_PASSWD
EOF
fi
if [ "$WLAN_ADDRESS" ] && [ "$WLAN_GATEWAY" ]; then
    $SUDO tee -a "$nmconnection" <<EOF >/dev/null

[ipv4]
method=manual
address1=$WLAN_ADDRESS,$WLAN_GATEWAY
EOF
fi
$SUDO chmod 600 "$nmconnection"
