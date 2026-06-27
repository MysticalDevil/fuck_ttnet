#!/system/bin/sh

MODDIR="${0%/*}"
export MODDIR
LOCK_DIR="$MODDIR/service.lock"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  old_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null)"
  if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
    exit 0
  fi
  rm -f "$LOCK_DIR/pid" 2>/dev/null
  rmdir "$LOCK_DIR" 2>/dev/null || exit 0
  mkdir "$LOCK_DIR" 2>/dev/null || exit 0
fi

run_service() {
  trap 'rm -f "$LOCK_DIR/pid" 2>/dev/null; rmdir "$LOCK_DIR" 2>/dev/null' EXIT HUP INT TERM
  LOG_FILE="${LOG_FILE:-$MODDIR/fuck_ttnet.log}"
  now="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
  [ -n "$now" ] || now="unknown-time"
  echo "[$now] service started in passive mode; use WebUI for diagnosis and repair" >> "$LOG_FILE"
}

run_service &
echo "$!" > "$LOCK_DIR/pid"
