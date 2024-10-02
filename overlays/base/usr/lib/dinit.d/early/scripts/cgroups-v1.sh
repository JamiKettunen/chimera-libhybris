#!/bin/sh
set -e

# cgroup mounts
_cgroupv1="/sys/fs/cgroup"
_cgroupv2="${_cgroupv1}/unified"

# cgroup v1
./early/helpers/mntpt "$_cgroupv1" || mount -o mode=0755 -t tmpfs cgroup "$_cgroupv1"
while read -r _subsys_name _hierarchy _num_cgroups _enabled; do
    [ "$_enabled" = "1" ] || continue
    _controller="${_cgroupv1}/${_subsys_name}"
    mkdir -p "$_controller"
    ./early/helpers/mntpt "$_controller" || mount -t cgroup -o "$_subsys_name" cgroup "$_controller"
done < /proc/cgroups

# cgroup v2
mkdir -p "$_cgroupv2"
./early/helpers/mntpt "$_cgroupv2" || mount -t cgroup2 -o nsdelegate cgroup2 "$_cgroupv2" || \
  mount -t cgroup2 cgroup2 "$_cgroupv2" || \
  rmdir "$_cgroupv2"
