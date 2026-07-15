"""Claude Code quota provider.

Reads the Claude Code OAuth token from ~/.claude/.credentials.json and queries
Anthropic's live usage endpoint (the same data `/usage` shows inside Claude
Code): rolling 5-hour and 7-day utilization, with reset times.

Token handling is intentionally defensive:
  * We read the credentials file fresh on every snapshot. Claude Code refreshes
    the token by itself whenever it runs, so most of the time we just read it.
  * If the access token is expired we *try* to refresh it and write the rotated
    token back atomically (preserving every other field). If the refresh fails
    for any reason we never touch the file — the widget just shows Claude as
    offline until the token is refreshed again by Claude Code.
"""

import json
import os
import time
import urllib.error
import urllib.request
from pathlib import Path

CREDS_FILE = Path.home() / ".claude" / ".credentials.json"
USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
TOKEN_URL = "https://console.anthropic.com/v1/oauth/token"
# Public OAuth client id used by Claude Code.
CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

# Windows we surface, in display order. Keys not present / null are skipped.
WINDOW_LABELS = [
    ("five_hour", "5 horas"),
    ("seven_day", "7 días"),
    ("seven_day_opus", "7d · Opus"),
    ("seven_day_sonnet", "7d · Sonnet"),
]


class ClaudeProvider:
    id = "claude"
    label = "Claude"

    def __init__(self):
        self._last = None  # last good snapshot, reused when a poll fails

    # ── credentials ──────────────────────────────────────────────────────────
    def _load_creds(self) -> dict:
        with open(CREDS_FILE) as f:
            return json.load(f)

    def _save_creds(self, data: dict) -> None:
        tmp = CREDS_FILE.with_name(CREDS_FILE.name + ".tmp")
        tmp.write_text(json.dumps(data, indent=2))
        os.chmod(tmp, 0o600)
        tmp.replace(CREDS_FILE)

    def _refresh(self, refresh_token: str) -> dict:
        body = json.dumps({
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
            "client_id": CLIENT_ID,
        }).encode()
        req = urllib.request.Request(
            TOKEN_URL, data=body, method="POST",
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=15) as r:
            return json.load(r)

    def _access_token(self, force_refresh: bool = False) -> tuple[str, dict]:
        """Return a (hopefully valid) access token plus the oauth block.

        Normally we only refresh when the cached ``expiresAt`` says the token
        has expired. ``force_refresh`` bypasses that check: the caller uses it
        after a live 401, where the server has rejected a token our clock still
        believes is valid (server-side revocation, a rotation by Claude Code
        that invalidated our copy, or clock skew).
        """
        data = self._load_creds()
        oauth = data.get("claudeAiOauth", {})
        expires = oauth.get("expiresAt", 0) or 0
        # 60s of slack so we don't race a just-expiring token.
        if not force_refresh and expires > (time.time() + 60) * 1000:
            return oauth.get("accessToken", ""), oauth

        rt = oauth.get("refreshToken")
        if not rt:
            return oauth.get("accessToken", ""), oauth
        try:
            tok = self._refresh(rt)
            oauth["accessToken"] = tok["access_token"]
            oauth["refreshToken"] = tok.get("refresh_token", rt)
            oauth["expiresAt"] = int((time.time() + tok.get("expires_in", 3600)) * 1000)
            data["claudeAiOauth"] = oauth
            self._save_creds(data)
        except Exception as e:
            print(f"[claude] token refresh failed: {e}", flush=True)
        return oauth.get("accessToken", ""), oauth

    # ── snapshot ─────────────────────────────────────────────────────────────
    def _fetch_usage(self, force_refresh: bool = False) -> tuple[dict, dict]:
        """Hit the usage endpoint once, returning (usage, oauth)."""
        token, oauth = self._access_token(force_refresh=force_refresh)
        req = urllib.request.Request(USAGE_URL, headers={
            "Authorization": f"Bearer {token}",
            "anthropic-beta": "oauth-2025-04-20",
            "anthropic-version": "2023-06-01",
        })
        with urllib.request.urlopen(req, timeout=15) as r:
            return json.load(r), oauth

    def snapshot(self) -> dict:
        if not CREDS_FILE.exists():
            return self._err("no autenticado (ejecuta Claude Code una vez)")
        try:
            try:
                usage, oauth = self._fetch_usage()
            except urllib.error.HTTPError as e:
                # A 401 means the server rejected a token our clock thought was
                # valid. Force a refresh and retry once before giving up.
                if e.code == 401:
                    print("[claude] 401, forcing token refresh and retrying",
                          flush=True)
                    usage, oauth = self._fetch_usage(force_refresh=True)
                else:
                    raise

            windows = []
            for key, label in WINDOW_LABELS:
                w = usage.get(key)
                if w and w.get("utilization") is not None:
                    windows.append({
                        "label": label,
                        "utilization": round(float(w["utilization"]), 1),
                        "resets_at": w.get("resets_at"),
                    })

            extra = usage.get("extra_usage") or {}
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
            # 429 (rate limit) and 5xx are transient: the usage endpoint throttles
            # or hiccups briefly. If we already have good numbers, keep showing them
            # as valid so the panel doesn't flap to "offline" — the next poll recovers.
            if e.code == 429 or e.code >= 500:
                if self._last:
                    print(f"[claude] transient HTTP {e.code}, keeping last snapshot",
                          flush=True)
                    return self._last
                return self._err(f"HTTP {e.code} (reintentando)")
            # 401/403 etc. are real auth failures — surface them.
            return self._degrade(f"HTTP {e.code}")
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
