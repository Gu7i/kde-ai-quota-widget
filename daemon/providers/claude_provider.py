"""Claude Code quota provider.

Reads the Claude Code OAuth token from ~/.claude/.credentials.json and queries
Anthropic's live usage endpoint (the same data `/usage` shows inside Claude
Code): rolling 5-hour and 7-day utilization, with reset times.

Two rules keep this well-behaved:

  * **We never write the credentials file.** OAuth refresh tokens are
    single-use: whoever redeems one invalidates it for everybody else. When
    this daemon and Claude Code both refreshed from the same file they raced,
    and the loser sat in a 403 loop until the winner rewrote the pair. Claude
    Code owns the token; we only ever read it. If the access token is expired
    we say so and wait for Claude Code to rotate it.

  * **We back off when throttled.** The usage endpoint allows roughly 30
    requests/hour. On a 429 or 5xx we stop calling for a growing interval
    instead of hammering it at the poll rate, and keep showing the last good
    numbers meanwhile.
"""

import json
import time
import urllib.error
import urllib.request
from pathlib import Path

CREDS_FILE = Path.home() / ".claude" / ".credentials.json"
USAGE_URL = "https://api.anthropic.com/api/oauth/usage"

# Backoff after a throttle/server error, in seconds: doubles per consecutive
# failure between these bounds, and resets to zero on the first success.
BACKOFF_MIN = 120
BACKOFF_MAX = 900

# Windows we surface, in display order. Keys not present / null are skipped.
# The third element is the window length in seconds: the API only tells us when
# a window resets, and the widget needs the span to work out how much of it has
# already been spent (used for the "at this pace" projection).
WINDOW_LABELS = [
    ("five_hour", "5 horas", 5 * 3600),
    ("seven_day", "7 días", 7 * 86400),
    ("seven_day_opus", "7d · Opus", 7 * 86400),
    ("seven_day_sonnet", "7d · Sonnet", 7 * 86400),
]


class ClaudeProvider:
    id = "claude"
    label = "Claude"

    def __init__(self):
        self._last = None          # last good snapshot, reused when a poll fails
        self._backoff = 0          # current backoff length, seconds
        self._backoff_until = 0.0  # monotonic-ish wall clock deadline

    # ── credentials (read-only) ──────────────────────────────────────────────
    def _oauth(self) -> dict:
        with open(CREDS_FILE) as f:
            return json.load(f).get("claudeAiOauth", {})

    # ── throttling ───────────────────────────────────────────────────────────
    def _enter_backoff(self) -> None:
        self._backoff = min(max(self._backoff * 2, BACKOFF_MIN), BACKOFF_MAX)
        self._backoff_until = time.time() + self._backoff

    def _clear_backoff(self) -> None:
        self._backoff = 0
        self._backoff_until = 0.0

    # ── snapshot ─────────────────────────────────────────────────────────────
    def _fetch_usage(self, token: str) -> dict:
        req = urllib.request.Request(USAGE_URL, headers={
            "Authorization": f"Bearer {token}",
            "anthropic-beta": "oauth-2025-04-20",
            "anthropic-version": "2023-06-01",
        })
        with urllib.request.urlopen(req, timeout=15) as r:
            return json.load(r)

    def snapshot(self, force: bool = False) -> dict:
        """Poll the usage endpoint.

        ``force`` is set by the widget's Actualizar button: a human clicking a
        button is not what gets us rate limited, so it skips the backoff wait.
        The automatic poll loop always respects it.
        """
        if not CREDS_FILE.exists():
            return self._err("no autenticado (ejecuta Claude Code una vez)")

        if not force and time.time() < self._backoff_until:
            # Still throttled — don't spend a request we know will be refused.
            return self._last or self._err("esperando datos…")

        try:
            oauth = self._oauth()
            token = oauth.get("accessToken", "")
            if not token:
                return self._degrade("sin token (abre Claude Code)")

            usage = self._fetch_usage(token)

            windows = []
            for key, label, span in WINDOW_LABELS:
                w = usage.get(key)
                if w and w.get("utilization") is not None:
                    windows.append({
                        "label": label,
                        "utilization": round(float(w["utilization"]), 1),
                        "resets_at": w.get("resets_at"),
                        "window_seconds": span,
                    })

            extra = usage.get("extra_usage") or {}
            self._clear_backoff()
            self._last = {
                "id": self.id, "label": self.label, "ok": True, "error": None,
                "windows": windows,
                "meta": {
                    "plan": oauth.get("subscriptionType", ""),
                    "tier": oauth.get("rateLimitTier", ""),
                    "extra_usage": bool(extra.get("is_enabled")),
                },
            }
            return self._last
        except urllib.error.HTTPError as e:
            # 429 (rate limit) and 5xx are transient. Back off so we stop adding
            # to the pile, and keep the last good numbers valid so the panel
            # doesn't flap to "offline" — the next poll recovers.
            if e.code == 429 or e.code >= 500:
                self._enter_backoff()
                print(f"[claude] HTTP {e.code}, pausando {self._backoff}s",
                      flush=True)
                return self._last or self._err("esperando datos…")
            if e.code in (401, 403):
                # Our copy of the token is dead. Only Claude Code can rotate it.
                return self._degrade("token caducado (abre Claude Code)")
            return self._degrade(f"HTTP {e.code}")
        except urllib.error.URLError as e:
            return self._degrade(f"sin conexión ({e.reason})")
        except Exception as e:
            return self._degrade(str(e))

    def _degrade(self, msg: str) -> dict:
        """Mark offline but keep the last good numbers visible if we have any."""
        if self._last:
            stale = dict(self._last)
            stale["ok"] = False
            stale["error"] = msg
            return stale
        return self._err(msg)

    def _err(self, msg: str) -> dict:
        return {"id": self.id, "label": self.label, "ok": False,
                "error": msg, "windows": [], "meta": {}}
