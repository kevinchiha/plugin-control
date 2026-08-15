# Preview pane design

Date: 2026-08-15
Status: approved, not implemented
Branch: `preview-pane`

## Goal

Show a screenshot of the selected plugin inside the command palette, so
browsing the marketplace feels like browsing a storefront instead of reading a
list of names. The idea comes from Okomart (`brianblakely/omarchy-plugins`),
which shows screenshots and metadata for every catalogued plugin.

Okomart sources its images by cloning every catalogued repository into a local
mirror and scanning each working tree for image files. That works for its
14-entry `plugins.txt`; it does not scale to the 234-entry marketplace catalog
this plugin already consumes. This design takes the idea and drops the
mechanism.

## What the marketplace already provides

`https://omarchyplugins.com/catalog.json` — already downloaded on the existing
30-minute refresh — carries per-plugin preview fields that
`lib/catalog.jq` currently discards:

| Field | Example | Notes |
| --- | --- | --- |
| `previewThumbnail` | `assets/img/plugins/9-…-card.webp` | site-relative, 720×405 |
| `previewThumbnailWidth` / `Height` | `720` / `405` | integers |
| `previewImage` | `assets/img/plugins/9-…-detail.webp` | site-relative, 1600×900 |
| `previewWidth` / `previewHeight` | `1600` / `900` | integers |
| `stars`, `license`, `category`, `repositoryUpdatedAt` | `13`, `MIT`, `Desktop`, ISO 8601 | also discarded today |

Coverage measured on 2026-08-15: 161 of 234 catalog rows carry a preview, and
155 of the 186 installable rows do. No new remote source is introduced by this
work; the images live on the same host as the catalog that is already trusted
to describe what gets installed.

## Non-goals

- Cloning plugin repositories, or any new GitHub API traffic.
- Screenshots for locally installed, self-cloned, or Omarchy built-in plugins.
  They would need on-disk image scanning; explicitly declined.
- Coloured initials tiles as a placeholder for plugins with no screenshot;
  explicitly declined.
- Offering this work upstream to `ilyaZar/plugin-control`.

## Layer 1 — Catalog

### `lib/catalog.jq`

`normalized_record` builds a whitelist of fields. Add to it:

```
previewThumbnail, previewThumbnailWidth, previewThumbnailHeight,
previewImage, previewWidth, previewHeight,
stars, license, category, repositoryUpdatedAt
```

Preview paths are validated by a new `valid_preview_path` definition and
resolved against a base URL supplied by the caller. Validation rules, applied
to `previewThumbnail` and `previewImage` independently:

- must be a string of at most 512 characters with no control characters;
- must match `^[A-Za-z0-9][A-Za-z0-9._/-]*$` — this excludes a leading `/`,
  any scheme, any host, backslashes, query strings and fragments;
- must not contain `..`;
- must end in `.webp`, `.png`, `.jpg`, `.jpeg` or `.gif` (case-insensitive).

A path that fails any rule becomes `""`. **It does not reject the row** — a bad
picture must never hide a plugin from the palette. Dimensions that are not
positive integers under 10000 become `0`; `stars` follows the same rule.
`license` and `category` reuse `safe_string(80)`, `repositoryUpdatedAt` reuses
`safe_string(64)`.

Resolution: the record stores the absolute URL, `$previewBase + "/" + path`,
and only when `$previewBase` matches `^https://[A-Za-z0-9.-]+(/[A-Za-z0-9._~/-]*)?$`
with any trailing slash stripped. With no usable base, both preview fields are
`""`.

### `bin/plugin-control`

`normalize_catalog` gains a sixth parameter, the channel's `website_url`, and
passes it to jq as `--arg previewBase`. `refresh_catalog_channel` already reads
the channel record that carries `website_url`, so the value is available at the
call site. Channels with no website (for example `github-submissions`) pass the
empty string and therefore produce no previews.

The bootstrap catalog (`bootstrap/catalog.json`, Omarchy built-ins) is
unaffected and carries no preview fields.

## Layer 2 — Image fetching

QML never performs network access. A new helper subcommand does, matching how
every other remote fetch in this plugin works.

### `plugin-control preview <url>`

Prints one JSON object on stdout:

```json
{"ok":true,"path":"/home/…/previews/<sha256>.webp","cached":true}
{"ok":false,"error":"preview host is not an enabled channel"}
```

Rules:

1. **Host allowlist.** The URL's origin must equal the `website_url` origin of
   an enabled channel in the user's `channels.yaml`. This keeps the helper from
   being turned into a general-purpose downloader by the QML layer.
2. **Scheme.** `https` only, enforced by both the allowlist check and
   `--proto '=https' --proto-redir '=https'`.
3. **Cache path.** `$CACHE_ROOT/previews/<sha256 of url><ext>`, where `<ext>` is
   taken from the validated URL suffix and `$CACHE_ROOT` is the existing
   `~/.cache/omarchy/plugin-control`. A cache hit returns immediately with
   `"cached":true` and touches the file's mtime.
4. **Download.** `curl --fail --silent --show-error --location --proto '=https'
   --proto-redir '=https' --connect-timeout 5 --max-time 20 --max-filesize
   4194304 --max-redirs 3 --user-agent 'plugin-control/…'`, writing to a
   temporary file in the same directory, then renamed into place — the same
   temp-then-rename pattern `atomic_write_stream` and `atomic_write_text`
   already use for text payloads. Binary content goes through a plain `mv`
   rather than those helpers.
5. **Content check.** Before the rename, the temporary file must be non-empty
   and start with a recognised image signature (`RIFF….WEBP`, PNG, JPEG or
   GIF). Anything else is discarded and reported as an error.
6. **Concurrency.** A per-file `flock` under `$RUNTIME_ROOT` so two rapid
   selections of the same plugin cannot both download it.
7. **Eviction.** After a successful download, if the previews directory holds
   more than 400 files, delete the oldest by mtime down to 400. Sizes are small
   (720×405 WebP), so this bounds the directory in the low tens of megabytes.

Failures are never fatal to the palette; the pane simply shows no image.

## Layer 3 — QML wiring

### `CatalogModel.js`

`prepareRecords` passes the new fields through onto each record, defaulting
missing values to `""` / `0`, exactly as it does for existing optional fields.

### `Service.qml`

- `property var previewPaths: ({})` — resolved URL → local file path, plus a
  set of URLs already attempted and failed, so a broken image is asked for once
  per shell session.
- `function requestPreview(url)` — no-op when the URL is empty, already
  resolved, already failed, or already queued. Otherwise it appends to a queue.
- One `Process` handles the queue serially, running
  `[helperPath, "preview", url]`, collecting stdout, updating `previewPaths`,
  emitting `previewReady(url, path)`, then starting the next queued URL.
  Serial execution matches the single-process-per-purpose pattern used by
  `cachedProcess`, `refreshProcess` and `statusProcess`, and keeps a fast scroll
  from spawning dozens of curls.
- Queue cap of 12 pending URLs; the newest request wins when full, because the
  user's current selection matters more than a row they have scrolled past.

### `PluginControl.qml`

Selection handling: a 150 ms `Timer` restarted on every selection change calls
`service.requestPreview(record.previewThumbnail)`. Holding an arrow key
therefore fetches only what the selection lands on.

Pre-warm: on a filter change, and after `applySnapshot`, request thumbnails for
the visible rows only (currently at most 6, plus 2 either side), so ordinary
scrolling finds the file already on disk.

## Layer 4 — Layout

Current geometry: a centred card, `cardWidth` capped at `Style.space(720)`,
`cardHeight` capped at `Style.space(500)`, at most 6 result rows.

- `previewPaneVisible` is true when all of: the settings menu is closed, the
  action dialog is closed, `previewPaneHidden` is false, the selected record is
  a real plugin (not a command completion), and `panel.width >= Style.space(900)`.
- When visible, `cardWidth` becomes `Math.min(Style.space(1080), panel.width -
  Style.gapsOut * 2)`. The results list keeps its present width; the pane takes
  the remainder. When hidden, the existing 720 cap applies unchanged.
- The pane sits beside the results list only. The search field, filter chips and
  footer continue to span the full card width.
- The width change is animated with the existing animation guard
  (`animationsEnabled`, sourced from `hyprctl`), so it does not snap.

Pane contents, top to bottom:

1. A 16:9 image box, `fillMode: Image.PreserveAspectFit`, `asynchronous: true`,
   source `file://` + the resolved cache path. While the fetch is in flight the
   box holds its size and shows nothing.
2. When the record has no `previewThumbnail`: the same box, holding the same
   size, with a muted `No screenshot` label. The pane keeps its width so the
   window does not jump sideways as the selection moves past such rows.
3. Name and version; author; kind.
4. The metadata row recovered from the catalog: `★ stars`, licence, category,
   and `Updated <n> days ago` derived from `repositoryUpdatedAt`.

## Layer 5 — Enlarged view

- Opened by clicking the image, or by `Ctrl+E` from the palette. `Enter` is not
  reused: in the palette it installs, removes, enables or disables, and
  overloading it risks an unintended action.
- `Ctrl+E` is free; `Ctrl+P`, `Ctrl+I`, `Ctrl+W`, `Ctrl+G`, `Ctrl+R`, `Ctrl+S`,
  `Ctrl+U` and `Ctrl+Backspace` are taken. Unmodified letters are unavailable
  because the search field holds the focus.
- The overlay covers the panel above the card, dims the background with the
  existing `scrim` colour, and shows `previewImage` (1600×900) scaled to at most
  90% of the panel in each axis. It requests the full-size image through the
  same `preview` subcommand on open, showing `Loading…` until the file arrives.
- `Escape`, a click outside the image, or `Ctrl+E` again closes it and returns
  focus to the same row with no state changed. `Ctrl+E` does nothing when the
  record has no `previewImage`.

## Layer 6 — Settings

`channels.yaml` is validated under a strict schema 2 that rejects unknown keys
and falls back to the last valid file, so a new key must be added deliberately.

```yaml
settings:
  tray-icon-hidden: false
  preview-pane-hidden: false
```

- `scripts/channel_config.rb` accepts `preview-pane-hidden` as an optional
  boolean defaulting to `false`, keeping every other strictness rule.
- `Service.qml` exposes `property bool previewPaneHidden: false`, set from the
  `config-status` payload. `applyConfigStatus` currently returns early when
  `tray-icon-hidden` is missing or not boolean; the preview setting must be read
  before that early return so one missing key cannot suppress the other.
- No new UI: `Ctrl+S` already opens the YAML through `scripts/open-settings.sh`,
  which remains the single place these settings are edited.
- With the pane hidden, no preview URLs are requested at all.

## Testing

New coverage:

- `tests/catalog.test.sh` — a fixture catalog exercising a valid preview path,
  an absolute URL, a `../` traversal, a control character, a wrong extension,
  an over-length path, and an out-of-range dimension. Each bad case must yield
  `""` or `0` **with the row still present**. One case with an empty
  `previewBase` must yield empty previews.
- `tests/backend.test.sh` — the `preview` subcommand against a stubbed `curl` on
  `MOCK_BIN` (the harness already puts a mock bin first on `PATH`): a fresh
  download, a cache hit that does not invoke curl, a host outside the enabled
  channels, a non-image body rejected by the signature check, and eviction once
  the directory exceeds its cap.
- `tests/channel_config.test.rb` — `preview-pane-hidden` accepted as a boolean,
  rejected as a string, defaulted when absent, and an unknown key still
  rejected.
- `tests/model.test.js` — the new fields survive `prepareRecords`.

Two known local constraints, from prior work in this checkout:

- `tests/all.sh` aborts partway on a `_shared/` directory that exists only in
  the original author's multi-plugin checkout, so the Quickshell stage
  (`tests/qml.test.sh`) is run separately.
- `shellcheck` is not installed on this machine. Either install it before the
  final check or record explicitly that the shell lint step was skipped.

## Documentation

`README.md` gains: `Ctrl+E` in the key table, a short paragraph describing the
preview pane and where the images come from, and `preview-pane-hidden` in the
settings block.

## Risks and accepted trade-offs

| Risk | Decision |
| --- | --- |
| ~1 in 6 installable plugins, and every built-in, has no screenshot | Accepted. The pane holds its size and says `No screenshot`; the initials-tile fallback was declined. |
| The card widening from 720 to 1080 is a visible change to a familiar window | Accepted, animated, and reversible through `preview-pane-hidden`. |
| Image traffic to `omarchyplugins.com` while browsing | Same host as the catalog itself; lazy, cached on disk, and fully disabled by one setting. |
| A malicious catalog row pointing the fetcher at another host | Blocked by the host allowlist, the relative-path validation, and the image signature check. |
| Fork diverges further from upstream | Accepted; no upstream pull request is planned for this work. |
