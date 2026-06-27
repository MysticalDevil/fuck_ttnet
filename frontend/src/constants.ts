const MODULE_DIR = "/data/adb/modules/fuck_ttnet";

export const STATUS_CMD = `MODDIR=${MODULE_DIR} sh ${MODULE_DIR}/scripts/status.sh`;
export const REPAIR_CMD = `MODDIR=${MODULE_DIR} sh ${MODULE_DIR}/scripts/repair.sh`;
export const FORCE_STOP_CMD = "am force-stop com.zhiliaoapp.musically";
export const AUTO_REFRESH_MS = 15000;
export const MIN_REFRESH_FEEDBACK_MS = 900;
