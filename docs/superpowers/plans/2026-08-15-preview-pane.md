# Preview Pane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a screenshot and repository metadata for the selected plugin in a pane beside the results list, sourced from preview fields the marketplace catalog already ships.

**Architecture:** `lib/catalog.jq` stops discarding the catalog's preview and metadata fields and resolves the site-relative paths into absolute URLs against the channel's `website_url`. A new `plugin-control preview` subcommand downloads one image into `~/.cache/omarchy/plugin-control/previews/` and prints its local path, so QML never performs network access. `Service.qml` queues those requests one at a time; a new `PreviewPane.qml` renders the picture and metadata beside the `ListView`, and a new `PreviewLightbox.qml` shows the large image on `Ctrl+E` or a click.

**Tech Stack:** Bash 5, jq, Ruby (Psych), QML / Quickshell, Node (test runner only).

**Spec:** `docs/superpowers/specs/2026-08-15-preview-pane-design.md`

## Global Constraints

- Branch: `preview-pane`. Commit after every task.
- QML must never open a network connection. All fetching happens in `bin/plugin-control`.
- A malformed preview field blanks the picture; it must never reject a catalog row or hide a plugin.
- The `preview` subcommand downloads only from the origin of an **enabled** channel's `website_url`.
- `https` only, enforced by both the URL check and `curl --proto '=https' --proto-redir '=https'`.
- No new runtime dependencies. `curl`, `jq`, `flock`, `sha256sum`, `realpath`, `ruby` are already required.
- Existing keybindings do not change. `Enter` is not overloaded; the enlarged view uses `Ctrl+E`.
- Settings stay under strict schema 2 — unknown keys must still be rejected.
- No AI attribution in commit messages.
- Shell style follows the existing file: `local` declarations first, `[[ ]]` tests, `printf` over `echo`, two-space indent.

**Deviation from the spec, carried through this plan:** the subcommand is
`preview <root> <url>`, not `preview <url>`. The host allowlist reads the
channel configuration through `load_config`, which needs the source root, and
every other subcommand already takes the root as its first argument.

---

### Task 1: Catalog preview and metadata fields

**Files:**
- Modify: `lib/catalog.jq`
- Create: `tests/fixtures/catalog-preview.json`
- Test: `tests/catalog.test.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: each normalized record gains `previewThumbnail` (absolute URL string or `""`), `previewImage` (same), `previewThumbnailWidth`, `previewThumbnailHeight`, `previewWidth`, `previewHeight` (integers, `0` when unusable), `stars` (integer), `license` (string), `repositoryUpdatedAt` (string). The script reads an optional `--arg previewBase` through `$ARGS.named.previewBase`, so callers that do not pass it keep working.

- [ ] **Step 1: Write the fixture**

Create `tests/fixtures/catalog-preview.json`:

```json
{
  "stateSchemaVersion": 1,
  "generatedAt": "2026-08-15T00:00:00Z",
  "plugins": [
    {
      "id": "preview.good",
      "name": "Good preview",
      "sourceType": "community",
      "previewThumbnail": "assets/img/plugins/a-card.webp",
      "previewImage": "assets/img/plugins/a-detail.webp",
      "previewThumbnailWidth": 720,
      "previewThumbnailHeight": 405,
      "previewWidth": 1600,
      "previewHeight": 900,
      "stars": 13,
      "license": "MIT",
      "repositoryUpdatedAt": "2026-08-11T17:06:54Z"
    },
    {
      "id": "preview.absolute",
      "name": "Absolute URL",
      "sourceType": "community",
      "previewThumbnail": "https://evil.example/x.png"
    },
    {
      "id": "preview.traversal",
      "name": "Traversal",
      "sourceType": "community",
      "previewThumbnail": "assets/../../etc/passwd.png"
    },
    {
      "id": "preview.control",
      "name": "Control character",
      "sourceType": "community",
      "previewThumbnail": "assets/img/a.png"
    },
    {
      "id": "preview.extension",
      "name": "Wrong extension",
      "sourceType": "community",
      "previewThumbnail": "assets/img/a.svg"
    },
    {
      "id": "preview.rooted",
      "name": "Leading slash",
      "sourceType": "community",
      "previewThumbnail": "/assets/img/a.png"
    },
    {
      "id": "preview.numbers",
      "name": "Out of range numbers",
      "sourceType": "community",
      "previewThumbnail": "assets/img/plugins/b-card.webp",
      "previewThumbnailWidth": 99999,
      "stars": -5
    }
  ]
}
```

- [ ] **Step 2: Write the failing test**

Append to `tests/catalog.test.sh`, immediately after the
`ok - custom catalogs cannot impersonate native built-ins` block (before the
`export HOME=` line, because everything below that point sources the helper):

```bash
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
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `tests/catalog.test.sh`
Expected: FAIL — the first `jq -e` on `.records[0].previewThumbnail` returns
false because the field does not exist yet (jq exits 1 on a `null` result).

- [ ] **Step 4: Add the validators to `lib/catalog.jq`**

Insert after the `valid_tags` definition (line 25) and before `valid_release`:

```jq
def valid_preview_path:
  type == "string"
  and length > 0
  and length <= 512
  and (test("[[:cntrl:]]") | not)
  and test("^[A-Za-z0-9][A-Za-z0-9._/-]*$")
  and (contains("..") | not)
  and (ascii_downcase | test("\\.(webp|png|jpg|jpeg|gif)$"));

def preview_base:
  ($ARGS.named.previewBase // "")
  | if type == "string"
      and length <= 2048
      and test("^https://[A-Za-z0-9][A-Za-z0-9.-]*(:[0-9]{1,5})?(/[A-Za-z0-9._~/-]*)?$")
    then sub("/+$"; "")
    else ""
    end;

def preview_url($key):
  (preview_base) as $base
  | if $base == "" then ""
    elif ((.[$key] // null) | type) != "string" then ""
    elif (.[$key] | valid_preview_path | not) then ""
    else $base + "/" + .[$key]
    end;

def bounded_number($key; $maximum):
  (.[$key] // 0)
  | if type == "number" and . >= 0 and . <= $maximum then floor else 0 end;
```

- [ ] **Step 5: Extend `row_valid` and `normalized_record`**

In `row_valid`, add two lines after `and optional_string("upstreamCheckStatus"; 80)`:

```jq
  and optional_string("license"; 120)
  and optional_string("repositoryUpdatedAt"; 64)
```

In `normalized_record`, replace the final field line
`releaseTag: (.repositoryRelease.tag // "")` with:

```jq
      releaseTag: (.repositoryRelease.tag // ""),
      license: (.license // ""),
      stars: bounded_number("stars"; 1000000),
      repositoryUpdatedAt: (.repositoryUpdatedAt // ""),
      previewThumbnail: preview_url("previewThumbnail"),
      previewImage: preview_url("previewImage"),
      previewThumbnailWidth: bounded_number("previewThumbnailWidth"; 10000),
      previewThumbnailHeight: bounded_number("previewThumbnailHeight"; 10000),
      previewWidth: bounded_number("previewWidth"; 10000),
      previewHeight: bounded_number("previewHeight"; 10000)
```

Preview paths are deliberately **not** added to `row_valid`: a bad picture must
not hide a plugin.

- [ ] **Step 6: Run the test to verify it passes**

Run: `tests/catalog.test.sh`
Expected: PASS, including the four pre-existing `ok -` lines.

- [ ] **Step 7: Commit**

```bash
git add lib/catalog.jq tests/catalog.test.sh tests/fixtures/catalog-preview.json
git commit -m "feat: keep marketplace preview and metadata fields"
```

---

### Task 2: Pass the channel website into normalization

**Files:**
- Modify: `bin/plugin-control:234-245` (`normalize_catalog`), `bin/plugin-control:270-313` (`refresh_catalog_channel`)
- Test: `tests/catalog.test.sh`

**Interfaces:**
- Consumes: `preview_base` handling from Task 1.
- Produces: `normalize_catalog <root> <raw> <channel_name> <source> <rank> [preview_base]` — the sixth argument is optional and defaults to empty.

- [ ] **Step 1: Write the failing test**

Append at the end of `tests/catalog.test.sh`:

```bash
download_catalog() {
  jq '.plugins[0].previewThumbnail = "assets/img/plugins/a-card.webp"' \
    "$TEST_DIR/fixtures/catalog-valid.json" >"$2"
  : >"$3"
  printf '200\n'
}
channel_with_site="$(jq -c '. + {website_url:"https://omarchyplugins.com/"}' \
  <<<"$channel")"
refresh_catalog_channel "$ROOT" "$channel_with_site"
jq -e '.records[0].previewThumbnail
  == "https://omarchyplugins.com/assets/img/plugins/a-card.webp"' \
  "$CHANNEL_CACHE/marketplace.json" >/dev/null
printf 'ok - refresh resolves previews against the channel website\n'

refresh_catalog_channel "$ROOT" "$channel"
jq -e '.records[0].previewThumbnail == ""' \
  "$CHANNEL_CACHE/marketplace.json" >/dev/null
printf 'ok - a channel without a website produces no previews\n'
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `tests/catalog.test.sh`
Expected: FAIL on `ok - refresh resolves previews...` — the cached record's
`previewThumbnail` is `""` because the website is never passed to jq.

- [ ] **Step 3: Add the parameter to `normalize_catalog`**

```bash
normalize_catalog() {
  local root="$1"
  local raw="$2"
  local channel_name="$3"
  local source="$4"
  local rank="$5"
  local preview_base="${6:-}"
  jq -c \
    --arg channelName "$channel_name" \
    --arg channelSource "$source" \
    --argjson channelRank "$rank" \
    --arg previewBase "$preview_base" \
    -f "$root/lib/catalog.jq" "$raw"
}
```

- [ ] **Step 4: Read and forward the website in `refresh_catalog_channel`**

Change the declaration line

```bash
  local channel_id channel_name source rank url
```

to

```bash
  local channel_id channel_name source rank url website
```

and add after the `url="$(jq -r '.catalog_url' <<<"$channel")"` line:

```bash
  website="$(jq -r '.website_url // ""' <<<"$channel")"
```

Then change the normalization call to:

```bash
  normalized="$(normalize_catalog "$root" "$body" \
    "$channel_name" "$source" "$rank" "$website" 2>/dev/null)" || {
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `tests/catalog.test.sh`
Expected: PASS on every line including the two new ones.

- [ ] **Step 6: Commit**

```bash
git add bin/plugin-control tests/catalog.test.sh
git commit -m "feat: resolve previews against the channel website"
```

---

### Task 3: Preview command — validation, allowlist, cache hit

**Files:**
- Modify: `bin/plugin-control` (new functions after `download_catalog`, new `preview)` case in `main`, updated `usage`)
- Create: `tests/preview.test.sh`
- Modify: `tests/all.sh`

**Interfaces:**
- Consumes: `load_config` (already present), `init_paths`, `$CACHE_ROOT`.
- Produces: `preview_command <root> <url>` printing
  `{"ok":true,"path":"<absolute path>","cached":true|false}` on success and
  `{"ok":false,"error":"<message>"}` on failure. Helpers available to later
  tasks: `preview_cache_dir`, `preview_extension <url>`, `preview_url_valid <url>`,
  `preview_origin <url>`, `preview_host_allowed <root> <url>`.

- [ ] **Step 1: Write the failing test**

Create `tests/preview.test.sh` (make it executable with `chmod 0755`):

```bash
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `tests/preview.test.sh`
Expected: FAIL with `preview_command: command not found`.

- [ ] **Step 3: Add the helpers to `bin/plugin-control`**

Insert immediately after the closing brace of `download_catalog`:

```bash
preview_cache_dir() {
  printf '%s\n' "$CACHE_ROOT/previews"
}

preview_url_valid() {
  local url="${1:-}"
  [[ ${#url} -le 2048 ]] || return 1
  [[ $url =~ ^https://[A-Za-z0-9][A-Za-z0-9.-]*(:[0-9]{1,5})?/[A-Za-z0-9._~/-]+$ ]]
}

preview_extension() {
  local lowered="${1,,}"
  case "$lowered" in
    *.webp) printf '.webp\n' ;;
    *.png) printf '.png\n' ;;
    *.jpg | *.jpeg) printf '.jpg\n' ;;
    *.gif) printf '.gif\n' ;;
    *) return 1 ;;
  esac
}

preview_origin() {
  local rest="${1#https://}"
  printf 'https://%s\n' "${rest%%/*}"
}

preview_host_allowed() {
  local root="$1"
  local url="$2"
  local config origin
  origin="$(preview_origin "$url")"
  config="$(load_config "$root")" || return 1
  jq -e --arg origin "$origin" '
    [.channels[]
      | select(.enabled == true)
      | (.website_url // "")
      | select(. != "")
      | capture("^(?<origin>https://[^/]+)").origin]
    | index($origin) != null' <<<"$config" >/dev/null
}

preview_command() {
  local root="$1"
  local url="${2:-}"
  local extension digest target directory
  preview_url_valid "$url" || {
    json_error "unsupported preview address"
    return 1
  }
  extension="$(preview_extension "$url")" || {
    json_error "unsupported preview image type"
    return 1
  }
  preview_host_allowed "$root" "$url" || {
    json_error "preview host is not an enabled channel"
    return 1
  }
  digest="$(printf '%s' "$url" | sha256sum | cut -d ' ' -f 1)"
  directory="$(preview_cache_dir)"
  target="$directory/$digest$extension"
  mkdir -p -- "$directory"
  if [[ -f $target && ! -L $target && -s $target ]]; then
    touch -- "$target"
    jq -cn --arg path "$target" '{ok:true,path:$path,cached:true}'
    return
  fi
  json_error "could not download the preview"
  return 1
}
```

The final two lines are a placeholder that Task 4 replaces with the download.

- [ ] **Step 4: Wire the subcommand into `main`**

In `main`'s second `case`, add after the `config-status)` block:

```bash
    preview)
      (( $# == 2 )) || { usage; return 2; }
      preview_command "$(source_root "$1")" "$2"
      ;;
```

and update `usage` to:

```bash
usage() {
  json_error "usage: plugin-control <cached|refresh|ensure-config|config-status|status|action|ack|preview|benchmark> ..."
}
```

- [ ] **Step 5: Register the test file**

In `tests/all.sh`, add after the `"$TEST_DIR/catalog.test.sh"` line:

```bash
"$TEST_DIR/preview.test.sh"
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `tests/preview.test.sh`
Expected: PASS on all three `ok -` lines.

- [ ] **Step 7: Commit**

```bash
git add bin/plugin-control tests/preview.test.sh tests/all.sh
git commit -m "feat: add a preview subcommand with a channel host allowlist"
```

---

### Task 4: Preview command — download, signature check, atomic write

**Files:**
- Modify: `bin/plugin-control` (new `preview_is_image`, `preview_download`; `preview_command` replaces its placeholder)
- Test: `tests/preview.test.sh`

**Interfaces:**
- Consumes: `preview_command` and helpers from Task 3.
- Produces: `preview_download <url> <target>` returning 0 on a verified image, non-zero otherwise; `preview_is_image <file>` returning 0 for PNG, JPEG, GIF or WebP content.

- [ ] **Step 1: Write the failing test**

Append to `tests/preview.test.sh`:

```bash
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `tests/preview.test.sh`
Expected: FAIL on `ok - an allowed preview is downloaded and cached` — the
placeholder returns `{"ok":false,...}`.

- [ ] **Step 3: Add the download helpers**

Insert before `preview_command`:

```bash
preview_is_image() {
  local file="$1"
  local signature
  [[ -s $file ]] || return 1
  signature="$(od -An -tx1 -N 12 -- "$file" | tr -d ' \n')"
  case "$signature" in
    89504e470d0a1a0a*) return 0 ;;
    ffd8ff*) return 0 ;;
    474946383761* | 474946383961*) return 0 ;;
    52494646????????57454250*) return 0 ;;
  esac
  return 1
}

preview_download() {
  local url="$1"
  local target="$2"
  local directory temporary
  directory="$(dirname -- "$target")"
  temporary="$(mktemp "$directory/.preview.tmp.XXXXXX")" || return 1
  if ! curl --fail --silent --show-error --location \
    --proto '=https' --proto-redir '=https' --max-redirs 3 \
    --connect-timeout 5 --max-time 20 --max-filesize 4194304 \
    --header 'User-Agent: plugin-control/0.1.0' \
    --output "$temporary" -- "$url"; then
    rm -f -- "$temporary"
    return 1
  fi
  if ! preview_is_image "$temporary"; then
    rm -f -- "$temporary"
    return 1
  fi
  chmod 0600 "$temporary"
  mv -fT -- "$temporary" "$target" || {
    rm -f -- "$temporary"
    return 1
  }
}
```

- [ ] **Step 4: Replace the placeholder in `preview_command`**

Replace the final two lines of `preview_command`

```bash
  json_error "could not download the preview"
  return 1
```

with:

```bash
  preview_download "$url" "$target" || {
    json_error "could not download the preview"
    return 1
  }
  jq -cn --arg path "$target" '{ok:true,path:$path,cached:false}'
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `tests/preview.test.sh`
Expected: PASS on all seven `ok -` lines.

- [ ] **Step 6: Commit**

```bash
git add bin/plugin-control tests/preview.test.sh
git commit -m "feat: download previews through a verified image fetch"
```

---

### Task 5: Preview command — eviction and concurrency lock

**Files:**
- Modify: `bin/plugin-control` (`preview_evict`, lock inside `preview_command`)
- Test: `tests/preview.test.sh`

**Interfaces:**
- Consumes: `preview_command` from Task 4.
- Produces: `preview_evict` trimming the previews directory to `PREVIEW_CACHE_LIMIT` (400) files, oldest first.

- [ ] **Step 1: Write the failing test**

Append to `tests/preview.test.sh`:

```bash
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `tests/preview.test.sh`
Expected: FAIL on `(( count <= 400 ))` — 406 files remain.

- [ ] **Step 3: Add eviction**

Insert before `preview_command`:

```bash
readonly PREVIEW_CACHE_LIMIT=400

preview_evict() {
  local directory count excess
  directory="$(preview_cache_dir)"
  [[ -d $directory ]] || return 0
  count="$(find "$directory" -maxdepth 1 -type f -printf '.' | wc -c)"
  (( count > PREVIEW_CACHE_LIMIT )) || return 0
  excess=$(( count - PREVIEW_CACHE_LIMIT ))
  find "$directory" -maxdepth 1 -type f -printf '%T@ %p\0' \
    | sort -z -n \
    | head -z -n "$excess" \
    | while IFS=' ' read -r -d '' _ path; do
      rm -f -- "$path"
    done
}
```

- [ ] **Step 4: Call eviction and take the per-image lock**

In `preview_command`, wrap everything from the `mkdir -p` line to the end in a
lock block so two rapid selections of the same plugin cannot both download it:

```bash
  mkdir -p -- "$directory"
  {
    flock -w 10 11 || {
      json_error "another preview download is in progress"
      return 1
    }
    if [[ -f $target && ! -L $target && -s $target ]]; then
      touch -- "$target"
      jq -cn --arg path "$target" '{ok:true,path:$path,cached:true}'
      return
    fi
    preview_download "$url" "$target" || {
      json_error "could not download the preview"
      return 1
    }
    preview_evict
    jq -cn --arg path "$target" '{ok:true,path:$path,cached:false}'
  } 11>"$RUNTIME_ROOT/preview-$digest.lock"
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `tests/preview.test.sh`
Expected: PASS on all eight `ok -` lines.

Run: `bash -n bin/plugin-control`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add bin/plugin-control tests/preview.test.sh
git commit -m "feat: bound the preview cache and lock concurrent fetches"
```

---

### Task 6: The `preview-pane-hidden` setting

**Files:**
- Modify: `lib/channel_config.rb:13`, `lib/channel_config.rb:98-109`
- Modify: `config/channels.yaml`
- Test: `tests/channel_config.test.rb`

**Interfaces:**
- Consumes: nothing.
- Produces: validated configuration gains `settings["preview-pane-hidden"]`, a boolean defaulting to `false`. `config-status` therefore carries it to QML.

- [ ] **Step 1: Write the failing test**

Append to `tests/channel_config.test.rb`:

```ruby
test("preview pane defaults to visible") do
  config = PluginControl.load_file(DEFAULT)
  assert_equal false, config.dig("settings", "preview-pane-hidden")
end

test("preview pane can be hidden") do
  config = parse(default_text.sub("preview-pane-hidden: false",
    "preview-pane-hidden: true"))
  assert_equal true, config.dig("settings", "preview-pane-hidden")
end

test("preview pane setting must be boolean") do
  assert_invalid(default_text.sub("preview-pane-hidden: false",
    "preview-pane-hidden: sometimes"), "true or false")
end

test("preview pane setting is optional") do
  config = parse(default_text.sub("\n  preview-pane-hidden: false", ""))
  assert_equal false, config.dig("settings", "preview-pane-hidden")
end
```

Also update the existing `every settings field is required` test, whose
substitution would otherwise leave an orphaned indented line:

```ruby
test("every settings field is required") do
  assert_invalid(default_text.sub(
    "settings:\n  tray-icon-hidden: false\n  preview-pane-hidden: false",
    "settings: {}"),
    "settings.tray-icon-hidden must be true or false")
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `ruby tests/channel_config.test.rb`
Expected: FAIL on `not ok - preview pane defaults to visible` (the key is
absent, so `dig` returns `nil`).

- [ ] **Step 3: Add the key to the template**

In `config/channels.yaml`, change the settings block to:

```yaml
settings:
  tray-icon-hidden: false
  preview-pane-hidden: false
```

- [ ] **Step 4: Accept the key in the validator**

In `lib/channel_config.rb`, change line 13 to:

```ruby
  SETTINGS_KEYS = %w[tray-icon-hidden preview-pane-hidden].freeze
```

and change the hash returned by `validate_settings` to:

```ruby
    {
      "tray-icon-hidden" => exact_boolean(
        settings["tray-icon-hidden"],
        "settings.tray-icon-hidden"),
      "preview-pane-hidden" => exact_boolean(
        settings.fetch("preview-pane-hidden", false),
        "settings.preview-pane-hidden")
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `ruby tests/channel_config.test.rb`
Expected: PASS on every line.

Run: `tests/catalog.test.sh`
Expected: PASS — it copies `config/channels.yaml` into place, so a template
mistake surfaces here.

- [ ] **Step 6: Commit**

```bash
git add lib/channel_config.rb config/channels.yaml tests/channel_config.test.rb
git commit -m "feat: add the preview-pane-hidden setting"
```

---

### Task 7: Carry the fields through the record model

**Files:**
- Modify: `CatalogModel.js:75-105`
- Test: `tests/model.test.js`

**Interfaces:**
- Consumes: record fields from Task 1.
- Produces: every prepared record has `previewThumbnail` and `previewImage` (https-only strings, `""` otherwise), `previewThumbnailWidth`, `previewThumbnailHeight`, `previewWidth`, `previewHeight`, `stars` (numbers, `0` otherwise), `license`, `repositoryUpdatedAt` (strings). Preview URLs are deliberately excluded from `searchFields`.

- [ ] **Step 1: Write the failing test**

Append to `tests/model.test.js`, before the final lines of the file:

```js
test("preview fields survive preparation", () => {
  const prepared = Catalog.prepareRecords([
    {
      id: "io.example.preview",
      name: "Preview",
      source: "marketplace",
      previewThumbnail: "https://omarchyplugins.com/a-card.webp",
      previewImage: "https://omarchyplugins.com/a-detail.webp",
      previewThumbnailWidth: 720,
      previewThumbnailHeight: 405,
      previewWidth: 1600,
      previewHeight: 900,
      stars: 13,
      license: "MIT",
      repositoryUpdatedAt: "2026-08-11T17:06:54Z"
    }
  ]);
  assert.equal(prepared[0].previewThumbnail,
    "https://omarchyplugins.com/a-card.webp");
  assert.equal(prepared[0].previewImage,
    "https://omarchyplugins.com/a-detail.webp");
  assert.equal(prepared[0].previewThumbnailWidth, 720);
  assert.equal(prepared[0].previewHeight, 900);
  assert.equal(prepared[0].stars, 13);
  assert.equal(prepared[0].license, "MIT");
  assert.equal(prepared[0].repositoryUpdatedAt, "2026-08-11T17:06:54Z");
});

test("non-https previews and bad numbers are dropped", () => {
  const prepared = Catalog.prepareRecords([
    {
      id: "io.example.bad",
      name: "Bad",
      source: "marketplace",
      previewThumbnail: "file:///etc/passwd",
      previewImage: "",
      previewThumbnailWidth: "wide",
      stars: -3
    }
  ]);
  assert.equal(prepared[0].previewThumbnail, "");
  assert.equal(prepared[0].previewImage, "");
  assert.equal(prepared[0].previewThumbnailWidth, 0);
  assert.equal(prepared[0].stars, 0);
});

test("preview URLs are not searchable text", () => {
  const prepared = Catalog.prepareRecords([
    {
      id: "io.example.search",
      name: "Search",
      source: "marketplace",
      previewThumbnail: "https://omarchyplugins.com/zzzunique.webp"
    }
  ]);
  assert.equal(prepared[0].searchFields.join(" ").indexOf("zzzunique"), -1);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `node tests/model.test.js`
Expected: FAIL — `previewThumbnailWidth` is the string `"wide"` rather than `0`
(the raw value is copied verbatim today).

- [ ] **Step 3: Add the helpers**

In `CatalogModel.js`, add after the `searchText` function:

```js
function httpsUrl(value) {
  var raw = cleanText(value)
  return raw.indexOf("https://") === 0 ? raw : ""
}

function countNumber(value) {
  var number = Number(value)
  return isFinite(number) && number > 0 ? Math.floor(number) : 0
}
```

- [ ] **Step 4: Normalize the new fields**

In `normalizeRecord`, add after the `record.kind = cleanText(record.kind)` line:

```js
  record.license = cleanText(record.license)
  record.repositoryUpdatedAt = cleanText(record.repositoryUpdatedAt)
  record.stars = countNumber(record.stars)
  record.previewThumbnail = httpsUrl(record.previewThumbnail)
  record.previewImage = httpsUrl(record.previewImage)
  record.previewThumbnailWidth = countNumber(record.previewThumbnailWidth)
  record.previewThumbnailHeight = countNumber(record.previewThumbnailHeight)
  record.previewWidth = countNumber(record.previewWidth)
  record.previewHeight = countNumber(record.previewHeight)
```

Leave `record.searchFields` untouched.

- [ ] **Step 5: Run the test to verify it passes**

Run: `node tests/model.test.js`
Expected: PASS on every line.

- [ ] **Step 6: Commit**

```bash
git add CatalogModel.js tests/model.test.js
git commit -m "feat: normalize preview fields on catalog records"
```

---

### Task 8: Service-side preview queue

**Files:**
- Modify: `Service.qml:75-92` (`applyConfigStatus`), and add new members near the other `Process` blocks

**Interfaces:**
- Consumes: `plugin-control preview <root> <url>` from Tasks 3–5; `preview-pane-hidden` from Task 6.
- Produces: on the service object — `property bool previewPaneHidden`, `function previewPathFor(url) -> string`, `function requestPreview(url)`, `signal previewReady(string url, string path)`.

- [ ] **Step 1: Add the properties and signal**

In `Service.qml`, after `property bool animationsEnabled: true`, add:

```qml
  property bool previewPaneHidden: false
  property var previewPaths: ({})
  property var previewFailed: ({})
  property var previewQueue: []
```

and after `signal actionFinished(var state)`:

```qml
  signal previewReady(string url, string path)
```

- [ ] **Step 2: Read the setting before the tray early return**

In `applyConfigStatus`, insert immediately after
`var settings = parsed.config.settings`:

```qml
    var previewHidden = settings ? settings["preview-pane-hidden"] : undefined
    if (typeof previewHidden === "boolean") previewPaneHidden = previewHidden
```

This must come before the existing `tray-icon-hidden` check, which returns
early when that key is missing.

- [ ] **Step 3: Add the queue functions**

Add after the `requestStatus` function:

```qml
  function previewPathFor(url) {
    var key = String(url || "")
    if (!key) return ""
    return String(previewPaths[key] || "")
  }

  function requestPreview(url) {
    var key = String(url || "")
    if (!key || previewPaneHidden || !helperPath) return
    if (key.indexOf("https://") !== 0) return
    if (previewPaths[key] || previewFailed[key]) return
    if (previewProcess.currentUrl === key) return
    if (previewQueue.indexOf(key) >= 0) return
    var queue = previewQueue.slice()
    queue.push(key)
    while (queue.length > 12) queue.shift()
    previewQueue = queue
    startNextPreview()
  }

  function startNextPreview() {
    if (!helperPath || previewProcess.running) return
    if (previewQueue.length === 0) return
    var queue = previewQueue.slice()
    var next = queue.shift()
    previewQueue = queue
    previewProcess.output = ""
    previewProcess.currentUrl = next
    previewProcess.command = [helperPath, "preview", sourceDir, next]
    previewProcess.running = true
  }

  function acceptPreview(raw) {
    var url = String(previewProcess.currentUrl || "")
    previewProcess.currentUrl = ""
    var parsed = parseJson(raw, null)
    var key
    if (parsed && parsed.ok === true && String(parsed.path || "")) {
      var paths = ({})
      for (key in previewPaths) paths[key] = previewPaths[key]
      paths[url] = String(parsed.path)
      previewPaths = paths
      previewReady(url, paths[url])
    } else if (url) {
      var failed = ({})
      for (key in previewFailed) failed[key] = previewFailed[key]
      failed[url] = true
      previewFailed = failed
    }
    Qt.callLater(startNextPreview)
  }
```

- [ ] **Step 4: Add the process**

Add after the `statusProcess` block:

```qml
  Process {
    id: previewProcess
    property string output: ""
    property string currentUrl: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: previewProcess.output = text
    }
    onExited: root.acceptPreview(output)
  }
```

- [ ] **Step 5: Verify the QML still loads**

Run: `tests/qml.test.sh`
Expected: PASS (this stage checks the QML parses and imports cleanly).

- [ ] **Step 6: Commit**

```bash
git add Service.qml
git commit -m "feat: queue preview fetches through the helper"
```

---

### Task 9: The preview pane

**Files:**
- Create: `PreviewPane.qml`
- Modify: `PluginControl.qml:56-57` (`cardWidth`), `PluginControl.qml:858-880` (results area), plus new properties and a warm-up timer
- Test: `tests/qml.test.sh` (lint list)

**Interfaces:**
- Consumes: `service.requestPreview`, `service.previewPathFor`, `service.previewReady`, `service.previewPaneHidden` from Task 8; record fields from Task 7.
- Produces: on `root` — `readonly property bool previewPaneVisible`, `readonly property int previewPaneWidth`, `function warmPreviews()`. `PreviewPane` exposes `property var record`, `property var service`, `property color foreground`, `signal imageActivated()`.

- [ ] **Step 1: Create `PreviewPane.qml`**

```qml
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property var record: null
  property var service: null
  property color foreground: Color.menu.text
  property string imagePath: ""

  readonly property string thumbnailUrl: record && record.previewThumbnail
    ? String(record.previewThumbnail) : ""
  readonly property bool hasImage: imagePath !== ""

  signal imageActivated()

  function metadataLine() {
    if (!record) return ""
    var parts = []
    if (Number(record.stars) > 0) parts.push("★ " + Number(record.stars))
    if (String(record.license || "")) parts.push(String(record.license))
    if (String(record.category || "")) parts.push(String(record.category))
    return parts.join("  ·  ")
  }

  function updatedLine() {
    var when = Date.parse(String(record && record.repositoryUpdatedAt || ""))
    if (!isFinite(when)) return ""
    var days = Math.floor((Date.now() - when) / 86400000)
    if (days <= 0) return "Updated today"
    if (days === 1) return "Updated yesterday"
    if (days < 30) return "Updated " + days + " days ago"
    if (days < 365) return "Updated " + Math.floor(days / 30) + " months ago"
    return "Updated " + Math.floor(days / 365) + " years ago"
  }

  function refresh() {
    imagePath = service && thumbnailUrl
      ? service.previewPathFor(thumbnailUrl) : ""
    if (!imagePath && thumbnailUrl) fetchDebounce.restart()
    else fetchDebounce.stop()
  }

  onThumbnailUrlChanged: refresh()

  Timer {
    id: fetchDebounce
    interval: 150
    repeat: false
    onTriggered: {
      if (root.service && root.thumbnailUrl)
        root.service.requestPreview(root.thumbnailUrl)
    }
  }

  Connections {
    target: root.service
    function onPreviewReady(url, path) {
      if (url === root.thumbnailUrl) root.imagePath = path
    }
  }

  Column {
    anchors.fill: parent
    spacing: Style.spacing.sm

    Rectangle {
      id: imageFrame
      width: parent.width
      height: Math.round(width * 9 / 16)
      radius: Style.cornerRadius
      color: Util.alpha(root.foreground, 0.06)
      clip: true

      Image {
        anchors.fill: parent
        source: root.hasImage ? "file://" + root.imagePath : ""
        visible: root.hasImage && status === Image.Ready
        asynchronous: true
        cache: true
        fillMode: Image.PreserveAspectFit
        sourceSize.width: Math.round(imageFrame.width)
      }

      Text {
        anchors.centerIn: parent
        visible: !root.hasImage
        text: root.thumbnailUrl ? "Loading…" : "No screenshot"
        color: root.foreground
        opacity: 0.45
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
      }

      MouseArea {
        anchors.fill: parent
        enabled: root.hasImage
        cursorShape: root.hasImage ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.imageActivated()
      }
    }

    Text {
      width: parent.width
      text: root.record ? String(root.record.name || "") : ""
      textFormat: Text.PlainText
      color: root.foreground
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.title
      font.bold: true
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      visible: text !== ""
      text: {
        if (!root.record) return ""
        var author = String(root.record.author || "")
        var version = String(root.record.version || "")
        return version ? (author ? author + "  ·  v" + version : "v" + version)
          : author
      }
      textFormat: Text.PlainText
      color: root.foreground
      opacity: 0.70
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      visible: text !== ""
      text: root.metadataLine()
      textFormat: Text.PlainText
      color: root.foreground
      opacity: 0.60
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      visible: text !== ""
      text: root.updatedLine()
      textFormat: Text.PlainText
      color: root.foreground
      opacity: 0.50
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }
}
```

- [ ] **Step 2: Add the sizing properties in `PluginControl.qml`**

Replace the `cardWidth` property (lines 56-57) with:

```qml
  readonly property bool previewPaneVisible: root.service
    && !root.service.previewPaneHidden
    && paletteChromeVisible
    && !actionDialog.opened
    && panel.width >= Style.space(900)
  readonly property int previewPaneWidth: previewPaneVisible
    ? Style.space(320) : 0
  readonly property int cardWidth: Math.min(
    previewPaneVisible ? Style.space(1080) : Style.space(720),
    Math.max(Style.space(320), panel.width - Style.gapsOut * 2))
```

- [ ] **Step 3: Add the warm-up**

Add after the `rebuildResults` function:

```qml
  function warmPreviews() {
    if (!service || !previewPaneVisible) return
    var start = Math.max(0, selectedIndex - 2)
    var end = Math.min(filteredRecords.length, start + 8)
    for (var index = start; index < end; index++) {
      var record = filteredRecords[index]
      if (record && record.previewThumbnail)
        service.requestPreview(record.previewThumbnail)
    }
  }
```

and a timer beside the other `Timer` elements:

```qml
  Timer {
    id: warmPreviewsTimer
    interval: 250
    repeat: false
    onTriggered: root.warmPreviews()
  }
```

At the end of `rebuildResults`, add:

```qml
    warmPreviewsTimer.restart()
```

- [ ] **Step 4: Put the pane beside the list**

In the results `Item` (line 858), keep the `Item`'s own `width`/`height`/`clip`
and replace its single `ListView` child with a `Row` that holds the list and the
pane. The `ListView` keeps every existing property and its delegate — only its
parent changes:

```qml
        Item {
          width: parent.width
          height: Math.max(root.rowHeight,
            parent.height - root.activeHeaderHeight - root.activeFooterHeight
              - root.activeFilterRowHeight - root.statusHeight
              - parent.spacing * root.chromeSpacingCount)
          clip: true

          Row {
            anchors.fill: parent
            spacing: root.previewPaneVisible ? Style.spacing.md : 0

            Item {
              width: parent.width - root.previewPaneWidth - parent.spacing
              height: parent.height
              clip: true

              ListView {
                id: resultList
                // ...unchanged: focus, anchors.fill, visible, model, clip,
                // boundsBehavior, spacing, Keys handling, delegate...
              }
            }

            PreviewPane {
              id: previewPane
              width: root.previewPaneWidth
              height: parent.height
              visible: root.previewPaneVisible
              record: root.selectedRecord
              service: root.service
              foreground: root.foreground
            }
          }
        }
```

- [ ] **Step 5: Add the new file to the QML lint list**

`tests/qml.test.sh` lints a fixed list of files, so a new file is otherwise
never checked. Add `"$ROOT/PreviewPane.qml"` to the `qmllint` invocation:

```bash
"$qmllint_bin" -I /usr/share/omarchy/shell \
  "$ROOT/Service.qml" "$ROOT/PluginControl.qml" "$ROOT/ActionDialog.qml" \
  "$ROOT/PreviewPane.qml" \
  "$ROOT/PluginControlBar.qml" \
  "$ROOT/lib/shortcuts/HyprlandBinding.qml"
```

- [ ] **Step 6: Verify the QML loads and the model tests still pass**

Run: `tests/qml.test.sh`
Expected: PASS.

Run: `node tests/model.test.js`
Expected: PASS.

- [ ] **Step 7: Look at it**

Run:

```bash
bin/plugin-control stop || true
bin/plugin-control start
omarchy-shell shell toggle io.github.ilyazar.plugin-control '{}'
```

Expected: typing `plug-install:` shows the list with a picture pane on the
right that follows the selection; plugins without a screenshot show
`No screenshot` and the window does not change width as the selection moves.

- [ ] **Step 8: Commit**

```bash
git add PreviewPane.qml PluginControl.qml
git commit -m "feat: show a preview pane beside the results"
```

---

### Task 10: The enlarged view

**Files:**
- Create: `PreviewLightbox.qml`
- Modify: `PluginControl.qml` (key handling near line 560, the `PanelWindow` body, `PreviewPane` signal wiring, `footerModel` at line 310, `activateFooter` at line 334)
- Test: `tests/qml.test.sh` (lint list and footer assertions)

**Interfaces:**
- Consumes: `PreviewPane.imageActivated` from Task 9; `service.requestPreview` from Task 8.
- Produces: on `root` — `property bool lightboxOpen`, `function toggleLightbox()`, `function closeLightbox()`.

- [ ] **Step 1: Create `PreviewLightbox.qml`**

```qml
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property var record: null
  property var service: null
  property bool opened: false
  property color scrim: Color.menu.scrim
  property color foreground: Color.menu.text
  property string imagePath: ""

  readonly property string fullUrl: record && record.previewImage
    ? String(record.previewImage) : ""
  readonly property bool available: fullUrl !== ""

  signal dismissed()

  visible: opened && available

  function refresh() {
    imagePath = service && fullUrl ? service.previewPathFor(fullUrl) : ""
    if (!imagePath && fullUrl && opened) service.requestPreview(fullUrl)
  }

  onOpenedChanged: refresh()
  onFullUrlChanged: refresh()

  Connections {
    target: root.service
    function onPreviewReady(url, path) {
      if (url === root.fullUrl) root.imagePath = path
    }
  }

  Rectangle {
    anchors.fill: parent
    color: root.scrim
    opacity: 0.92

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismissed()
    }
  }

  Image {
    anchors.centerIn: parent
    width: Math.min(parent.width * 0.9, implicitWidth)
    height: Math.min(parent.height * 0.9, implicitHeight)
    source: root.imagePath ? "file://" + root.imagePath : ""
    visible: root.imagePath !== "" && status === Image.Ready
    asynchronous: true
    fillMode: Image.PreserveAspectFit
  }

  Text {
    anchors.centerIn: parent
    visible: root.imagePath === ""
    text: "Loading…"
    color: root.foreground
    opacity: 0.65
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.body
  }
}
```

- [ ] **Step 2: Add the state and functions to `PluginControl.qml`**

Add beside the other mutable properties:

```qml
  property bool lightboxOpen: false
```

and beside the other functions:

```qml
  function closeLightbox() {
    lightboxOpen = false
    queryInput.forceActiveFocus()
  }

  function toggleLightbox() {
    if (lightboxOpen) {
      closeLightbox()
      return
    }
    var record = selectedRecord
    if (!record || !String(record.previewImage || "")) return
    lightboxOpen = true
  }
```

- [ ] **Step 3: Add the overlay to the panel**

Inside `PanelWindow`, after the `BorderSurface { id: card ... }` block:

```qml
    PreviewLightbox {
      id: previewLightbox
      anchors.fill: parent
      z: 30
      opened: root.lightboxOpen
      record: root.selectedRecord
      service: root.service
      scrim: root.scrim
      foreground: root.foreground
      onDismissed: root.closeLightbox()
    }
```

- [ ] **Step 4: Bind the keys and the click**

In `handleKey`, make Escape close the overlay first. Change

```qml
      } else if (event.key === Qt.Key_Escape) {
```

so the branch immediately above it reads:

```qml
      } else if (event.key === Qt.Key_Escape && root.lightboxOpen) {
        root.closeLightbox()
      } else if (event.key === Qt.Key_Escape) {
```

and add a branch beside the other control shortcuts, after the `Ctrl+I` case:

```qml
      } else if (isControlShortcut(event, Qt.Key_E)) {
        root.toggleLightbox()
```

Then wire the pane's click, on the `PreviewPane` element added in Task 9:

```qml
              onImageActivated: root.toggleLightbox()
```

- [ ] **Step 5: Add the footer entry and make the footer dispatch by key**

`footerModel` (line 310) feeds the clickable shortcut row, and
`activateFooter` currently dispatches on the array index with `else
openSettings()` as a catch-all — inserting an entry would silently misroute
every click after it. Replace both. `footerModel` becomes:

```qml
  readonly property var footerModel: {
    var entries = [{ keyLabel: "[Ctrl+I]", label: "Info" }]
    if (previewPaneVisible)
      entries.push({ keyLabel: "[Ctrl+E]", label: "Enlarge" })
    entries.push({ keyLabel: "[Ctrl+W]", label: root.marketplaceShortcutLabel })
    entries.push({ keyLabel: "[Ctrl+G]", label: "GitHub source" })
    entries.push({ keyLabel: "[Ctrl+R]", label: "Refresh" })
    entries.push({ keyLabel: "[Ctrl+S]", label: "Settings" })
    return entries
  }
```

The literal spellings must stay exactly as written — `tests/qml.test.sh`
asserts several of them with a fixed-string search. `activateFooter` becomes:

```qml
  function activateFooter(index) {
    if (index < 0 || index >= footerModel.length) return false
    var key = String(footerModel[index].keyLabel || "")
    if (key === "[Ctrl+I]") openSelectedInfo()
    else if (key === "[Ctrl+E]") toggleLightbox()
    else if (key === "[Ctrl+W]") openMarketplaceShortcut()
    else if (key === "[Ctrl+G]") openGithubShortcut()
    else if (key === "[Ctrl+R]") requestCatalogRefresh()
    else if (key === "[Ctrl+S]") openSettings()
    else return false
    return true
  }
```

The entry appears only while the pane is visible, so the narrow palette keeps
its current five chips.

- [ ] **Step 6: Extend the QML checks**

In `tests/qml.test.sh`, add `"$ROOT/PreviewLightbox.qml"` to the `qmllint`
invocation alongside `"$ROOT/PreviewPane.qml"`, and add two assertions beside
the existing `keyLabel` ones:

```bash
rg -Fq '{ keyLabel: "[Ctrl+E]", label: "Enlarge" }' "$ROOT/PluginControl.qml"
rg -q 'Qt.Key_E' "$ROOT/PluginControl.qml"
```

- [ ] **Step 7: Verify and look at it**

Run: `tests/qml.test.sh`
Expected: PASS.

Run:

```bash
bin/plugin-control stop || true
bin/plugin-control start
omarchy-shell shell toggle io.github.ilyazar.plugin-control '{}'
```

Expected: `Ctrl+E` on a plugin with a screenshot opens the large image;
`Escape` returns to the same row with the query intact; `Ctrl+E` on a plugin
without a screenshot does nothing; `Enter` still opens the install dialog;
clicking `[Ctrl+E] Enlarge` in the footer does the same as the key.

- [ ] **Step 8: Commit**

```bash
git add PreviewLightbox.qml PluginControl.qml
git commit -m "feat: add an enlarged preview on Ctrl+E"
```

---

### Task 11: Documentation and the full sweep

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: everything above.
- Produces: no code interfaces.

- [ ] **Step 1: Document the pane**

In `README.md`, add a row to the key table after the `Ctrl+I` row:

```markdown
| `Ctrl+E`                                   | Enlarge the screenshot of the selection     |
```

Add a short section after the `Use` section:

```markdown
## Screenshots

Marketplace listings carry their own screenshots, so the palette shows one for
the selected plugin beside the results. Pictures are fetched only from the
website of a channel you have enabled, cached under
`~/.cache/omarchy/plugin-control/previews/`, and never downloaded by the
window itself. Plugins with no screenshot show `No screenshot`, and built-in
plugins have none. `Ctrl+E` or a click enlarges the picture; `Escape` closes it.

Hide the pane, and stop all picture downloads, with `preview-pane-hidden`.
```

Add the setting to the YAML block in the `Settings` section:

```yaml
settings:
  tray-icon-hidden: false
  preview-pane-hidden: false
```

- [ ] **Step 2: Run every test**

Run each stage of `tests/all.sh` directly, because `tests/all.sh` aborts partway
on a `_shared/` directory that exists only in the upstream author's
multi-plugin checkout:

```bash
bash -n bin/plugin-control scripts/open-settings.sh tests/*.sh
ruby -c lib/channel_config.rb
node tests/model.test.js
ruby tests/channel_config.test.rb
tests/catalog.test.sh
tests/preview.test.sh
tests/issues.test.sh
tests/backend.test.sh
tests/helpers.test.sh
tests/qml.test.sh
```

Expected: every line reports `ok - …`.

- [ ] **Step 3: Validate the plugin**

Run: `omarchy plugin validate .`
Expected: valid.

- [ ] **Step 4: Lint the shell**

Run: `shellcheck bin/plugin-control scripts/*.sh tests/*.sh`
Expected: clean. `shellcheck` is not installed on this machine — install it
first (`sudo pacman -S --needed shellcheck`) or state explicitly in the final
report that this step was skipped. Do not claim it passed.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: describe the preview pane and its setting"
```

---

## Self-Review

**Spec coverage**

| Spec section | Task |
| --- | --- |
| Layer 1 — catalog fields, validation, resolution | 1 |
| Layer 1 — `normalize_catalog` sixth argument, `website_url` | 2 |
| Layer 2 — host allowlist, scheme, cache path | 3 |
| Layer 2 — download, signature check, atomic write | 4 |
| Layer 2 — eviction, concurrency lock | 5 |
| Layer 3 — `CatalogModel.js` passthrough | 7 |
| Layer 3 — `Service.qml` queue, debounce, pre-warm | 8 (queue), 9 (debounce and pre-warm) |
| Layer 4 — pane layout, widths, empty state, metadata | 9 |
| Layer 5 — enlarged view, `Ctrl+E`, Escape | 10 |
| Layer 6 — `preview-pane-hidden` | 6 (config), 8 (service), 9 (visibility) |
| Testing | 1, 2, 3, 4, 5, 6, 7, and the sweep in 11 |
| Documentation | 11 |

**Deviations from the spec, deliberate**

- The subcommand takes the source root as its first argument
  (`preview <root> <url>`), because the host allowlist reads the channel
  configuration through `load_config`.
- The debounce timer lives in `PreviewPane.qml` rather than `PluginControl.qml`;
  the pane already tracks the selected record, so no extra wiring is needed.
  The pre-warm loop stays in `PluginControl.qml`, which owns `filteredRecords`.
- `license` and `repositoryUpdatedAt` are added to `row_valid`, matching how
  every other optional string is treated. Preview paths stay out of it.
- The spec did not mention the footer. `Ctrl+E` is added to the clickable
  shortcut row so it is discoverable, which forces `activateFooter` to dispatch
  on the key label rather than the array index — the current index dispatch
  would misroute every click after an inserted entry. The chip appears only
  while the pane is visible, so the narrow palette is unchanged.

**Two traps this plan works around**

- `tests/qml.test.sh` lints a hard-coded list of QML files. New files must be
  added to it or they are never checked (Tasks 9 and 10).
- `applyConfigStatus` in `Service.qml` returns early when `tray-icon-hidden` is
  missing, so `preview-pane-hidden` must be read before that return (Task 8).
