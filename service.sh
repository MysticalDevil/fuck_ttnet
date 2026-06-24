#!/system/bin/sh

MODDIR="${0%/*}"
export MODDIR

# shellcheck source=/dev/null
. "$MODDIR/common/ttnet_patch.sh"

(
  wait_for_tiktok_data
  log_msg "service started"

  while true; do
    patch_tiktok_ttnet
    sleep "${FUCK_TTNET_INTERVAL:-20}"
  done
) &
