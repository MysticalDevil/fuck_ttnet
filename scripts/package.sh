#!/usr/bin/env sh

set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fuck_ttnet_package.XXXXXX")"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT HUP INT TERM

version="$(sed -n 's/^version=//p' "$ROOT_DIR/module.prop" | head -n 1)"
module_id="$(sed -n 's/^id=//p' "$ROOT_DIR/module.prop" | head -n 1)"

if [ -z "$module_id" ]; then
  echo "package: module id is missing in module.prop" >&2
  exit 1
fi

if [ -z "$version" ]; then
  echo "package: version is missing in module.prop" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"

install -m 0644 "$ROOT_DIR/module.prop" "$STAGING_DIR/module.prop"
install -m 0755 "$ROOT_DIR/action.sh" "$STAGING_DIR/action.sh"
install -m 0755 "$ROOT_DIR/post-fs-data.sh" "$STAGING_DIR/post-fs-data.sh"
install -m 0755 "$ROOT_DIR/service.sh" "$STAGING_DIR/service.sh"
install -m 0644 "$ROOT_DIR/README.md" "$STAGING_DIR/README.md"
install -m 0644 "$ROOT_DIR/README.zh-CN.md" "$STAGING_DIR/README.zh-CN.md"

mkdir -p "$STAGING_DIR/common"
install -m 0755 "$ROOT_DIR/common/ttnet_patch.sh" "$STAGING_DIR/common/ttnet_patch.sh"

mkdir -p "$STAGING_DIR/docs" "$STAGING_DIR/samples"
install -m 0644 "$ROOT_DIR/docs/investigation.md" "$STAGING_DIR/docs/investigation.md"
install -m 0644 "$ROOT_DIR/samples/3011076_drop_rule.json" "$STAGING_DIR/samples/3011076_drop_rule.json"
install -m 0644 "$ROOT_DIR/samples/observed_3011076_drop_rule.json" \
  "$STAGING_DIR/samples/observed_3011076_drop_rule.json"

mkdir -p "$STAGING_DIR/scripts"
install -m 0755 "$ROOT_DIR/scripts/package.sh" "$STAGING_DIR/scripts/package.sh"
install -m 0755 "$ROOT_DIR/scripts/collect_device_evidence.sh" \
  "$STAGING_DIR/scripts/collect_device_evidence.sh"
install -m 0755 "$ROOT_DIR/scripts/extract_ttnet_rule.py" \
  "$STAGING_DIR/scripts/extract_ttnet_rule.py"
install -m 0755 "$ROOT_DIR/scripts/probe_ttnet_smali.sh" "$STAGING_DIR/scripts/probe_ttnet_smali.sh"
install -m 0755 "$ROOT_DIR/scripts/search_public_evidence.sh" \
  "$STAGING_DIR/scripts/search_public_evidence.sh"
install -m 0755 "$ROOT_DIR/scripts/test_patch_patterns.sh" \
  "$STAGING_DIR/scripts/test_patch_patterns.sh"
install -m 0755 "$ROOT_DIR/scripts/ttnet_dispatch_model.py" "$STAGING_DIR/scripts/ttnet_dispatch_model.py"

output="$DIST_DIR/$module_id-$version.zip"
tmp_output="$DIST_DIR/.$module_id-$version.zip.tmp"

rm -f "$tmp_output"
(
  cd "$STAGING_DIR"
  zip -qr "$tmp_output" \
    module.prop \
    action.sh \
    post-fs-data.sh \
    service.sh \
    README.md \
    README.zh-CN.md \
    common \
    docs \
    samples \
    scripts
)

mv "$tmp_output" "$output"
echo "package: wrote $output"
