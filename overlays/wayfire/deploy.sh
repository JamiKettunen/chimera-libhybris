#!/bin/sh -ex
apk add wayfire-droidian@hybris-cports \
  greetd xwayland hicolor-icon-theme fonts-cantarell-otf

# auto-login (at least first time until wayfire crashes/is otherwise killed)
tee -a /etc/greetd/config.toml >/dev/null <<'EOF'

[initial_session]
command = "wayfire"
user = "hybris"
EOF

# CROSS HACK: workaround wlroots cannot find Xwayland binary "/usr/aarch64-chimera-linux-musl/usr/bin/Xwayland"
# https://github.com/droidian/wlroots/blob/feature/next/upgrade-0-17-4/xwayland/server.c#L454
ln -sr / /usr/aarch64-chimera-linux-musl
ln -sr / /usr/armv7-chimera-linux-musleabihf
