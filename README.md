# Plugin Control

Think of Sublime Text's classic Package Control or the VS Code Command Palette,
but for Omarchy Quattro plugins.

Press Ctrl+P (or click the tray icon), type a few letters to fuzzy-search, and
press Enter to install or remove a plugin.

![Plugin Control command palette](preview.png)

Plugin Control keeps the full [@HANCORE-linux](https://github.com/HANCORE-linux)
[community marketplace](https://omarchyplugins.com/) and local plugin state in a
small cache, then filters it in process on every keypress.

## Install

```bash
omarchy plugin add https://github.com/ilyaZar/plugin-control.git --enable
```

Plugin manifests cannot add global bindings. For a keyboard-only path, add this
optional binding to your repo-managed or user-owned `bindings.lua`:

```lua
o.bind(
  "CTRL + P",
  "Plugin Control",
  "omarchy-shell shell toggle io.github.ilyazar.plugin-control '{}'"
)
```

Bare Ctrl+P is quick, but it replaces the usual application shortcut while the
binding is active. Change the first string if that disrupts your setup.

## Use

Start typing to search plugin names, IDs, descriptions, authors, and tags. Enter
opens the selected plugin's available action; Ctrl+I shows details without
changing anything.

Enter toggles anything the shell reports as present and switchable, whether it
ships with Omarchy or you installed it yourself. Removal is destructive, so it
stays behind `plug-remove:`. Bars are neither: they are replaced rather than
switched off, and the shell marks them as such.

Filter with the chips under the search field, or type the command directly —
they are the same thing, since a chip writes its command into the field:

- `plug-install:` shows available installable plugins
- `plug-remove:` shows removable local plugins
- `plug-builtin:` shows the plugins that ship with Omarchy
- `plug-mine:` shows the plugins you installed or cloned yourself
- `plug-disabled:` shows everything switched off, whatever its origin
- `plug-type: <kind>` filters by kind — bar widget, panel, service, overlay

`plug-type:` takes a value, so its chip steps through the kinds and clears on
the step past the last. Either spelling works: `bar widget` or `bar-widget`.

### Counts and sorting

Marketplace rows show their star and heart counts on the right: `★ 274  ♥ 7`.
Built-in plugins and your own checkouts are not marketplace listings, so they
show no counts rather than a row of zeroes.

The `Sort` chip sets the order, and `Ctrl+O` steps it forward. Unlike the
filters above, the order is not a command written into the search field: it is
its own setting, so it survives switching filters and typing a query. "Mine,
most starred" is a reasonable thing to ask for.

| Order             | Ranks by                                          |
| ----------------- | ------------------------------------------------- |
| `Best match`      | Search relevance — the default, and how it behaved before |
| `Recently added`  | When the marketplace listed the plugin            |
| `Recent activity` | When its repository last changed                  |
| `Most starred`    | GitHub stars                                      |
| `Most viewed`     | Marketplace page views                            |
| `Most copied`     | Marketplace install-command copies                |
| `Most hearts`     | Marketplace hearts                                |
| `A–Z`             | Name                                              |

Stars arrive with the catalog. Views, copies and hearts come from the
marketplace's separate counter service, named by `engagement_url` in the channel
configuration; they are cached alongside the catalog, so the last known numbers
survive an outage. When that service has never been reached, the chip steps over
those three orders instead of offering a ranking it cannot honour. Delete the
`engagement_url` line to stop contacting it — stars and every other order keep
working.

Commands are not pinned. Type `install`, `remove`, `plug-in`, or `plg-in` to
bring one forward, then press Tab or Enter to complete it. Search restarts after
the colon. Backspace edits a plugin name normally; at an empty completed prefix,
one press removes the trailing space and the next clears the command.

Useful keys:

| Keys                                       | Action                                      |
| ------------------------------------------ | ------------------------------------------- |
| `Ctrl+P` or `Escape`                       | Close the palette from the plugin list      |
| `Up`, `Down`, `Page Up`, `Page Down`       | Move the selection                          |
| `Home` or `End`                            | Jump to the first or last result            |
| `Enter`                                    | Complete a command or confirm an action     |
| `Tab`                                      | Complete the selected command               |
| `Ctrl+Backspace`                           | Remove the previous word                    |
| `Ctrl+U`                                   | Clear the query                             |
| `Ctrl+O`                                   | Step the sort order forward                 |
| `Ctrl+R`                                   | Refresh the catalog                         |
| `Ctrl+I`                                   | Show details for the selected plugin        |
| `Ctrl+E`                                   | Enlarge the screenshot of the selection     |
| `Ctrl+W`                                   | Open the plugin website                     |
| `Ctrl+G`                                   | Open the plugin source repository           |
| `Ctrl+S`                                   | Open settings; `Escape` returns to the list |

## Screenshots

Marketplace listings carry their own screenshots, so the palette shows one for
the selected plugin beside the results. The pane only appears when the
palette has room for it; on a narrow screen it does not appear at all.
Plugins with no screenshot show `No screenshot`, and Omarchy's built-in
plugins have none.

Marketplace screenshots are WebP files. A Qt install without WebP support
shows `Can't display image` instead of the picture; on Arch, the
`qt6-imageformats` package adds the missing decoder.

Pictures are fetched only from the website of a channel you have enabled.
Redirects are refused outright, so a picture served via a redirect will not
load. Downloads are cached under `~/.cache/omarchy/plugin-control/previews/`,
capped at 400 files with the oldest evicted first.

`Ctrl+E` or a click on the picture enlarges it; `Escape` closes it. While the
enlarged view is open, the palette ignores every other key except `Ctrl+P`,
which closes the view and dismisses the palette in one press.

Hide the pane, and stop all picture downloads, with `preview-pane-hidden`.

## Install behavior

Installs run in the background by default and report their result in the palette
and a notification. The confirmation's `Run in Omarchy terminal` switch streams
native prompts instead. Both paths use the confirmed catalog snapshot.

Plugins run unsandboxed inside the shell. Marketplace validation is not a
security audit.

## Start and stop

The lifecycle helper lives inside the installed plugin:

```bash
~/.config/omarchy/plugins/io.github.ilyazar.plugin-control/bin/plugin-control start
~/.config/omarchy/plugins/io.github.ilyazar.plugin-control/bin/plugin-control start --tray-hidden
~/.config/omarchy/plugins/io.github.ilyazar.plugin-control/bin/plugin-control stop
```

`start` uses the configured tray default. `--tray-hidden` and `--tray-visible`
override it; `stop` disables the plugin.

## Settings

Ctrl+S opens Plugin settings, Keybindings, and Cancel / Back. Use `j`/`k`,
arrows, mouse, or Enter; Escape returns to the plugin list.

```text
~/.config/omarchy/plugin-control/channels.yaml
~/.config/hypr/bindings.lua
```

```yaml
settings:
  tray-icon-hidden: false
  preview-pane-hidden: false
```

Plugin Control never rewrites the user-owned Ctrl+P binding. Its other shortcuts
work only while the palette is focused. Saving a valid tray setting updates the
live bar; a CLI flag overrides it until the YAML is saved again.

Settings use strict schema 2. Invalid edits keep the last valid schema-2 file;
version 1 is not migrated.

An existing `channels.yaml` is never rewritten, only created when absent. A
configuration written before the counter service existed therefore has no
`engagement_url`, and the view, copy and heart orders stay unavailable until the
line is added by hand:

```yaml
channels:
  - id: marketplace
    catalog_url: https://omarchyplugins.com/catalog.json
    website_url: https://omarchyplugins.com/
    engagement_url: https://api.omarchyplugins.com/v1/stats
```

## Dependencies

- Omarchy Quattro and its shell
- Bash, curl, Git, and jq
- Ruby with Psych
- util-linux (`flock` and `setsid`)
- GNU coreutils (`timeout`)
- `omarchy-launch-terminal` for terminal installs

Plugin Control installs no packages and requests no elevated privileges.

## Remove

Select Plugin Control under `plug-remove:` or right-click its bar icon and
choose Remove Plugin Control. Both paths open the same No/Yes warning. The
native command is:

```bash
omarchy plugin remove io.github.ilyazar.plugin-control
```

Remove the optional Ctrl+P binding separately. Native removal keeps:

- settings: `~/.config/omarchy/plugin-control/`
- cache: `~/.cache/omarchy/plugin-control/`
- action history: `~/.local/state/omarchy/plugin-control/`

## Development

```bash
tests/all.sh
shellcheck bin/plugin-control scripts/*.sh tests/*.sh
omarchy plugin validate .
```

## License

MIT. See [LICENSE](LICENSE).
