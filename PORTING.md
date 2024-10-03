# Porting

## Overview
Here's some rough high level requirements and notes about the process:
1. Have an Android 9+ stock (or otherwise treble/GSI compatible) device flashed with the target
   firmware ready to go and bootloader unlocked
   - you must have a VNDK of 33 (Android 13) or below, use treble checker app or
     `adb shell getprop ro.vndk.version`
2. compiled downstream kernel source with "the usual" Halium patches/defconfig tweaks (see Droidian,
   Ubuntu Touch and Sailfish OS ports)
   - kernel modules also deployed in `/usr/lib/modules` as needed
3. for GKI 1.0/2.0 devices (bootimg header v3/4 + kernel v5.4+) made a `/etc/modules-load.d/*.conf`
   based on `/vendor/lib/modules/modules.load`
   - for MediaTek SoC devices additional connectivity modules for WLAN etc from vendor initrc files
     need to be digged up (insmod) so they can be loaded later when android container is running
     - see `rg /vendor/etc/init -e insmod`
4. if desired create executable `/etc/rc.local` with some device-specifics e.g.
   `echo 255 > /sys/class/leds/green/brightness || :` to determine finished boot status etc
   - see [`DEBUGGING.md`](DEBUGGING.md) for how to enable dinit logs among other very useful tips
5. once booted generate udev rules (important for UI etc)
   - see [Generate udev rules](PORTING.md#generate-udev-rules)

For more details about e.g. modifying a pre-existing Ubuntu Touch `boot.img` to be compatible see
[`PORTING.md`](PORTING.md).

Otherwise copy e.g. [`config.vidofnir.sh`](config.vidofnir.sh) and modify it adding overlays etc you
want for your own device after creating them under [`overlays/`](overlays/)


## Re-using boot.img from Ubuntu Touch
As an example for Volla Phone X23 download from https://system-image.ubports.com/devel/arm64/android9plus/daily/vidofnir_esim/index.json
last entry the boot tarball (containing `*boot.img` + potentially interesting device-specific hacks
for later). For older (but still treble-compatible devices) with full systemimage builds this would
instead be inside device tarball with the hacks in `android-rootfs.img/system/halium`.

Make sure to remove `systempart=...` from kernel cmdline unless you don't mind having the rootfs in
the historically tiny/otherwise space constrained `system` partition (which also happens to be more
difficult to mount/debug on modern devices with `super` partition):
```sh
unpack_bootimg --boot_img vendor_boot.img --format=mkbootimg > mkbootimg_args
sed "s/systempart=[^ ']*//" mkbootimg_args > mkbootimg_args_chimera
sh -c "mkbootimg $(cat mkbootimg_args_chimera) --vendor_boot chimera-vendor_boot.img" && rm -r out mkbootimg_args*
fastboot \
  flash boot boot.img \
  flash vendor_boot chimera-vendor_boot.img \
  reboot recovery
```
For older non-GKI devices without `vendor_boot` or `super` partitions instead use:
```sh
unpack_bootimg --boot_img boot.img --format=mkbootimg > mkbootimg_args
sed "s/systempart=[^ ']*//" mkbootimg_args > mkbootimg_args_chimera
sh -c "mkbootimg $(cat mkbootimg_args_chimera) --out chimera-boot.img" && rm -r out mkbootimg_args*
fastboot \
  flash boot chimera-boot.img \
  reboot recovery
```
These assume you have `unpack_bootimg` etc from https://github.com/LineageOS/android_system_tools_mkbootimg
installed via `android-tools` (https://github.com/nmeum/android-tools) or similar. For some devices
`fastboot reboot recovery` may also be non-functional and you'll have to do the usual device-specific
button combo to enter it or *also* flash `recovery` partition with the `boot.img`.

Once booted to the UBports recovery successfully you may verify `systempart=` is gone from
`/proc/cmdline` as well.


## Generate udev rules
This may be needed for graphical programs (including full desktop environments) to run for example:
```sh
wc -l $(find /system/ -name 'ueventd*.rc') $(find /vendor/ -name 'ueventd*.rc')
cat $(find /system/ -name 'ueventd*.rc') $(find /vendor/ -name 'ueventd*.rc') | grep '^/dev' | sed 's:^/dev/::' \
| awk '{printf "ACTION==\"add\", KERNEL==\"%s\", OWNER=\"android_%s\", GROUP=\"android_%s\", MODE=\"%s\"\n",$1,$3,$4,$2}' \
| sed 's/android_root/root/g; s/\r//' > /etc/udev/rules.d/70-$(getprop ro.product.vendor.device).rules
```
