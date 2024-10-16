#!/bin/sh -ex
apk add wayfire-droidian@hybris-cports \
  xwayland hicolor-icon-theme fonts-cantarell-otf

# auto-login (android-service@hwcomposer dep in /etc/default/agetty-tty1)
tee -a /etc/skel/.bash_profile >/dev/null <<'EOF'

if [ ! -e /run/no-wayfire ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec wayfire &> /tmp/wayfire.log
fi
EOF

# CROSS HACK: workaround wlroots cannot find Xwayland binary "/usr/aarch64-chimera-linux-musl/usr/bin/Xwayland"
# https://github.com/droidian/wlroots/blob/feature/next/upgrade-0-17-4/xwayland/server.c#L454
ln -sr / /usr/aarch64-chimera-linux-musl
ln -sr / /usr/armv7-chimera-linux-musleabihf
