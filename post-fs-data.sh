#!/system/bin/sh

MODDIR="${0%/*}"
export MODDIR

# shellcheck source=/dev/null
. "$MODDIR/common/ttnet_patch.sh"

wait_for_tiktok_data
patch_tiktok_ttnet
