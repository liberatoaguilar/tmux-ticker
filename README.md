# tmux-ticker

Delayed stock quotes in your tmux status ribbon — every quote labeled with its delay.

A one-row scrolling ticker pinned to the top of every tmux window. It polls a hosted
feed and rotates delayed market quotes across the top of your terminal; between the
quotes it renders a single global message slot (bold, italic, color, rainbow), and
shows a house message when the slot is idle.

The client is **read-only and inert**: it fetches quotes and the current message over
HTTPS and draws them as plain colored text. It never evaluates anything the server sends.

![tmux-ticker scrolling across the top of a terminal window](docs/marquee.png)

## Install

**[TPM](https://github.com/tmux-plugins/tpm)** — add to `~/.tmux.conf`, then press `prefix + I`:

```tmux
set -g @plugin 'liberatoaguilar/tmux-ticker'
```

**One-liner** (no TPM):

```bash
curl -fsSL https://ticker.aguilabs.com/install.sh | bash
```

Then add the printed line to `~/.tmux.conf` and reload:

```tmux
run-shell ~/.config/tmux-ticker/ticker.tmux
```

The installer fetches a pinned release tag (a `v*` tarball published with the first
release), never `main`.

## Requirements

`tmux`, `bash`, `curl`, and `jq` on your `PATH` (standard on macOS/Linux dev boxes).
Without `jq` the ticker still runs but shows a static fallback message instead of the
live feed.

## Configuration

All options are set in `~/.tmux.conf` with `set -g`:

| Option | Default | Meaning |
| --- | --- | --- |
| `@ticker-api` | `https://ticker.aguilabs.com` | API origin the client polls |
| `@ticker-toggle-key` | `a` | toggle key, used as `prefix + <key>` |
| `@ticker-position` | `top` | `top` to enable, `off` to disable registration entirely |
| `@ticker-height` | `1` | ticker height in rows |
| `@ticker-poll-s` | `0.12` | scroll-frame interval (seconds) |
| `@ticker-fetch-s` | `2` | re-fetch interval (seconds) |
| `@ticker-emoji` | `auto` | `auto`\|`on`\|`off` — emoji glyphs in quote items. `off` is plain ASCII; `auto`/`on` use the emoji variants |
| `@ticker-markets` | `on` | `on`\|`off` — rotate the markets carousel between slot messages. `off` shows the slot message only |

## Market data

Quotes shown by the ticker are **delayed** (typically 15+ minutes) and each is labeled
with its delay (or `mkt closed` outside trading hours). They are provided for
informational purposes only and are **not investment advice**.

## Keybinding

`prefix + a` toggles the ticker across **all** windows (creates/kills the panes).

## Running alongside other plugins

`tmux-ticker` owns only the **top row** of each window and registers its hooks with
`set-hook -ga` (append), so it coexists with other tmux plugins that own a different
pane region — load order doesn't matter and it won't clobber their hooks.

## Uninstall

```bash
~/.config/tmux-ticker/scripts/uninstall.sh
```

This kills every ticker pane and disables the plugin without disturbing other plugins'
shared hooks. Then remove the `@plugin` / `run-shell` line and reload tmux.

## License

[MIT](./LICENSE) © 2026 Liberato Aguilar Business Software LLC
