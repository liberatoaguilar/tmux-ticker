# tmux-ticker

Delayed stock quotes in your tmux status ribbon — every quote labeled with its delay.

A one-row scrolling ticker pinned to the top of every tmux window. It rotates delayed
market quotes across the top of your terminal, fetched **directly by the plugin** — no
server required for quotes at all; between the quotes it renders a single global message
slot (bold, italic, color, rainbow) polled from a tmux-ticker server, and shows a house
message when the slot is idle.

Quotes need **no server at all**. The plugin polls [Finnhub](https://finnhub.io) directly
with **your own** key. Setup:

1. Sign up at [finnhub.io](https://finnhub.io) for a free API key.
2. Make `FINNHUB_API_KEY` visible to the **tmux server** — either:
   - `export FINNHUB_API_KEY=...` in your shell profile **before** starting tmux, or
   - at runtime: `tmux set-environment -g FINNHUB_API_KEY ...`, then respawn the ticker
     (toggle it off/on with `prefix + a`) so it picks up the key.

No key? The ticker still runs, showing only the message slot.

> [!IMPORTANT]
> Quotes are fetched **directly from your provider with your own key** — for your own
> personal/internal use, on your own terminals. The server (`@ticker-api`) is used only
> for the shared message slot, never for quotes. You are responsible for complying with
> your data provider's terms of service. This plugin uses **Finnhub only** — no Twelve
> Data (its free tier prohibits display).

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
| `@ticker-symbols` | `NVDA,MSFT,AMD,TSLA` | comma-separated symbols to fetch from Finnhub (max 12) |
| `@ticker-hero` | *(empty)* | symbol to pin first in the carousel, marked with a gold ★ |

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
