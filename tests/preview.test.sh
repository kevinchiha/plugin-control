#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
readonly ROOT
TEMP_ROOT="$(mktemp -d /tmp/plugin-control-preview-test.XXXXXX)"
readonly TEMP_ROOT
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

export HOME="$TEMP_ROOT/home"
export XDG_CONFIG_HOME="$TEMP_ROOT/config"
export XDG_CACHE_HOME="$TEMP_ROOT/cache"
export XDG_STATE_HOME="$TEMP_ROOT/state"
export XDG_RUNTIME_DIR="$TEMP_ROOT/runtime"
export MOCK_BIN="$TEMP_ROOT/bin"
export MOCK_CURL_LOG="$TEMP_ROOT/curl.log"
export PATH="$MOCK_BIN:/usr/bin:/bin"
mkdir -p "$MOCK_BIN" "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" \
  "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR"
: >"$MOCK_CURL_LOG"

cat >"$MOCK_BIN/curl" <<'MOCK'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >>"$MOCK_CURL_LOG"
output=""
previous=""
for argument in "$@"; do
  [[ $previous == --output ]] && output="$argument"
  previous="$argument"
done
[[ -n $output ]] || exit 1
case "${MOCK_CURL_BODY:-png}" in
  png) printf '\x89PNG\r\n\x1a\n' >"$output" ;;
  webp) printf 'RIFF\x10\x00\x00\x00WEBPVP8 ' >"$output" ;;
  html) printf '<!doctype html>\n' >"$output" ;;
  empty) : >"$output" ;;
  fail) exit 22 ;;
esac
exit 0
MOCK
chmod 0755 "$MOCK_BIN/curl"

source "$ROOT/bin/plugin-control"
init_paths
ensure_config "$ROOT"
load_config "$ROOT" >/dev/null

card="https://omarchyplugins.com/assets/img/plugins/a-card.webp"

preview_command "$ROOT" "http://omarchyplugins.com/a.png" \
  | jq -e '.ok == false' >/dev/null
preview_command "$ROOT" "https://omarchyplugins.com/a.svg" \
  | jq -e '.ok == false' >/dev/null
preview_command "$ROOT" "https://omarchyplugins.com/a.png?x=1" \
  | jq -e '.ok == false' >/dev/null
printf 'ok - unsupported preview addresses are rejected\n'

preview_command "$ROOT" "https://evil.example/a.png" \
  | jq -e '.ok == false and (.error | contains("channel"))' >/dev/null
[[ ! -s $MOCK_CURL_LOG ]]
printf 'ok - preview hosts outside the enabled channels never reach curl\n'

digest="$(printf '%s' "$card" | sha256sum | cut -d' ' -f1)"
mkdir -p -- "$CACHE_ROOT/previews"
printf 'RIFF\x10\x00\x00\x00WEBPVP8 ' >"$CACHE_ROOT/previews/$digest.webp"
result="$(preview_command "$ROOT" "$card")"
jq -e '.ok == true and .cached == true' <<<"$result" >/dev/null
jq -e --arg path "$CACHE_ROOT/previews/$digest.webp" '.path == $path' \
  <<<"$result" >/dev/null
[[ ! -s $MOCK_CURL_LOG ]]
printf 'ok - a cached preview is returned without downloading\n'

detail="https://omarchyplugins.com/assets/img/plugins/a-detail.png"
: >"$MOCK_CURL_LOG"
result="$(MOCK_CURL_BODY=png preview_command "$ROOT" "$detail")"
jq -e '.ok == true and .cached == false' <<<"$result" >/dev/null
downloaded="$(jq -r '.path' <<<"$result")"
[[ -s $downloaded ]]
[[ $(stat -c '%a' -- "$downloaded") == 600 ]]
grep -q -- "--proto =https" "$MOCK_CURL_LOG"
printf 'ok - an allowed preview is downloaded and cached\n'

: >"$MOCK_CURL_LOG"
jq -e '.cached == true' <<<"$(preview_command "$ROOT" "$detail")" >/dev/null
[[ ! -s $MOCK_CURL_LOG ]]
printf 'ok - the second request for the same preview is served from cache\n'

html="https://omarchyplugins.com/assets/img/plugins/a-html.png"
MOCK_CURL_BODY=html preview_command "$ROOT" "$html" \
  | jq -e '.ok == false' >/dev/null
[[ -z $(find "$CACHE_ROOT/previews" -name '.preview.tmp.*' -print -quit) ]]
[[ -z $(find "$CACHE_ROOT/previews" -name "$(printf '%s' "$html" \
  | sha256sum | cut -d ' ' -f 1)*" -print -quit) ]]
printf 'ok - a non-image body is discarded and leaves no cache entry\n'

failing="https://omarchyplugins.com/assets/img/plugins/a-fail.png"
MOCK_CURL_BODY=fail preview_command "$ROOT" "$failing" \
  | jq -e '.ok == false' >/dev/null
printf 'ok - a failed download reports an error\n'

filler="$CACHE_ROOT/previews"
for index in $(seq 1 405); do
  printf '\x89PNG\r\n\x1a\n' >"$filler/filler-$index.png"
  touch -d "2020-01-01 00:00:$((index % 60))" -- "$filler/filler-$index.png"
done
fresh="https://omarchyplugins.com/assets/img/plugins/a-evict.png"
MOCK_CURL_BODY=png preview_command "$ROOT" "$fresh" >/dev/null
count="$(find "$filler" -maxdepth 1 -type f | wc -l)"
(( count <= 400 ))
[[ -s $filler/$(printf '%s' "$fresh" | sha256sum | cut -d ' ' -f 1).png ]]
printf 'ok - the preview cache is trimmed to its limit, newest kept\n'
