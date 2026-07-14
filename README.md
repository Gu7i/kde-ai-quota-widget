# AI Quota KDE Widget

See your AI subscription quotas and manage your local Ollama models from the KDE Plasma panel. One tab per AI provider with live usage, plus an Ollama tab to load/unload models from memory — no browser, no dashboard.

![KDE Plasma 6](https://img.shields.io/badge/KDE_Plasma-6-blue)
![Python 3.11+](https://img.shields.io/badge/Python-3.11+-green)
![License: GPL v2](https://img.shields.io/badge/License-GPLv2-blue)

## Features

- **AI neural-network panel icon** tinted by your Claude 5-hour utilization at a glance (teal → sand → red); dimmed red when the daemon is offline
- **Tabs** separating providers, one per AI plus an Ollama tab
- **Claude tab — live quota** (the same numbers `/usage` shows inside Claude Code):
  - **5-hour** and **7-day** rolling windows as labelled progress bars with utilization %
  - "reinicia en Xh Ym" reset hint per window
  - Opus / Sonnet 7-day windows shown when the API reports them
  - Plan (`PRO`) and rate-limit tier in the header/footer
- **Ollama tab — local models**:
  - Lists installed models with params, quantization and size on disk
  - **CARGAR / LIBERAR** button loads a model into RAM/VRAM (`keep_alive`) or evicts it — with an **EN RAM** badge for resident models
  - ★ mark a **preferred** model; the choice is persisted and readable by other apps
- **Instant feedback** — actions respond immediately (optimistic UI); confirmed by the next poll
- **Extensible provider architecture** — Codex, Gemini, etc. can be added by dropping one module in `daemon/providers/`
- Daemon runs as a systemd user service (starts at boot)
- Reads Claude's OAuth token from `~/.claude/.credentials.json` and refreshes it automatically when it expires (writing back atomically, and only on success — your credentials are never corrupted if a refresh fails)

## Providers

| Provider | Source | Data |
|---|---|---|
| Claude | `~/.claude/.credentials.json` + `api.anthropic.com/api/oauth/usage` | Live 5h / 7d utilization, resets, plan |
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
│  │  refreshes quotas every 60s  │   │
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
      {"label": "5 horas", "utilization": 67.0, "resets_at": "2026-07-14T06:29:59+00:00"},
      {"label": "7 días",  "utilization": 26.0, "resets_at": "2026-07-16T04:59:59+00:00"}
    ],
    "meta": {"plan": "pro", "tier": "default_claude_ai", "extra_usage": false}
  }
]
```

## How Claude quota works

The daemon reads the Claude Code OAuth token from `~/.claude/.credentials.json` and calls Anthropic's usage endpoint — the same data the `/usage` command shows inside Claude Code:

- `GET https://api.anthropic.com/api/oauth/usage` with `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20`, `anthropic-version: 2023-06-01`
- Returns `five_hour` / `seven_day` (and `seven_day_opus` / `seven_day_sonnet` when applicable) with `utilization` (%) and `resets_at`

**Token handling is defensive:** the file is read fresh on every poll (Claude Code keeps it refreshed whenever it runs). If the access token is expired the daemon refreshes it against `https://console.anthropic.com/v1/oauth/token` using Claude Code's public client id, and writes the rotated token back **atomically and only on success**. If a refresh ever fails, the file is left untouched and Claude simply shows as offline until the next refresh — nothing is corrupted.

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
       "windows": [{"label": "5 horas", "utilization": 40.0, "resets_at": "..."}],
       "meta": {"plan": "plus"},
   }
   ```

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
curl http://127.0.0.1:7183/ollama/models | python3 -m json.tool
curl -X POST http://127.0.0.1:7183/ollama/load \
     -H "Content-Type: application/json" -d '{"name":"qwen3:8b"}'
```

## Files

```
daemon/
  ai_quota_service.py          HTTP daemon on :7183 + 60s quota refresh loop
  providers/
    __init__.py                Provider contract docs
    claude_provider.py         Reads ~/.claude token, live usage, auto-refresh
    ollama_provider.py         /api/tags, /api/ps, load/unload, preferred
plasmoid/ai-quota/
  contents/ui/
    main.qml                   Plasmoid root: polling, tabs, panel icon
    QuotaBar.qml               A single utilization window (labelled bar)
    ModelRow.qml               One Ollama model row (load/unload/prefer)
  metadata.json                Plasma plugin descriptor
install.sh                     One-shot installer
uninstall.sh                   Clean removal
```

## Design

A sibling of [kde-ewelink-widget](https://github.com/Gu7i/kde-ewelink-widget): same industrial monospace chrome (filled tabs, status dot, `LLM CORP™` footer), in an American-vintage **dark** palette — charcoal background `#201F1D`, sand text `#C1AB85`, teal accent `#3E6868`, red `#C94E44`. Utilization bars shift teal → sand (≥70%) → red (≥90%). The panel icon is a neural-network glyph recolored by the same scale.

## License

[GPL-2.0-or-later](LICENSE) — consistent with the KDE Plasma ecosystem.
