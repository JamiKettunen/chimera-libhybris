# mkrootfs.sh config for Volla Phone X23 (volla-vidofnir)
# v5.10 kernel source: https://gitlab.com/ubports/porting/reference-device-ports/halium12/volla-x23/kernel-volla-mt6789
OVERLAYS+=(
	halium-12 # VNDK 31/32 adaptations
	mtk-extras # MediaTek SoC
	volla-vidofnir # Volla Phone X23
)
