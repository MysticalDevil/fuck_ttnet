#!/usr/bin/env sh

set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fuck_ttnet_package.XXXXXX")"

output=""
tmp_output=""

cleanup() {
  rm -rf "$STAGING_DIR"
  # A failed zip used to leave $DIST_DIR/.<id>-<version>.zip.tmp behind.
  [ -n "$tmp_output" ] && rm -f "$tmp_output"
}
trap cleanup EXIT HUP INT TERM

for tool in install zip; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "package: $tool is required" >&2
    exit 1
  fi
done

# Fail before the (slow) WebUI build if a runtime file is not valid LF.
# CRLF ships a module that cannot parse on the device; see .gitattributes.
check_lf() {
  if LC_ALL=C grep -q "$(printf '\r')" "$1"; then
    echo "package: CRLF line ending in ${1#"$ROOT_DIR"/}" >&2
    echo "package: run 'git add --renormalize .' and re-checkout" >&2
    exit 1
  fi
}

for f in \
  module.prop \
  post-fs-data.sh \
  service.sh \
  common/ttnet_patch.sh \
  common/remove_global_drop.awk \
  common/count_global_drop.awk \
  scripts/status.sh \
  scripts/repair.sh
do
  if [ -f "$ROOT_DIR/$f" ]; then
    check_lf "$ROOT_DIR/$f"
  fi
done

# Strip a stray CR so a CRLF checkout cannot leak it into the zip name.
version="$(sed -n 's/^version=//p' "$ROOT_DIR/module.prop" | head -n 1 | tr -d '\r')"
version_code="$(sed -n 's/^versionCode=//p' "$ROOT_DIR/module.prop" | head -n 1 | tr -d '\r')"
module_id="$(sed -n 's/^id=//p' "$ROOT_DIR/module.prop" | head -n 1 | tr -d '\r')"

if [ -z "$module_id" ]; then
  echo "package: module id is missing in module.prop" >&2
  exit 1
fi

if [ -z "$version" ]; then
  echo "package: version is missing in module.prop" >&2
  exit 1
fi

case "$version_code" in
  ''|*[!0-9]*)
    echo "package: versionCode must be a positive integer, got '$version_code'" >&2
    exit 1
    ;;
esac

mkdir -p "$DIST_DIR"

if [ -f "$ROOT_DIR/package.json" ]; then
  if ! command -v pnpm >/dev/null 2>&1; then
    echo "package: pnpm is required to build the WebUI assets" >&2
    exit 1
  fi
  (
    cd "$ROOT_DIR"
    pnpm build
  )
elif [ -f "$ROOT_DIR/webroot/index.html" ]; then
  echo "package: package.json is missing but webroot/ exists; refusing to ship unverified WebUI assets" >&2
  exit 1
fi

install -m 0644 "$ROOT_DIR/module.prop" "$STAGING_DIR/module.prop"
install -m 0755 "$ROOT_DIR/post-fs-data.sh" "$STAGING_DIR/post-fs-data.sh"
install -m 0755 "$ROOT_DIR/service.sh" "$STAGING_DIR/service.sh"
install -m 0644 "$ROOT_DIR/README.md" "$STAGING_DIR/README.md"
install -m 0644 "$ROOT_DIR/README.zh-CN.md" "$STAGING_DIR/README.zh-CN.md"

mkdir -p "$STAGING_DIR/common"
install -m 0755 "$ROOT_DIR/common/ttnet_patch.sh" "$STAGING_DIR/common/ttnet_patch.sh"
install -m 0644 "$ROOT_DIR/common/remove_global_drop.awk" "$STAGING_DIR/common/remove_global_drop.awk"
install -m 0644 "$ROOT_DIR/common/count_global_drop.awk" "$STAGING_DIR/common/count_global_drop.awk"

if [ ! -f "$ROOT_DIR/webroot/index.html" ]; then
  echo "package: webroot/index.html is missing" >&2
  exit 1
fi

mkdir -p "$STAGING_DIR/webroot"
cp -R "$ROOT_DIR/webroot/." "$STAGING_DIR/webroot/"

mkdir -p "$STAGING_DIR/docs" "$STAGING_DIR/samples"
install -m 0644 "$ROOT_DIR/docs/investigation.md" "$STAGING_DIR/docs/investigation.md"
install -m 0644 "$ROOT_DIR/docs/no-network-cases.md" "$STAGING_DIR/docs/no-network-cases.md"
install -m 0644 "$ROOT_DIR/docs/no-network-cases.zh-CN.md" "$STAGING_DIR/docs/no-network-cases.zh-CN.md"
install -m 0644 "$ROOT_DIR/samples/3011076_drop_rule.json" "$STAGING_DIR/samples/3011076_drop_rule.json"
install -m 0644 "$ROOT_DIR/samples/observed_3011076_drop_rule.json" \
  "$STAGING_DIR/samples/observed_3011076_drop_rule.json"
install -m 0644 "$ROOT_DIR/samples/observed_err_cert_authority_invalid.log" \
  "$STAGING_DIR/samples/observed_err_cert_authority_invalid.log"

mkdir -p "$STAGING_DIR/scripts"
install -m 0755 "$ROOT_DIR/scripts/package.sh" "$STAGING_DIR/scripts/package.sh"
install -m 0755 "$ROOT_DIR/scripts/collect_device_evidence.sh" \
  "$STAGING_DIR/scripts/collect_device_evidence.sh"
install -m 0755 "$ROOT_DIR/scripts/diagnose_no_network.sh" \
  "$STAGING_DIR/scripts/diagnose_no_network.sh"
install -m 0755 "$ROOT_DIR/scripts/extract_ttnet_rule.py" \
  "$STAGING_DIR/scripts/extract_ttnet_rule.py"
install -m 0755 "$ROOT_DIR/scripts/repair.sh" "$STAGING_DIR/scripts/repair.sh"
install -m 0755 "$ROOT_DIR/scripts/probe_ttnet_smali.sh" "$STAGING_DIR/scripts/probe_ttnet_smali.sh"
install -m 0755 "$ROOT_DIR/scripts/search_public_evidence.sh" \
  "$STAGING_DIR/scripts/search_public_evidence.sh"
install -m 0755 "$ROOT_DIR/scripts/status.sh" "$STAGING_DIR/scripts/status.sh"
install -m 0755 "$ROOT_DIR/scripts/test_patch_patterns.sh" \
  "$STAGING_DIR/scripts/test_patch_patterns.sh"
install -m 0755 "$ROOT_DIR/scripts/ttnet_dispatch_model.py" "$STAGING_DIR/scripts/ttnet_dispatch_model.py"

output="$DIST_DIR/$module_id-$version-$version_code.zip"
tmp_output="$DIST_DIR/.$module_id-$version-$version_code.zip.tmp"

if [ -e "$output" ]; then
  echo "package: refusing to overwrite existing artifact $output" >&2
  exit 1
fi

rm -f "$tmp_output"
(
  cd "$STAGING_DIR"
  zip -qr "$tmp_output" \
    module.prop \
    post-fs-data.sh \
    service.sh \
    README.md \
    README.zh-CN.md \
    common \
    webroot \
    docs \
    samples \
    scripts
)

mv "$tmp_output" "$output"
echo "package: wrote $output"
