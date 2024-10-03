# chimera-libhybris
Run [Chimera Linux](https://chimera-linux.org) bare-metal on Android devices with [Halium](https://halium.org)
and [libhybris](https://github.com/libhybris/libhybris).

This doc assumes you already have a general knowledge in how porting a Linux distro with downstream
kernel works (and ideally have an Ubuntu Touch port for example ready to use kernel artifacts from)

<img src="https://i.imgur.com/wjT2LiS.jpeg" height="360" />


## Porting
Since I don't yet have proper kernel/base package cports integration done for anything there's some
*very rough* notes in [`PORTING.md`](PORTING.md) which boil down to having a bootloader unlocked
treble Android 9–13 device and existing Halium adapted kernel artifacts (`*boot.img` and modules as
needed) ready to deploy.


## Building some extra packages
Before generating a rootfs image we need to build some required packages. Assuming you're
cross-building on a foreign (non-Chimera Linux) x86_64 host:
```sh
# NOTE: adjust target Halium version as needed
halium_version=12

git clone https://github.com/JamiKettunen/cports -b hybris ~/cports
pushd ~/cports
wget https://repo.chimera-linux.org/apk/apk-x86_64-3.0.0_pre6-r0.static -O apk
chmod +x apk
PATH=$PWD:$PATH
./cbuild keygen
./cbuild binary-bootstrap
pkgs="
user/wayfire-droidian
user/halium-gsi-$halium_version.0
user/libgbinder
main/dinit
"
for p in $pkgs; do ./cbuild pkg -a aarch64 ${p}; done
popd

rm -rf overlays/{base,halium-$halium_version}/pkgs
mkdir overlays/{base,halium-$halium_version}/pkgs
mv ~/cports/packages/user/aarch64/halium-gsi-$halium_version*.apk overlays/halium-$halium_version/pkgs/
cp ~/cports/packages/main/aarch64/dinit-*.apk overlays/base/pkgs/
cp ~/cports/packages/user/aarch64/*.apk overlays/base/pkgs/
rm overlays/base/pkgs/*-{headers,devel,doc}-*.apk
```
At this point before creating new rootfs images you should always force pull latest changes locally
(or even rebase the https://github.com/JamiKettunen/cports/tree/hybris clone on latest upstream
https://github.com/chimera-linux/cports/tree/master) and rebuild *all* packages after e.g.
`rm -r packages/{main,user}/aarch64`; you may want to enable ccache in `etc/config.ini` as follows:
```ini
[build]
ccache = yes
```


## Generating /tmp/chimera-rootfs.img
Using [`config.vidofnir.sh`](config.vidofnir.sh) as an example:
```sh
./mkrootfs.sh config.vidofnir.sh
```
NOTE: By default assumes:
1. `chimera-chroot` from https://github.com/chimera-linux/chimera-install-scripts to be available via e.g.
```sh
git clone https://github.com/chimera-linux/chimera-install-scripts
PATH=$PWD/chimera-install-scripts:$PATH
```
2. e.g. `qemu-aarch64-static` is installed and its binfmt setup already done
3. `sudo` is used, otherwise e.g. `echo 'SUDO=doas' > config.local.sh`

Do note that performing package updates to `dinit-chimera` and `udev` WILL render the device
unbootable until hacks from [`mkrootfs.sh`](mkrootfs.sh) to e.g. `/usr/lib/dinit.d/early/scripts/root-remount.sh`
etc are reapplied manually before reboot!


## Deploying and booting
NOTE: We call the `rootfs.img` instead as `ubuntu.img` when using Halium initrd to make the cleanest
possible mount hierarchy configuration on final rootfs without polluting it with double-mounts under
`/android` etc.
- place generated rootfs image as `ubuntu.img` on `userdata` root (unencrypted, ext4!)
  - with device in e.g. UBports recovery (TWRP should work too minus `simg` steps), run on host:
```sh
adb shell 'mountpoint -q /data || mount /data'

# NOTE: you may optionally use compression via e.g.
mv /tmp/chimera-rootfs.img /tmp/ubuntu.img && xz /tmp/ubuntu.img && \
  adb push /tmp/ubuntu.img.xz /data && adb shell unxz /data/ubuntu.img.xz
# or just wait out the transfer over USB
adb push /tmp/chimera-rootfs.img /data/ubuntu.img

adb shell 'chmod 644 /data/ubuntu.img && sync && reboot'
```


## Growing existing rootfs image size
You may resize this file at will with the following if the preconfigured `SIZE` from [`mkrootfs.sh`](mkrootfs.sh)
(or the loaded configurations files) isn't enough and your recovery environment has `resize2fs`:
```sh
adb shell 'e2fsck -fy /data/ubuntu.img && resize2fs -f /data/ubuntu.img 8G'
```
Otherwise you can resize it online (with chimera booted) but **DO NOT** run `e2fsck` outside recovery
with rootfs unmounted to avoid corrupting the filesystem!
```sh
doas resize2fs /userdata/ubuntu.img 8G
doas reboot
doas resize2fs /userdata/ubuntu.img
```


### Logging in (via USB)
As your SSH public key (`~/.ssh/id_rsa.pub`) is copied onto the rootfs by default you should be able
to log in as both `hybris` (default password: `1234`) and `root`.
```sh
ssh hybris@10.15.19.82
# or
ssh root@10.15.19.82
```


### Wayfire (Wayland compositor)
This is currently the only known working GPU rendering test you can do. Auto-login via `greetd` is
enabled by default which should bring it up on the display but you may also launch it via `conspy`
(tty1) as described below after `dinitctl stop greetd` for further debugging as needed:
```sh
doas dinitctl stop greetd
doas conspy 1
# login: hybris
wayfire &> /tmp/wayfire.log
```
Then you're free to run graphical clients via e.g. `WAYLAND_DISPLAY=wayland-0 kgx` as `hybris` user.
To stop Wayfire you have to `pkill wayfire` as `^C` in the tty1 doesn't work


## Waydroid
Running Android (LineageOS) container on top of this all is also possible with a Wayland compositor up:
```sh
doas apk add waydroid
doas waydroid init -s GAPPS
waydroid show-full-ui
```
Do note that on Halium 12+ ports no official image vendor channels are available due to Waydroid
images past Android 11 having issues that need to be ironed out. You can setup some older images
built from `lineage-20` (Android 13) trees regardless if you wish but they require running
`waydroid show-full-ui` **twice**.
```sh
sudo mkdir -p /etc/waydroid-extra/images
images_url=https://sourceforge.net/projects/aleasto-lineageos/files/LineageOS%2020/waydroid_arm64
doas wget $images_url/system.img/download -O /etc/waydroid-extra/images/system.img
doas wget $images_url/vendor.img/download -O /etc/waydroid-extra/images/vendor.img
doas waydroid init -f
```


### See also
- https://github.com/JamiKettunen/cports/tree/hybris (Chimera Linux integration packages)
- https://gitlab.com/hybrisos/hybrisaports (postmarketOS libhybris pkgs before dropped)
- https://github.com/AlpHybris/alphybrisaports (latest similar musl libc project)
- https://github.com/droidian
- https://t.me/halium
