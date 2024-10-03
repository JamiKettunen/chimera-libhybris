# mkrootfs.sh config for Volla Phone (volla-yggdrasil)
# v4.4 kernel source: https://gitlab.com/ubports/porting/reference-device-ports/android9/volla-phone/android_kernel_volla_mt6763
OVERLAYS+=(
	halium-9 # VNDK 28 adaptations
	mtk-extras # MediaTek SoC
	volla-yggdrasil # Volla Phone
)
