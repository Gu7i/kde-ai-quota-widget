# AI Quota KDE Widget

See your AI subscription quotas and manage your local Ollama models from the KDE Plasma panel. One tab per AI provider with live usage, plus an Ollama tab to load/unload models from memory — no browser, no dashboard.

![KDE Plasma 6](https://img.shields.io/badge/KDE_Plasma-6-blue)
![Python 3.11+](https://img.shields.io/badge/Python-3.11+-green)
![License: GPL v2](https://img.shields.io/badge/License-GPLv2-blue)

## Features

- **AI neural-network panel icon** in the plain theme color, so it sits in the icon row like every other tray icon — with a small amber/red badge once your 5-hour window crosses 70% / 90% **or Claude is having an incident**; dimmed when the daemon is offline
- **Tabs** separating providers, one per AI plus an Ollama tab, each with a health dot
- **Claude tab — live quota** (the same numbers `/usage` shows inside Claude Code):
  - The **first window is a hero readout** — the number you opened the widget for, not one row among many
  - Bars carry **70 / 90 threshold marks**, the same cut-offs that drive the color (teal → amber → red)
  - "reinicia en Xh Ym" reset hint plus an **"a este ritmo llegas al X%"** projection per window
  - Opus / Sonnet 7-day windows shown when the API reports them
  - Plan (`PRO`) and rate-limit tier as chips
- **Claude tab — service status** from [status.claude.com](https://status.claude.com), the thing quota numbers can't tell you: whether a failing request is your limit or their outage
  - One quiet line while everything is up (`● TODO OPERATIVO`); it only grows when something is wrong
  - Degraded components (Claude Code, API, claude.ai — plus anything else currently unhealthy), in Spanish
  - Open incidents with their latest update, clickable through to the incident page
- **Follows your Plasma theme** — the vintage palette ships in a light and a dark variant, picked from `Kirigami.Theme`, and every size derives from `Kirigami.Units` so it scales on HiDPI
- **Status bar** showing how stale the numbers are (`actualizado hace 6 s`) and whether the daemon is answering
- **Actualizar forces a real re-query** (`POST /refresh`) instead of re-reading the daemon's cache, and spins while it is in flight
- **Ollama tab — local models**:
  - Lists installed models with params, quantization and size on disk
  - **CARGAR / LIBERAR** button loads a model into RAM/VRAM (`keep_alive`) or evicts it — with an **EN RAM** badge for resident models
  - ★ mark a **preferred** model; the choice is persisted and readable by other apps
- **Instant feedback** — actions respond immediately (optimistic UI); confirmed by the next poll
- **Extensible provider architecture** — Codex, Gemini, etc. can be added by dropping one module in `daemon/providers/`
- Daemon runs as a systemd user service (starts at boot)
- Reads Claude's OAuth token from `~/.claude/.credentials.json` — read-only, never written, so it can't race Claude Code over single-use refresh tokens
- Rate-limit aware: backs off when Anthropic's usage endpoint throttles, and retries fast at boot when the network isn't up yet

## Providers

| Provider | Source | Data |
|---|---|---|
| Claude | `~/.claude/.credentials.json` + `api.anthropic.com/api/oauth/usage` | Live 5h / 7d utilization, resets, plan |
| Claude status | `status.claude.com/api/v2/summary.json` | Overall indicator, per-component state, open incidents |
| Ollama | `http://127.0.0.1:11434` (`/api/tags`, `/api/ps`, `/api/generate`) | Installed models, resident state, load/unload, preferred |

> Codex and Gemini are not included yet: their per-plan quota has no clean local endpoint. The daemon is built so they can be added later without a rewrite — see [Adding a provider](#adding-a-provider).

## Requirements

- KDE Plasma 6
- Python 3.11+ (standard library only — no extra pip packages)
- **Claude tab:** Claude Code installed and signed in at least once (so `~/.claude/.credentials.json` exists)
- **Ollama tab:** [Ollama](https://ollama.com) running locally (`ollama serve`)

## Installation

### 1. Clone the repo

```bash
git clone https://github.com/Gu7i/kde-ai-quota-widget.git
cd kde-ai-quota-widget
```

### 2. Run the installer

```bash
chmod +x install.sh
./install.sh
```

The installer will:
- Install and enable the `ai-quota-daemon` systemd user service
- Install the Plasma plasmoid
- Add the widget to your panel

No credentials to enter: Claude's token is read from `~/.claude`, and Ollama is auto-detected at `http://127.0.0.1:11434`.

### Uninstall

```bash
./uninstall.sh
```

Your Claude Code credentials (`~/.claude`) are never touched by uninstall.

### Manual setup (alternative)

```bash
# 1. Start the daemon
systemctl --user enable --now ai-quota-daemon.service

# 2. Install the plasmoid
cp -r plasmoid/ai-quota ~/.local/share/plasma/plasmoids/org.kde.ai-quota

# 3. Add to panel
#    Right-click panel → Add widgets → search "AI Quota"
```

## Architecture

```
┌─────────────────────────────────────┐
│  KDE Panel                          │
│  ┌──────────────────────────────┐   │
│  │  Plasmoid (QML)              │   │
│  │  polls GET /providers +      │   │
│  │  /ollama/models every 8s     │   │
│  │  POST /ollama/load|unload    │   │
│  └──────────────┬───────────────┘   │
└─────────────────┼───────────────────┘
                  │ HTTP localhost:7183
┌─────────────────┼───────────────────┐
│  ai-quota-daemon│(Python)           │
│  ┌──────────────┴───────────────┐   │
│  │  ai_quota_service.py         │   │
│  │  refreshes quotas every 180s │   │
│  │  providers/                  │   │
│  │    claude_provider.py ───────┼───┼──▶ api.anthropic.com/api/oauth/usage
│  │    ollama_provider.py ───────┼───┼──▶ localhost:11434 (Ollama)
│  └──────────────────────────────┘   │
└─────────────────────────────────────┘
```

## Daemon API

The daemon exposes a local REST API at `http://127.0.0.1:7183`:

| Method | Path | Description |
|---|---|---|
| GET | `/status` | Daemon health + list of active provider ids |
| GET | `/providers` | Quota snapshot for every provider (windows, meta) |
| GET | `/claude/status` | status.claude.com: overall indicator, components, open incidents |
| GET | `/ollama/models` | Installed models + which are resident in memory + preferred |
| POST | `/ollama/load` | Load a model into memory `{"name": "qwen3:8b"}` (async) |
| POST | `/ollama/unload` | Evict a model from memory `{"name": "qwen3:8b"}` |
| POST | `/ollama/preferred` | Mark a model as preferred `{"name": "qwen3:8b"}` |
| POST | `/refresh` | Force an immediate quota refresh |

Example `/providers` response:

```json
[
  {
    "id": "claude",
    "label": "Claude",
    "ok": true,
    "windows": [
      {"label": "5 horas", "utilization": 67.0, "resets_at": "2026-07-14T06:29:59+00:00", "window_seconds": 18000},
      {"label": "7 días",  "utilization": 26.0, "resets_at": "2026-07-16T04:59:59+00:00", "window_seconds": 604800}
    ],
    "meta": {"plan": "pro", "tier": "default_claude_ai", "extra_usage": false}
  }
]
```

Example `/claude/status` response:

```json
{
  "ok": true,
  "indicator": "minor",
  "severity": 1,
  "description": "Partially Degraded Service",
  "components": [
    {"name": "Claude Code", "status": "degraded_performance", "primary": true}
  ],
  "incidents": [
    {
      "name": "Degraded performance for multiple models",
      "status": "investigating",
      "impact": "minor",
      "url": "https://stspg.io/tcsfmtc03xgm",
      "body": "We are investigating elevated errors…"
    }
  ]
}
```

## How Claude quota works

The daemon reads the Claude Code OAuth token from `~/.claude/.credentials.json` and calls Anthropic's usage endpoint — the same data the `/usage` command shows inside Claude Code:

- `GET https://api.anthropic.com/api/oauth/usage` with `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20`, `anthropic-version: 2023-06-01`
- Returns `five_hour` / `seven_day` (and `seven_day_opus` / `seven_day_sonnet` when applicable) with `utilization` (%) and `resets_at`

**Token handling is read-only.** The file is read fresh on every poll, and never written. Claude Code owns the token and keeps it refreshed whenever it runs; if the access token is expired the widget shows `token caducado (abre Claude Code)` and recovers by itself on the next poll after Claude Code rotates it.

This is deliberate. An earlier version refreshed the token itself and wrote the rotated pair back. OAuth refresh tokens are single-use, so the daemon and Claude Code raced over the same file and whichever redeemed second was left holding a dead token — a 403 loop that only ended when the other process rewrote the credentials.

**Rate limiting:** the usage endpoint allows roughly 30 requests/hour, so the poll loop runs at 180s. On a 429 or 5xx the provider backs off (120s, doubling to a 900s cap, reset on the first success) and keeps serving the last good numbers rather than flapping to offline. The **Actualizar** button skips the backoff — a human pressing a button is not what causes throttling.

## How the status check works

`status.claude.com` is an Atlassian Statuspage, so it has a public JSON API. One call to `GET /api/v2/summary.json` returns the overall indicator, every component and the unresolved incidents — no credentials, no rate limit worth backing off from, and it is CDN-cached.

It is deliberately a **separate provider** from the quota one: the moment the usage endpoint starts failing is exactly the moment you want to know whether Anthropic is down, so an expired token or a 429 must never take the status readout with it.

`severity` maps Statuspage's indicator to a number (`none` 0, `minor` 1, `major` 2, `critical` 3) so the widget can color and compare it. If the fetch fails we keep the last snapshot but flag it `ok: false` — a failed check is not evidence of an outage, and never renders as one.

## Ollama model management

- Installed models come from `/api/tags`; resident models from `/api/ps`
- **Load** = `POST /api/generate {"model": ..., "prompt": "", "keep_alive": -1}` — runs in the background on the daemon and returns instantly, since a cold load of a multi-GB model can take a while. The **EN RAM** badge appears on the next poll (≤8 s)
- **Unload** = the same with `"keep_alive": 0`
- **Preferred** is stored in `~/.config/ai-quota-widget/config.json`:

```json
{
  "ollama_url": "http://127.0.0.1:11434",
  "ollama_preferred": "qwen3:8b"
}
```

Point `ollama_url` elsewhere in this file to track a remote Ollama host.

## Adding a provider

The daemon discovers quota providers in `daemon/ai_quota_service.py → build_providers()`. To add one (e.g. Codex or Gemini):

1. Create `daemon/providers/<name>_provider.py` with a class exposing `id`, `label`, and a `snapshot()` method returning:

   ```python
   {
       "id": "codex", "label": "Codex", "ok": True, "error": None,
       "windows": [{"label": "5 horas", "utilization": 40.0, "resets_at": "...",
                    "window_seconds": 18000}],
       "meta": {"plan": "plus"},
   }
   ```

   `window_seconds` (the length of the window) is optional: the API only says
   *when* a window resets, so the widget needs the span to work out how much of
   it is already spent. Omit it and the "at this pace" projection is simply
   hidden for that window; everything else still renders.

2. Register it in `build_providers()`:

   ```python
   _quota_providers = [ClaudeProvider(), CodexProvider()]
   ```

The plasmoid builds one tab per provider automatically — no QML changes needed.

## Useful commands

```bash
# Daemon
systemctl --user status ai-quota-daemon
systemctl --user restart ai-quota-daemon
journalctl --user -u ai-quota-daemon -f

# Test API
curl http://127.0.0.1:7183/providers    | python3 -m json.tool
curl http://127.0.0.1:7183/claude/status | python3 -m json.tool
curl http://127.0.0.1:7183/ollama/models | python3 -m json.tool
curl -X POST http://127.0.0.1:7183/ollama/load \
     -H "Content-Type: application/json" -d '{"name":"qwen3:8b"}'
```

## Files

```
daemon/
  ai_quota_service.py          HTTP daemon on :7183 + 180s quota refresh loop
  providers/
    __init__.py                Provider contract docs
    claude_provider.py         Reads ~/.claude token (read-only), live usage, backoff
    claude_status_provider.py  status.claude.com summary: indicator, components, incidents
    ollama_provider.py         /api/tags, /api/ps, load/unload, preferred
plasmoid/ai-quota/
  contents/ui/
    main.qml                   Plasmoid root: palette, polling, tabs, panel icon
    QuotaBar.qml               One utilization window — hero or compact row
    StatusStrip.qml            Claude service status: headline, components, incidents
    Gauge.qml                  Utilization track with the 70 / 90 threshold marks
    ModelRow.qml               One Ollama model row (load/unload/prefer)
  metadata.json                Plasma plugin descriptor
install.sh                     One-shot installer
uninstall.sh                   Clean removal
```

## Design

A sibling of [kde-ewelink-widget](https://github.com/Gu7i/kde-ewelink-widget): the same industrial monospace chrome and `LLM CORP™` mark, in an American-vintage palette — charcoal `#201F1D` / sand `#C1AB85` / teal / rust on dark, parchment `#F6F2E8` / `#6B5B41` on light. The variant is chosen from `Kirigami.Theme.backgroundColor`, so the popup no longer sits as a black slab in a light desktop.

Layout follows one rule: **the number you opened the widget for is the largest thing in the window.** The first quota window is a hero readout; the rest are compact rows under it. Bars shift teal → amber (≥70%) → rust (≥90%) and carry marks at those two thresholds, so a bar says how close you are without you having to remember where the line is — amber is its own hue rather than the body sand, which made "warning" and "label" identical. Chrome is demoted throughout: tabs are underlined rather than filled, and the footer trades decoration for the freshness of the data.

Every dimension derives from `Kirigami.Units.gridUnit`, which tracks the desktop's font metrics — there are no hardcoded pixel sizes left to break on HiDPI.

## License

[GPL-2.0-or-later](LICENSE) — consistent with the KDE Plasma ecosystem.
