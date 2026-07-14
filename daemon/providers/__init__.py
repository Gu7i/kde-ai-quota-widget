"""Quota providers. Each provider exposes a .snapshot() returning a dict:

    {
        "id": "claude",
        "label": "Claude",
        "ok": bool,
        "error": str | None,
        "windows": [ {"label": "5 horas", "utilization": 55.0, "resets_at": "..."} , ... ],
        "meta": { "plan": "pro", ... },
    }

To add a provider (Codex, Gemini, ...) drop a module here and register it in
ai_quota_service.build_providers().
"""
