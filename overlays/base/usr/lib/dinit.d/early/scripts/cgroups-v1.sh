#!/bin/sh
# adapted https://github.com/chimera-linux/dinit-chimera/commit/c43985d removals using
# /usr/lib/dinit.d/early/helpers/mnt and without attempting non-functional v2 stuff in this fallback
set -e

# cgroup mounts
_cgroupv1="/sys/fs/cgroup"

# cgroup v1
/usr/lib/dinit.d/early/helpers/mnt try "$_cgroupv1" cgroup tmpfs "mode=0755"
while read -r _subsys_name _hierarchy _num_cgroups _enabled; do
    [ "$_enabled" = "1" ] || continue
    _controller="${_cgroupv1}/${_subsys_name}"
    mkdir -p "$_controller"
    /usr/lib/dinit.d/early/helpers/mnt try "$_controller" cgroup cgroup "$_subsys_name"
done < /proc/cgroups
