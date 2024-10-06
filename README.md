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

Currently known booting ports include:
- Halium 9 based [`Volla Phone`](config.yggdrasil.sh) with kernel v4.4 and MediaTek Helio P23 (MT6763) SoC
- Halium 12 based [`Volla Phone X23`](config.vidofnir.sh) with kernel v5.10 and MediaTek Helio G99 (MT6789) SoC
- Maybe even your device...?


## Host dependencies
- `git` for cloning this repo and cports for package building
  - https://github.com/chimera-linux/cports/blob/master/Usage.md#requirements also apply
    - an `apk add base-cbuild-host` away on chimera systems
- `bash` for [`mkrootfs.sh`](mkrootfs.sh)
- `sudo` (or `doas`) for running specific commands as `root`
- `wget` (or `fetch` / `curl`) for fetching base rootfs archive
- e.g. `qemu-aarch64-static` (or `qemu-aarch64`) for cross-architecture rootfs building
  - assuming binfmt configuration setup for qemu user as well


## Building some extra packages
Before generating a rootfs image we need to build some required packages. Assuming you're
cross-building on a foreign (non-Chimera Linux) x86_64 host:
```sh
# NOTE: adjust target Halium version as needed
halium_version=12

git clone https://github.com/JamiKettunen/cports -b hybris
cd cports
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
./cbuild prune-pkgs -a aarch64
cd -
```
At this point before creating new rootfs images you should always force pull latest changes locally
(or even afterward rebase the https://github.com/JamiKettunen/cports/tree/hybris clone on latest
upstream https://github.com/chimera-linux/cports/tree/master) and rebuild *all* packages after e.g.
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
If without `chimera-chroot`, `xchroot` or `arch-chroot` around already:
```sh
git clone https://github.com/chimera-linux/chimera-install-scripts
PATH=$PWD/chimera-install-scripts:$PATH
```
Cross-architecture builds assume a working binfmt setup for static qemu-user binary for e.g. aarch64.

Do note that performing package updates to `dinit-chimera` and `udev` WILL render the device
unbootable until hacks from [`mkrootfs.sh`](mkrootfs.sh) to e.g. `/usr/lib/dinit.d/early/scripts/root-remount.sh`
etc are reapplied manually before reboot!


### Configuration
Additional configuration is possible through device config files such as shown above,
`config.local.sh` which may contain some user specific for yourself applied to every device or
environment variables which are as follows (and *most* seen atop [`mkrootfs.sh`](mkrootfs.sh)):
- `ARCH`: target rootfs architecture; while configurable only `aarch64` really makes sense or has
  been tested so far. `armv7` will require a full from-source bootstrap since no binary packages are
  officially provided by Chimera Linux (currently) and `x86_64` Androids are *very* rare.
- `DATE`: https://repo.chimera-linux.org/live/ version to use for base rootfs tarballs
- `FLAVOR`: from above version URL subdir the `-FLAVOR` archive to use; `bootstrap` and `full` are
  the only sensible choices really
- `WORKDIR`: mountpoint of rootfs image file during the creation process
- `OUT_ROOTFS`: rootfs image file location, you may want to move it out of `/tmp`
  default as needed
- `SIZE`: `fallocate -l` size used to create the rootfs image file
- `APK_CACHE`: apk package cache dir on host to use when running `apk` operations inside chroot to
  speed up subsequent (re)builds; `apk-cache` (at chimera-libhybris clone toplevel) is default and
  when value empty/unset nothing is cached
- `CPORTS`: existing clone location of hybris cports; `cports` (at chimera-libhybris clone toplevel)
  and `~/cports` as available are automatically supported defaults
- `CPORTS_PACKAGES_DIR`: hybris cports local packages dir containing `user` etc; should always be
  `packages` (relative to cports clone toplevel) unless using `./cbuild --repository-path ...`
- `PASSWD`: password to set for non-root user, when set as empty value only login via SSH pubkey (or
  on-device autologin); defaults to `1234`
- `SUDO`: command prefix for elevating user privileges to root; `sudo` and `doas` as available are
  automatically supported defaults (and when value empty/unset)
- `FETCH`: command prefix for downloading files; `wget`, `fetch` and `curl -O` as available are
  automatically supported defaults
- `QEMU_USER_STATIC`: qemu-user static binary to use when creating a cross-architecture rootfs; e.g.
  `qemu-aarch64-static` and `qemu-aarch64` as available are automatically supported defaults
- `CHROOT_WRAPPER`: command prefix for running commands inside rootfs chroot; `chimera-chroot`,
  `xchroot` and `arch-chroot` as available are automatically supported defaults
- `OVERLAYS`: array of [`overlays`](overlays) to "dump" on top of the rootfs before non-root user creation which
  may contain `deploy.sh` files to execute inside chroot or `deploy-host.sh` files sourced in the
  context (variables et all) of `mkrootfs.sh`; defaults to `base usbnet host-ssh-pubkey` with device
  configs typically appending more onto it


#### Overlay specific configuration
While most configuration affects the whole `mkrootfs.sh` there's some which only affect a specific
enabled overlay's `deploy-host.sh` which can read variables defined via env/configuration:
- `SSH_PUBKEYS`: SSH public keys to copy for both the non-root and root users in created rootfs;
  defaults to `$HOME/.ssh/id_*.pub`


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


### Logging in (via USB)
As your SSH public key (`~/.ssh/id_*.pub` or configured `SSH_PUBKEYS` file) is copied onto the rootfs
by default you should be able to log in as both `hybris` (default password: `1234` or configured `PASSWD`)
and `root`.
```sh
ssh hybris@10.15.19.82
# or
ssh root@10.15.19.82
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


## Updating and installing (hybris) cports packages
```sh
# for a one time thing it may make sense to not keep apk artifacts on rootfs if they fit in memory
ssh root@10.15.19.82 mount tmpfs -t tmpfs /hybris-cports-packages

# sync everything generally
rsync -hvrPt packages/ root@10.15.19.82:/hybris-cports-packages
# if you have multiple halium-gsi-* built locally instead and just want to copy e.g. halium-gsi-12*
find packages/ -type f ! -name 'halium-gsi-*' -o -name 'halium-gsi-12*' | sed 's|packages/||' | \
  rsync -hvrPt --files-from=- packages/ root@10.15.19.82:/hybris-cports-packages

ssh root@10.15.19.82 apk upgrade -Ua
# the same also works for additional built cports packages, just instead e.g.
ssh root@10.15.19.82 apk add my-new-package@hybris-cports

# if tmpfs on /hybris-cports-packages was used sync new APKINDEX* in place afterward to keep e.g.
# "apk upgrade -a" happy
ssh root@10.15.19.82 umount /hybris-cports-packages
rsync -hvrPt --include='*/' --include='APKINDEX*' --exclude='*' packages/ root@10.15.19.82:/hybris-cports-packages
```


### Wayfire (Wayland compositor)
This is currently the only known working GPU rendering test you can do. Auto-login via `greetd` is
enabled by default which should bring it up on the display but you may also launch it via `conspy`
(tty1) as described below after `dinitctl stop greetd` for further debugging as needed:
```sh
doas dinitctl stop greetd
doas conspy 1
# login: hybris
HYBRIS_LD_DEBUG=1 wayfire &> /tmp/wayfire.log
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
images_url="https://sourceforge.net/projects/aleasto-lineageos/files/LineageOS%2020/waydroid_arm64"
doas mkdir -p /etc/waydroid-extra/images
doas wget "$images_url/system.img/download" -O /etc/waydroid-extra/images/system.img
doas wget "$images_url/vendor.img/download" -O /etc/waydroid-extra/images/vendor.img
doas waydroid init -f
```


### See also
- https://github.com/JamiKettunen/cports/tree/hybris (Chimera Linux integration packages)
- https://gitlab.com/hybrisos/hybrisaports (postmarketOS libhybris pkgs before dropped)
- https://github.com/AlpHybris/alphybrisaports (latest similar musl libc project)
- https://github.com/droidian
- https://t.me/halium
