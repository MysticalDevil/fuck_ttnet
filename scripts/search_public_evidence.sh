#!/usr/bin/env sh

# Search public GitHub code for TTNet/TNC traffic-control evidence.
#
# The searches are read-only and are meant to be pasted into investigation
# notes. They do not prove TikTok's server-side rule-selection condition.

set -eu

if ! command -v gh >/dev/null 2>&1; then
  echo "search: GitHub CLI 'gh' is required" >&2
  exit 1
fi

SEARCH_FAILED=0

run_search() {
  label="$1"
  query="$2"
  tmp_output="$(mktemp "${TMPDIR:-/tmp}/fuck_ttnet_gh_search.XXXXXX")"

  echo
  echo "== $label =="
  echo "query: $query"
  if ! gh search code "$query" --limit "${GH_SEARCH_LIMIT:-20}" > "$tmp_output" 2>&1; then
    SEARCH_FAILED=1
  fi
  awk 'length($0) > 220 { print substr($0, 1, 217) "..."; next } { print }' "$tmp_output"
  rm -f "$tmp_output"
}

run_search "exact observed rule id in public TikTok decompilations" \
  "3011076 repo:cxxsheng/TiktokSource"
run_search "exact observed rule id in public TikTok APK mirrors" \
  "3011076 user:EduardoC3677"
run_search "TTNet traffic-control exception" \
  "ERR_TTNET_TRAFFIC_CONTROL_DROP"
run_search "TTNet dispatch action schema" \
  "ttnet_dispatch_actions repo:cxxsheng/TiktokSource"
run_search "TTNet drop-code parser" \
  "drop_code repo:cxxsheng/TiktokSource"
run_search "public URL dispatcher drop check" \
  "mActionRuleIdList mDispatchedURL repo:cxxsheng/TiktokSource"

if [ "$SEARCH_FAILED" -ne 0 ]; then
  echo
  echo "search: one or more GitHub searches failed" >&2
  exit 1
fi
