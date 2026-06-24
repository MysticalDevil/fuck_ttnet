#!/system/bin/sh

MODDIR="${0%/*}"
export MODDIR

# shellcheck source=/dev/null
. "$MODDIR/common/ttnet_patch.sh"

patch_tiktok_ttnet
