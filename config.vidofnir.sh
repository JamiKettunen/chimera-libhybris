# mkrootfs.sh config for Volla Phone X23 (volla-vidofnir)
OVERLAYS+=(
	halium-12 # VNDK 31/32 adaptations
	mtk-extras # MediaTek SoC
	volla-vidofnir # Volla Phone X23
)
