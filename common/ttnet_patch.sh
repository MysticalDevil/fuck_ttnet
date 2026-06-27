#!/system/bin/sh

PKG="${PKG:-com.zhiliaoapp.musically}"
APP_DIR="${APP_DIR:-/data/data/$PKG}"
FILES_DIR="${FILES_DIR:-$APP_DIR/files}"
SERVER_JSON="${SERVER_JSON:-$FILES_DIR/server.json}"
TT_NET_CONFIG="${TT_NET_CONFIG:-$FILES_DIR/tt_net_config.config}"
LOG_FILE="${LOG_FILE:-$MODDIR/fuck_ttnet.log}"
REMOVE_GLOBAL_DROP_AWK="${REMOVE_GLOBAL_DROP_AWK:-$MODDIR/common/remove_global_drop.awk}"

log_msg() {
  now="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
  [ -n "$now" ] || now="unknown-time"
  echo "[$now] $*" >> "$LOG_FILE"
}

trim_log() {
  [ -f "$LOG_FILE" ] || return 0
  size="$(wc -c < "$LOG_FILE" 2>/dev/null)"
  [ -n "$size" ] || return 0
  [ "$size" -le 65536 ] && return 0
  tail -c 32768 "$LOG_FILE" > "$LOG_FILE.tmp" 2>/dev/null && mv "$LOG_FILE.tmp" "$LOG_FILE"
}

wait_for_tiktok_data() {
  i=0
  while [ "$i" -lt 120 ]; do
    [ -d "$FILES_DIR" ] && return 0
    i=$((i + 1))
    sleep 2
  done

  log_msg "TikTok data dir not found: $FILES_DIR"
  return 1
}

owner_group_for_app() {
  # Android toybox stat formats vary across versions; numeric ls is more stable here.
  # shellcheck disable=SC2012
  ls -ldn "$FILES_DIR" 2>/dev/null | awk '{print $3 ":" $4}'
}

restore_app_file_attrs() {
  file="$1"
  owner_group="$(owner_group_for_app)"

  if [ -n "$owner_group" ]; then
    chown "$owner_group" "$file" 2>/dev/null || log_msg "chown failed for $file"
  fi

  chmod 600 "$file" 2>/dev/null || log_msg "chmod failed for $file"
  restorecon "$file" >/dev/null 2>&1 || true
}

backup_once() {
  file="$1"
  backup="$file.fuck_ttnet.bak"

  [ -f "$file" ] || return 0
  [ -f "$backup" ] && return 0

  cp "$file" "$backup" 2>/dev/null && log_msg "backup created: $backup"
  restore_app_file_attrs "$backup"
}

replace_if_changed() {
  source="$1"
  target="$2"
  tmp="$target.fuck_ttnet.tmp.$$"

  [ -s "$source" ] || return 1

  if cmp -s "$source" "$target" 2>/dev/null; then
    rm -f "$source" "$tmp" 2>/dev/null
    return 1
  fi

  backup_once "$target"
  cp "$source" "$tmp" 2>/dev/null || {
    log_msg "failed to stage replacement for $target"
    rm -f "$source" "$tmp" 2>/dev/null
    return 1
  }

  mv "$tmp" "$target" 2>/dev/null || {
    log_msg "failed to replace $target"
    rm -f "$source" "$tmp" 2>/dev/null
    return 1
  }

  rm -f "$source" 2>/dev/null
  restore_app_file_attrs "$target"
  return 0
}

patch_server_json() {
  [ -f "$SERVER_JSON" ] || return 0
  grep -q '3011076' "$SERVER_JSON" 2>/dev/null || return 0
  [ -f "$REMOVE_GLOBAL_DROP_AWK" ] || {
    log_msg "missing patch script: $REMOVE_GLOBAL_DROP_AWK"
    return 1
  }

  out="$SERVER_JSON.fuck_ttnet.out.$$"

  awk -f "$REMOVE_GLOBAL_DROP_AWK" "$SERVER_JSON" > "$out" 2>> "$LOG_FILE" || {
    log_msg "awk patch failed for server.json"
    rm -f "$out" 2>/dev/null
    return 1
  }

  if replace_if_changed "$out" "$SERVER_JSON"; then
    log_msg "patched server.json: removed global drop rule 3011076"
    return 0
  fi

  return 0
}

patch_tt_net_config() {
  [ -f "$TT_NET_CONFIG" ] || return 0
  grep -q '3011076' "$TT_NET_CONFIG" 2>/dev/null || return 0

  out="$TT_NET_CONFIG.fuck_ttnet.out.$$"

  sed -e 's/3011076,//g' -e 's/,3011076//g' "$TT_NET_CONFIG" > "$out" 2>> "$LOG_FILE" || {
    log_msg "sed patch failed for tt_net_config.config"
    rm -f "$out" 2>/dev/null
    return 1
  }

  if replace_if_changed "$out" "$TT_NET_CONFIG"; then
    log_msg "patched tt_net_config.config: removed rule id 3011076"
    return 0
  fi

  return 0
}

patch_tiktok_ttnet() {
  trim_log

  [ -d "$FILES_DIR" ] || {
    log_msg "skip: files dir not found: $FILES_DIR"
    return 1
  }

  patch_server_json
  patch_tt_net_config
}
