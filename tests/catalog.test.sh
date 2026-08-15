#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
readonly ROOT
TEMP_ROOT="$(mktemp -d /tmp/plugin-control-catalog-test.XXXXXX)"
readonly TEMP_ROOT
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

normalize() {
  jq -c --arg channelName "Omarchy Plugins Marketplace" \
    --arg channelSource marketplace --argjson channelRank 30 \
    -f "$ROOT/lib/catalog.jq" "$1"
}

valid="$(normalize "$TEST_DIR/fixtures/catalog-valid.json")"
jq -e '.ok == true and (.records | length) == 2' <<<"$valid" >/dev/null
jq -e '.records[0].installable == true' <<<"$valid" >/dev/null
jq -e '.records[1].installable == false' <<<"$valid" >/dev/null
jq -e '.records[0].listingValidatedCommit != .records[0].upstreamObservedCommit' \
  <<<"$valid" >/dev/null
printf 'ok - marketplace-like catalog and browse-only rows\n'

jq '.plugins += [{"name":"missing id"},
  {"id":"bad/id","name":"bad","sourceType":"community"},
  {"id":"bad.url","name":"bad","sourceType":"community",
    "repo":"http://github.com/example/bad","repositoryLayout":"root-plugin",
    "manifestPath":"manifest.json","installAvailable":true}]' \
  "$TEST_DIR/fixtures/catalog-valid.json" >"$TEMP_ROOT/malformed-rows.json"
malformed="$(normalize "$TEMP_ROOT/malformed-rows.json")"
jq -e '(.records | length) == 2 and (.errors | length) == 3' \
  <<<"$malformed" >/dev/null
printf 'ok - missing fields invalid IDs and unsafe URLs are row errors\n'

printf '{"stateSchemaVersion":1,"plugins":"wrong"}\n' \
  >"$TEMP_ROOT/malformed-root.json"
normalize "$TEMP_ROOT/malformed-root.json" \
  | jq -e '.ok == false and (.records | length) == 0' >/dev/null
printf 'ok - malformed catalog root is rejected\n'

jq -n '{stateSchemaVersion:1,plugins:
  [range(0;5001)|{id:("x."+tostring),name:"x",sourceType:"community"}]}' \
  >"$TEMP_ROOT/oversized-count.json"
normalize "$TEMP_ROOT/oversized-count.json" \
  | jq -e '.ok == false and (.error | contains("too many"))' >/dev/null
printf 'ok - excessive record counts are rejected\n'

jq '.plugins[0].sourceType="builtin" | .plugins[0].builtIn=true' \
  "$TEST_DIR/fixtures/catalog-valid.json" >"$TEMP_ROOT/custom-builtin.json"
custom="$(jq -c --arg channelName Custom \
  --arg channelSource custom --argjson channelRank 10 \
  -f "$ROOT/lib/catalog.jq" "$TEMP_ROOT/custom-builtin.json")"
jq -e '.records[0].builtIn == false and .records[0].source == "custom"' \
  <<<"$custom" >/dev/null
printf 'ok - custom catalogs cannot impersonate native built-ins\n'

normalize_preview() {
  jq -c --arg channelName "Omarchy Plugins Marketplace" \
    --arg channelSource marketplace --argjson channelRank 30 \
    --arg previewBase "https://omarchyplugins.com/" \
    -f "$ROOT/lib/catalog.jq" "$1"
}

preview="$(normalize_preview "$TEST_DIR/fixtures/catalog-preview.json")"
jq -e '(.records | length) == 7 and (.errors | length) == 0' \
  <<<"$preview" >/dev/null
jq -e '.records[0].previewThumbnail
  == "https://omarchyplugins.com/assets/img/plugins/a-card.webp"' \
  <<<"$preview" >/dev/null
jq -e '.records[0].previewImage
  == "https://omarchyplugins.com/assets/img/plugins/a-detail.webp"' \
  <<<"$preview" >/dev/null
jq -e '.records[0].previewThumbnailWidth == 720
  and .records[0].previewThumbnailHeight == 405
  and .records[0].previewWidth == 1600
  and .records[0].previewHeight == 900' <<<"$preview" >/dev/null
jq -e '.records[0].stars == 13 and .records[0].license == "MIT"
  and .records[0].repositoryUpdatedAt == "2026-08-11T17:06:54Z"' \
  <<<"$preview" >/dev/null
printf 'ok - preview fields resolve against the channel website\n'

jq -e '[.records[1:6][] | .previewThumbnail] | all(. == "")' \
  <<<"$preview" >/dev/null
jq -e '[.records[1:6][] | .id] | length == 5' <<<"$preview" >/dev/null
printf 'ok - unsafe preview paths blank the picture without hiding the plugin\n'

jq -e '.records[6].previewThumbnail != ""
  and .records[6].previewThumbnailWidth == 0
  and .records[6].stars == 0' <<<"$preview" >/dev/null
printf 'ok - out of range preview numbers fall back to zero\n'

no_base="$(jq -c --arg channelName Custom --arg channelSource custom \
  --argjson channelRank 10 -f "$ROOT/lib/catalog.jq" \
  "$TEST_DIR/fixtures/catalog-preview.json")"
jq -e '[.records[] | .previewThumbnail] | all(. == "")' \
  <<<"$no_base" >/dev/null
printf 'ok - previews need a channel website to resolve\n'

export HOME="$TEMP_ROOT/home"
export XDG_CONFIG_HOME="$TEMP_ROOT/config"
export XDG_CACHE_HOME="$TEMP_ROOT/cache"
export XDG_STATE_HOME="$TEMP_ROOT/state"
export XDG_RUNTIME_DIR="$TEMP_ROOT/runtime"
source "$ROOT/bin/plugin-control"
init_paths

good_config="$(load_config "$ROOT")"
printf 'version: [\n' >"$CHANNEL_CONFIG"
fallback_config="$(load_config "$ROOT")"
jq -e --argjson expected "$good_config" '. == $expected' \
  <<<"$fallback_config" >/dev/null
jq -e '.error | length > 0' "$CONFIG_ERROR" >/dev/null
cp "$ROOT/config/channels.yaml" "$CHANNEL_CONFIG"
printf 'ok - malformed YAML preserves the last good configuration\n'

rm -f -- "$LAST_GOOD_CONFIG"
sed 's/^version: 2$/version: 1/' "$ROOT/config/channels.yaml" \
  >"$CHANNEL_CONFIG"
cp "$CHANNEL_CONFIG" "$TEMP_ROOT/legacy-config.yaml"
if load_config "$ROOT" >"$TEMP_ROOT/legacy-output.json"; then
  printf 'not ok - unsupported config fell back to defaults\n' >&2
  exit 1
fi
cmp "$CHANNEL_CONFIG" "$TEMP_ROOT/legacy-config.yaml"
legacy_status="$(config_status "$ROOT" || true)"
jq -e '.ok == false and .usingLastGood == false and .config == null
  and (.error | contains("unsupported"))' <<<"$legacy_status" >/dev/null
mkdir -p -- "$(dirname -- "$SNAPSHOT_STATE")"
jq -cn '{ok:true,snapshotId:"legacy",records:[],config:{version:1}}' \
  >"$SNAPSHOT_STATE"
if cached_command "$ROOT" >"$TEMP_ROOT/legacy-snapshot.json"; then
  printf 'not ok - cached command returned a legacy snapshot\n' >&2
  exit 1
fi
[[ ! -s $TEMP_ROOT/legacy-snapshot.json ]]
cp "$ROOT/config/channels.yaml" "$CHANNEL_CONFIG"
load_config "$ROOT" >/dev/null
printf 'ok - unsupported config and snapshot fail without replacement\n'

target="$CACHE_ROOT/atomic.json"
printf '{"value":1}\n' | atomic_write_stream "$target"
jq -e '.value == 1' "$target" >/dev/null
printf '{"value":2}\n' | atomic_write_stream "$target"
jq -e '.value == 2' "$target" >/dev/null
if find "$CACHE_ROOT" -name '.atomic.json.tmp.*' -print -quit | grep -q .; then
  printf 'not ok - atomic cache left a temporary file\n' >&2
  exit 1
fi
printf 'ok - atomic cache replacement\n'

channel='{"id":"marketplace","name":"Omarchy Plugins Marketplace",
  "type":"marketplace-catalog","enabled":true,
  "catalog_url":"https://omarchyplugins.com/catalog.json"}'
mkdir -p "$CHANNEL_CACHE"
printf '%s\n' "$valid" >"$CHANNEL_CACHE/marketplace.json"
before="$(sha256sum "$CHANNEL_CACHE/marketplace.json")"

download_catalog() {
  printf '{bad json' >"$2"
  : >"$3"
  printf '200\n'
}
if refresh_catalog_channel "$ROOT" "$channel"; then
  printf 'not ok - malformed replacement was accepted\n' >&2
  exit 1
fi
[[ $(sha256sum "$CHANNEL_CACHE/marketplace.json") == "$before" ]]
printf 'ok - malformed download preserves the last valid cache\n'

download_catalog() {
  : >"$2"
  : >"$3"
  printf '000\n'
}
if refresh_catalog_channel "$ROOT" "$channel"; then
  printf 'not ok - failed oversized-style download was accepted\n' >&2
  exit 1
fi
[[ $(sha256sum "$CHANNEL_CACHE/marketplace.json") == "$before" ]]
printf 'ok - failed or oversized downloads preserve cache\n'

download_catalog() {
  : >"$2"
  : >"$3"
  printf '304\n'
}
refresh_catalog_channel "$ROOT" "$channel"
[[ $(sha256sum "$CHANNEL_CACHE/marketplace.json") == "$before" ]]
printf 'ok - ETag unchanged response keeps cache\n'

download_catalog() {
  printf '{"stateSchemaVersion":1,"plugins":[]}\n' >"$2"
  : >"$3"
  printf '200\n'
}
refresh_catalog_channel "$ROOT" "$channel"
jq -e '.ok == true and (.records | length) == 0' \
  "$CHANNEL_CACHE/marketplace.json" >/dev/null
printf 'ok - valid empty catalog clears stale records\n'
