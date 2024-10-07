#!/usr/bash

# preconfigure Wi-Fi network to connect to on initial boot out of the box
if [ -z "$WLAN_SSID" ]; then
    echo "You must configure at least a WLAN_SSID to use wlan-nm-config overlay!"
    exit 1
fi

nmconnection="$WORKDIR/etc/NetworkManager/system-connections/$WLAN_SSID.nmconnection"
$SUDO tee "$nmconnection" <<EOF >/dev/null
[connection]
id=$WLAN_SSID
uuid=$(uuidgen)
type=wifi

[wifi]
ssid=$WLAN_SSID
EOF
if [ "$WLAN_PASSWD" ]; then
    $SUDO tee -a "$nmconnection" <<EOF >/dev/null

[wifi-security]
key-mgmt=wpa-psk
psk=$WLAN_PASSWD
EOF
fi
if [ "$WLAN_ADDRESS" ] && [ "$WLAN_GATEWAY" ]; then
    # TODO: determine if WLAN_ADDRESS if IPv4/6 and configure approprietaly
    $SUDO tee -a "$nmconnection" <<EOF >/dev/null

[ipv4]
method=manual
address1=$WLAN_ADDRESS,$WLAN_GATEWAY
EOF
fi
$SUDO chmod 600 "$nmconnection"
