#!/usr/bin/env sh
set -e
: ${RNDIS_USB_NET:=10.15.19.0/24}
: ${RNDIS_USB_HOST:=10.15.19.100}
: ${RNDIS_USB_DEVICE:=10.15.19.82}

# TODO: use nftables instead?
sudo sysctl net.ipv4.ip_forward=1 >/dev/null
sudo iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A FORWARD -s $RNDIS_USB_NET -j ACCEPT
sudo iptables -A POSTROUTING -t nat -j MASQUERADE -s $RNDIS_USB_NET

MANUAL_STEPS_NEEDED=1
if ip a | grep -q "inet $RNDIS_USB_HOST"; then
	(set -x; ssh root@$RNDIS_USB_DEVICE dinitctl start usb-internet) && MANUAL_STEPS_NEEDED=0
fi

if [ $MANUAL_STEPS_NEEDED -eq 1 ]; then
        cat <<'EOF'
>> Now run 'dinitctl start usb-internet' or 'ip route add default via $RNDIS_USB_HOST dev usb0' on your device!
   (running 'dinitctl stop usb-internet' or 'ip route del default via $RNDIS_USB_HOST' will undo this)
EOF
fi

cat <<'EOF'
>> NOTE: Consider 'apk add resolvconf-none' if in early bringup without WLAN for a while to avoid the need to
   e.g. 'rm /etc/resolv.conf; echo "nameserver 1.1.1.1" > /etc/resolv.conf'
EOF
