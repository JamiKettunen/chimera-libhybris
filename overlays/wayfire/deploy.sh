#!/bin/sh -ex
apk add wayfire-hwcomposer@hybris-cports \
  xwayland hicolor-icon-theme fonts-cantarell-otf

# auto-login (android-service@hwcomposer dep in /etc/default/agetty-tty1)
tee -a /etc/skel/.bash_profile >/dev/null <<'EOF'

if [ ! -e /run/no-wayfire ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec wayfire &>> /tmp/wayfire.log
fi
EOF
