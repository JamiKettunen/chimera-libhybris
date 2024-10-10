#!/bin/sh
# adapted https://github.com/chimera-linux/dinit-chimera/commit/c43985d removals using
# ./early/helpers/mntpt and without attempting non-functional v2 stuff in this fallback
set -e

# cgroup mounts
_cgroupv1="/sys/fs/cgroup"

# cgroup v1
./early/helpers/mntpt "$_cgroupv1" || mount -o mode=0755 -t tmpfs cgroup "$_cgroupv1"
while read -r _subsys_name _hierarchy _num_cgroups _enabled; do
    [ "$_enabled" = "1" ] || continue
    _controller="${_cgroupv1}/${_subsys_name}"
    mkdir -p "$_controller"
    ./early/helpers/mntpt "$_controller" || mount -t cgroup -o "$_subsys_name" cgroup "$_controller"
done < /proc/cgroups
