#!/bin/sh -ex
# FIXME: while we need pulseaudio-modules-droid or a similar pipewire replacement for proper audio
#        routing to internal speakers etc this is mandatory for waydroid to launch (:
apk add waydroid pipewire iptables
