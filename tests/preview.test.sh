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
sleep "${MOCK_CURL_SLEEP:-0}"
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

{ preview_command "$ROOT" "http://omarchyplugins.com/a.png" || true; } \
  | jq -e '.ok == false' >/dev/null
{ preview_command "$ROOT" "https://omarchyplugins.com/a.svg" || true; } \
  | jq -e '.ok == false' >/dev/null
{ preview_command "$ROOT" "https://omarchyplugins.com/a.png?x=1" || true; } \
  | jq -e '.ok == false' >/dev/null
printf 'ok - unsupported preview addresses are rejected\n'

{ preview_command "$ROOT" "https://evil.example/a.png" || true; } \
  | jq -e '.ok == false and (.error | contains("channel"))' >/dev/null
[[ ! -s $MOCK_CURL_LOG ]]
printf 'ok - preview hosts outside the enabled channels never reach curl\n'

# A disabled channel's website must never authorize its host, even though
# the shipped config has no disabled channel with a website_url to exercise
# this with. Add one to the test's own config file.
cat >>"$CONFIG_ROOT/channels.yaml" <<'YAML'
  - id: disabled-with-site
    name: Disabled channel with a website
    type: marketplace-catalog
    enabled: false
    catalog_url: https://disabled.example/catalog.json
    website_url: https://disabled.example/
YAML
{ preview_command "$ROOT" "https://disabled.example/a.png" || true; } \
  | jq -e '.ok == false and (.error | contains("channel"))' >/dev/null
[[ ! -s $MOCK_CURL_LOG ]]
printf 'ok - a disabled channel with a website does not authorize its host\n'

# A lookalike host that merely contains the allowed origin as a substring
# (prefix or suffix) must not pass — the match has to be the full origin.
{ preview_command "$ROOT" "https://omarchyplugins.com.evil.example/a.png" \
  || true; } | jq -e '.ok == false and (.error | contains("channel"))' \
  >/dev/null
{ preview_command "$ROOT" "https://evilomarchyplugins.com/a.png" || true; } \
  | jq -e '.ok == false and (.error | contains("channel"))' >/dev/null
[[ ! -s $MOCK_CURL_LOG ]]
printf 'ok - lookalike hosts containing the allowed origin are rejected\n'

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
grep -q -- "--proto-redir =https" "$MOCK_CURL_LOG"
grep -q -- "--max-redirs 0" "$MOCK_CURL_LOG"
grep -q -- "--max-filesize 4194304" "$MOCK_CURL_LOG"
printf 'ok - an allowed preview is downloaded and cached\n'

: >"$MOCK_CURL_LOG"
jq -e '.cached == true' <<<"$(preview_command "$ROOT" "$detail")" >/dev/null
[[ ! -s $MOCK_CURL_LOG ]]
printf 'ok - the second request for the same preview is served from cache\n'

html="https://omarchyplugins.com/assets/img/plugins/a-html.png"
{ MOCK_CURL_BODY=html preview_command "$ROOT" "$html" || true; } \
  | jq -e '.ok == false' >/dev/null
[[ -z $(find "$CACHE_ROOT/previews" -name '.preview.tmp.*' -print -quit) ]]
[[ -z $(find "$CACHE_ROOT/previews" -name "$(printf '%s' "$html" \
  | sha256sum | cut -d ' ' -f 1)*" -print -quit) ]]
printf 'ok - a non-image body is discarded and leaves no cache entry\n'

failing="https://omarchyplugins.com/assets/img/plugins/a-fail.png"
{ MOCK_CURL_BODY=fail preview_command "$ROOT" "$failing" || true; } \
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

concurrent="https://omarchyplugins.com/assets/img/plugins/a-concurrent.png"
: >"$MOCK_CURL_LOG"
(
  MOCK_CURL_SLEEP=0.3 MOCK_CURL_BODY=png \
    preview_command "$ROOT" "$concurrent" >"$TEMP_ROOT/concurrent-one.json"
) &
concurrent_pid_one=$!
(
  MOCK_CURL_SLEEP=0.3 MOCK_CURL_BODY=png \
    preview_command "$ROOT" "$concurrent" >"$TEMP_ROOT/concurrent-two.json"
) &
concurrent_pid_two=$!
wait "$concurrent_pid_one" "$concurrent_pid_two"
jq -e '.ok == true' "$TEMP_ROOT/concurrent-one.json" >/dev/null
jq -e '.ok == true' "$TEMP_ROOT/concurrent-two.json" >/dev/null
curl_calls="$(grep -Fc -- "$concurrent" "$MOCK_CURL_LOG" || true)"
[[ $curl_calls == 1 ]]
printf 'ok - concurrent requests for the same preview issue exactly one download\n'

canary="$TEMP_ROOT/canary.txt"
printf 'do-not-touch\n' >"$canary"
symlinked="https://omarchyplugins.com/assets/img/plugins/a-symlink.png"
symlinked_digest="$(printf '%s' "$symlinked" | sha256sum | cut -d ' ' -f 1)"
symlinked_target="$CACHE_ROOT/previews/$symlinked_digest.png"
ln -s "$canary" "$symlinked_target"
: >"$MOCK_CURL_LOG"
result="$(MOCK_CURL_BODY=png preview_command "$ROOT" "$symlinked")"
jq -e '.ok == true and .cached == false' <<<"$result" >/dev/null
[[ -s $MOCK_CURL_LOG ]]
[[ ! -L $symlinked_target ]]
[[ -s $symlinked_target ]]
[[ $(cat "$canary") == "do-not-touch" ]]
printf 'ok - a symlinked cache entry is replaced instead of trusted or written through\n'
