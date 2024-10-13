# Debugging
You may not successfully boot Chimera Linux on the first try with working USB access but that can
be expected.


## Chroot in
The following has been tested as working via UBports recovery (but TWRP etc should similarly work
too where ever you may have root):
```sh
adb shell

mountpoint -q /data || mount /data
mkdir -p /root
e2fsck -fy /data/ubuntu.img

mount /data/ubuntu.img /root
for pseudofs in proc sys dev; do mount --bind /$pseudofs /root/$pseudofs; done
env -i HOME=/root PS1='(chroot) \w \$ ' TERM=xterm-256color $(which chroot) /root /bin/bash -l
```
For installing package files you can `adb push whatever.apk /root` and in chroot e.g.
`apk --no-network add /*.apk && rm /*.apk`

For tearing it down `adb shell 'umount /root/proc /root/sys /root/dev /root /data; sync && reboot'`
from host should do the trick


## Inspect kernel panic logs
If suspected and the device actually writes these the usual way they can be conveniently obtained
via recovery mode (even without chroot):
```
mount pstore -t pstore /sys/fs/pstore
cat /sys/fs/pstore/console-ramoops
```
On some older v3.x series kernels especially this may instead be doable via `cat /proc/last_kmsg`.


## Store logs on-disk
Due to downstream kernels being pretty spammy which would constantly keep growing especially
`/var/log/kern.log` the whole directory has `tmpfs` mounted on boot. Undo this from `chroot` as
needed to get debug logs viewable in recovery
```sh
sed -i '' 's/^[^#]*log/#&/' /etc/fstab
```


## Device reboots quickly and /dinit-panic.log exists
This is created by [`/usr/bin/dinit-panic`](overlays/base/usr/bin/dinit-panic) which you may tweak
in chroot, but you should continue to the section below.

Note that on some devices it may not reboot automatically to recovery mode on failure but just keeps
bootlooping without success, so be sure to check for this file in rootfs after entering recovery
manually!


## Getting debug logs out of dinit
We can create a `/usr/bin/init` wrapper script for debug logs from `chroot` (done by default):
```sh
cat <<'EOF' > /usr/bin/preinit
#!/bin/sh
>/dinit.log
exec /usr/bin/dinit "$@" --log-level debug --log-file /dinit.log
EOF
chmod +x /usr/bin/preinit
ln -sf preinit /usr/bin/init
```
To include every ran command from early scripts in the logs as well (as seen below) you can:
```
echo 'set -x' >> /usr/lib/dinit.d/early/scripts/common.sh
```
Similarly to include every ran command from `/etc/rc.local`:
```
sed -i '' '1a\
set -x
' /etc/rc.local
```
Assuming a failed boot without USB access either wait ~15 seconds and reboot forcefully, then enter
`chroot` again and `cat /dinit.log`:
```
dinit: Starting system
dinit: service early-env started.
INIT: root-remount
+ exec mount -o remount,ro,rshared /
mount: /: mount point is busy.
       dmesg(1) may have more information after failed mount system call.
dinit: Service early-root-remount command failed with exit code 32
dinit: service early-root-remount failed to start.
...
```
When done/issue fixed you may restore back the original init:
```sh
rm /dinit.log
ln -sf dinit /usr/bin/init
```


## Disabling potentially problematic services
In chroot (see above `Chroot in` section) you can try disabling each of the following one by one
in case your device is e.g. rebooting in a loop while trying to boot:
<!-- TODO: android-bluetooth -->
```sh
# at first best to try just avoiding graphical/user stuff from launching
dinitctl -o disable greetd

# only useful for wlan really which can be dealt with later (keep in mind in some cases Wi-Fi may
# be up and working before USB if you're unlucky... see README.md about wlan-nm-config overlay)
dinitctl -o disable networkmanager

# running Halium container shouldn't be mandatory for basic USB access (though this is sadly
# changing and becoming the case on modern QCOM platforms at least unless worked around...)
# alternatively "apk add !{lxc-android,halium-wrappers}-dinit-links"
rm /usr/lib/dinit.d/boot.d/{android.target,android-hwcomposer}

# while the last one will obviously disable USB access it may be the only way to confirm a kernel
# panic due to ConfigFS USB gadget setup or similar (likely conflict with Android container init?)
dinitctl -o disable usb-internet
dinitctl -o disable usb-tethering
```


## Power button
Another sign to see if the device is booted is to just press the power button once briefly, this as
per default configuration should reboot the device immediately if it didn't fail in early dinit
services or similar and has `elogind` running.


## Assign IP address to USB interface
Without a DHCP daemon like https://gitlab.com/postmarketOS/unudhcpd running or perhaps malfunction
in target device kernel USB gadget drivers you can manually assign the IPs on the host side for
example assuming end of `dmesg` shows the new USB network interface as `enp47s0f3u4u1u3`:
```sh
nic="enp47s0f3u4u1u3"
sudo sh -c 'ip link set dev $nic up && ip address add 10.15.19.100/24 dev $nic && ip route add 10.15.19.82 dev $nic'
ping -c 1 10.15.19.82
ssh hybris@10.15.19.82
```


## Internet access over USB
With USB network and SSH access established run [`./tethering.sh`](tethering.sh) in the repo clone
root directory **and read its output** for further steps.


## Check service statuses
```sh
doas dinitctl list

# only pending/failed services (+ toplevel boot one)
doas dinitctl list | grep -v '^\[{+'
```


## Getting Android container to boot
It should already be enabled by default unless disabled manually:
```
# lxc-ls -fF 'NAME,STATE'
NAME    STATE
android RUNNING
```
If it's not `dinitctl list` may give a clue as to what's going wrong (likely either `android-mounts`
or `lxc-android` fails to start), consult their respective logs under `/var/log/` (enabling log
storage on-disk as needed without USB access)

Android `/init` itself will log to `dmesg`, `logcat` could be interesting too when the container is
still running.

See also `lxc-checkconfig` to ensure you're running the expected kernel config and that your changes
are valid.

To start the container boot process manually you may `dinitctl start lxc-android`

To see ratelimited logging from e.g. Android `/init` when container start fails add e.g.
`printk.devkmsg=on log_buf_len=4M` to kernel (`*boot.img`) cmdline.

Some Halium 10 ports may also need a patched `/usr/lib/droid-vendor-overlay/bin/vndservicemanager`
from https://github.com/droidian-devices/adaptation-droidian-starqlte/blob/droidian/usr/lib/droid-vendor-overlay/bin/vndservicemanager
if it's crashing.

Restarting the entire container while running is also possible if needed via
`dinitctl restart --force lxc-android`. Do note that this may turn your display backlight entirely
off and you'll have to manually e.g. `echo 255 > /sys/class/leds/lcd-backlight/brightness` afterward
unless you create a [`android-hwcomposer-backlight` service](overlays/volla-vidofnir/etc/dinit.d/android-hwcomposer-backlight)


## View logs
```sh
doas tail -f /var/log/messages
ls -l /var/log/
doas dmesg -w
doas android_logcat
```
Do note that there's `tmpfs` (2% size is ~74 MiB with 4GB RAM device) mounted on `/var/log` by default
mostly due to spammy downstream kernels which would eat all disk space eventually even while idle and
may also "run out of space" in-memory pretty quickly depending on the kernel source spam debug levels.


## Internet via WLAN
Once the container is stable and WLAN works as seen in `rfkill list`, `nmcmli d` and `ip a` you may
`doas dinitctl disable usb-internet` (assuming enabled `usbnet` overlay on top of rootfs) to avoid
breaking internet upon rebooting by trying to use host internet over USB

To get it working one may need e.g. a [`/usr/libexec/enable-mtk-connectivity`](overlays/volla-vidofnir/usr/libexec/enable-mtk-connectivity)
specified to be ran from [`/etc/rc.local`](overlays/volla-vidofnir/etc/rc.local), otherwise try
something similar to:
```sh
# MediaTek
if [ -c /dev/wmtWifi ]; then
	sleep 3
	echo 1 > /dev/wmtWifi
fi

# WLAN on older QCOM devices
[ -e /dev/wcnss_wlan ] && echo 1 > /dev/wcnss_wlan
[ -e /sys/module/wlan/parameters/fwpath ] && echo sta > /sys/module/wlan/parameters/fwpath

[ -e /sys/kernel/boot_wlan/boot_wlan ] && echo 1 > /sys/kernel/boot_wlan/boot_wlan
[ -e /dev/wlan ] && echo ON > /dev/wlan

# QCOM cellular data
[ -e /dev/ipa ] && echo 1 > /dev/ipa
```


## Testing the GPU
Once `lxc-android` service is running well `test_egl_configs` should start returning interesting
results. For some devices at this point you may already get a graphical session up but if not try
`test_hwcomposer` (as root) but it may not work. Remember to first `dinitctl stop greetd` if it's
not yet disabled.

While likely irrelevant `export HYBRIS_LD_DEBUG=1` could help dig up not found libraries (which we
hide by default) most of which are non-fatal in practice as these are printed even on at least some
fully working devices; once located under `/android` define define space separated `HYBRIS_LD_LIBRARY_PATH`
env var with directory paths containing the supposedly missing library `.so` to see if this helps.

Also try `export LD_PRELOAD=libtls-padding.so` (Halium 10 specifically known possibly affected)

You may also just try running a full Wayland compositor as documented in e.g. [Launching Wayfire](README.md#wayfire-wayland-compositor)
with the help of the env vars etc here via `conspy` if it didn't launch by default.

NOTE: Some Halium 10/11 ports may need `dinitctl restart android-hwcomposer` after running some
graphical client like `test_hwcomposer` or `wayfire`.

Some QCOM devices set display brightness to 0 with hwcomposer start, so if there's still nothing on display try e.g.
```sh
echo 255 > /sys/class/leds/lcd-backlight/brightness
```


## Test via software rendering
We load Android GPU libraries like `libGLESv2.so.2` and `libEGL.so.1` with an added `/usr/lib/hybris`
to the default musl `LD_LIBRARY_PATH` (in `/etc/ld-musl-aarch64.path`).

To use software rendering via e.g. Mesa LLVMpipe you can just set `LD_LIBRARY_PATH=/usr/lib` in
environment for it to load the libraries from the usual default location:
```sh
LD_LIBRARY_PATH=/usr/lib EGL_PLATFORM=wayland vblank_mode=0 es2gears_wayland
```


## Debug library loading problems
Set e.g. `HYBRIS_LD_DEBUG=1 LD_DEBUG=files` in env of the failing process.


## Debug program crashes
```sh
doas apk add lldb chimera-repo-{main,user}-dbg
doas apk add musl-dbg # ...
lldb -- crashing_executable
```


## Programs aborting with SIGBUS
Could be missing hooks for vendor drivers to function when handled via libhybris in other middleware
example with https://github.com/libhybris/libhybris/commit/3d04060 (`pthread_getname_np`)
- missing (https://pastebin.com/raw/yCcSuyJ5):
```
I: [pulseaudio] droid-util.c: Droid hw module 14.2.97
I: [pulseaudio] droid-util.c: Loaded hw module audio.primary (generic)
Failed to handle SIGBUS.
Aborted
```
- working (https://pastebin.com/raw/E82r0hQV):
```
I: [pulseaudio] droid-util.c: Droid hw module 14.2.97
I: [pulseaudio] droid-util.c: Loaded hw module audio.primary (generic)
library "android.hardware.bluetooth.audio@2.0.so" not found
"/android/vendor/lib/soundfx/libqcomvisualizer.so" is 32-bit instead of 64-bit
"/android/vendor/lib/libqtigef.so" is 32-bit instead of 64-bit
```


## Disabling Android services
Simply create an empty file overlaying the original in Android `/system` or `/vendor` partition, for
example to prevent camera related binaries from starting:
```sh
doas mkdir -p /usr/lib/droid-{system,vendor}-overlay/etc/init
doas touch /usr/lib/droid-system-overlay/etc/init/camera_service.rc
doas touch /usr/lib/droid-vendor-overlay/etc/init/camerahalserver.rc
doas reboot
```


## Binder debugging
`/dev/binderfs/binder_logs/` on newer devices may also contain some insights.
```sh
# apk info -L libgbinder-progs
binder-list
```


## See also
- https://github.com/droidian/porting-guide/blob/master/debugging-tips.md
