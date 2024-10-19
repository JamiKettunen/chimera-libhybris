#!/bin/sh

# wait for this always to avoid occasional "Failed to connect to bluetooth binder service"
WAITFORSERVICE_VALUE="Ready" waitforservice vendor.service.nvram_init

# now wait for BT kernel module etc to be fully loaded to avoid hanging on
# "Bluetooth binder service failed" on some devices (e.g. volla-yggdrasil)
WAITFORSERVICE_VALUE="yes" waitforservice vendor.connsys.formeta.ready

# address already setup on a previous boot, nothing more to do here
[ -f /var/lib/bluetooth/board-address ] && exit 0

bt_mac_addr="$(hexdump -s 0 -n 6 -ve '/1 "%02X:"' /android/mnt/vendor/nvdata/APCFG/APRDEB/BT_Addr)"
[ "$bt_mac_addr" ] || exit 1

echo "${bt_mac_addr%:*}" > /var/lib/bluetooth/board-address
