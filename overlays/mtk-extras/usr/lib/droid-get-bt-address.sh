#!/bin/sh

# wait for this always to avoid occasional "Failed to connect to bluetooth binder service"
WAITFORSERVICE_VALUE="Ready" waitforservice vendor.service.nvram_init

# now wait for BT kernel module etc to be fully loaded to avoid hanging on
# "Bluetooth binder service failed" on some devices (e.g. volla-yggdrasil)
if [ -x /vendor/bin/wmt_launcher ]; then
	# wmt_launcher is known to exist at least up to Helio G99 (MT6789)
	WAITFORSERVICE_VALUE="yes" waitforservice vendor.connsys.formeta.ready
else
	# TODO: "waitforservice init.svc.wlan_assistant" on volla-algiz/nothing-tetris etc?
	# -> modules loaded at the same time as this is set... also wait for "wlan_assistant" service?
	#    -> perhaps look for new props again..
	WAITFORSERVICE_VALUE="yes" waitforservice vendor.connsys.driver.ready
fi

# address already setup on a previous boot, nothing more to do here
[ -f /var/lib/bluetooth/board-address ] && exit 0

bt_mac_addr="$(hexdump -s 0 -n 6 -ve '/1 "%02X:"' /android/mnt/vendor/nvdata/APCFG/APRDEB/BT_Addr)"
[ "$bt_mac_addr" ] || exit 1

echo "${bt_mac_addr%:*}" > /var/lib/bluetooth/board-address
