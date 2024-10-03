#!/bin/sh
set -e

# FIXME: launching wireplumber causes a kernel panic in mtk_i2s2_adc2_pcm_hw_params() as follows:
# https://paste.c-net.org/ytsftyobtyof
# without it we can still at least launch waydroid even if stuff otherwise may be cooked :^)
# NOTE: wireplumber updates WILL break the boot again for now...
# -> replace with "ln -s /dev/null /etc/dinit.d/user/wireplumber" after dinit 0.19?
rm /usr/lib/dinit.d/user/boot.d/wireplumber
