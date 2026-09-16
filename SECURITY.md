# Security Policy

## Reporting a vulnerability

Email **liberato@aguilabs.com** with details and reproduction steps. Please do not open
a public issue for security reports.

## What this client does

`tmux-ticker` is **read-only**. It makes two kinds of HTTPS request to the configured
`@ticker-api` origin:

- `GET /api/slot` — fetch the current message (text + style flags),
- `POST /api/beat` — an anonymous presence ping.

The returned message is rendered as **inert text** — it is parsed with `jq` and passed to
`printf` strictly as an *argument*, never as a format string and never evaluated by the
shell. The client executes nothing the server sends, writes no files outside
`~/.config/tmux-ticker`, and stores no personal data beyond a server-issued token (see
below).

- **Presence identity is server-issued.** The auth-less tmux client cannot name the
  row it writes: `/api/beat` and `/api/event` derive the presence key from an
  HMAC-signed token the server minted, so a caller can neither forge an id nor rotate
  one to reset its own rate limit.
