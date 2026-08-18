"""Claude service-status provider.

Reads https://status.claude.com — an Atlassian Statuspage — so the widget can
answer the question the quota bars can't: "is it me, or is Claude down?".

One call to /api/v2/summary.json returns the overall indicator, every
component and the unresolved incidents, so we never make three requests where
one does. The endpoint is public and CDN-cached: no credentials, no rate limit
worth backing off from. Failures just keep the last good snapshot.
"""

import json
import urllib.error
import urllib.request

SUMMARY_URL = "https://status.claude.com/api/v2/summary.json"
PAGE_URL = "https://status.claude.com"

# Statuspage's overall indicator, worst-first. The widget colours by severity,
# so it needs an order it can compare, not just a string.
SEVERITY = {"none": 0, "minor": 1, "major": 2, "critical": 3}

# Components we care about. The page also lists Console, Cowork, Government…
# which nobody driving this widget is going to act on; showing all six turns a
# glanceable strip into a list. Anything degraded is surfaced regardless (see
# below) — this only decides what stays visible while everything is fine.
PRIMARY_COMPONENTS = (
    "Claude Code",
    "Claude API (api.anthropic.com)",
    "claude.ai",
)


class ClaudeStatusProvider:
    id = "claude_status"
    label = "Estado de Claude"

    def __init__(self):
        self._last = None

    def snapshot(self, force: bool = False) -> dict:
        try:
            with urllib.request.urlopen(SUMMARY_URL, timeout=10) as r:
                data = json.load(r)
        except urllib.error.URLError as e:
            return self._degrade(f"sin conexión ({e.reason})")
        except Exception as e:
            return self._degrade(str(e))

        status = data.get("status") or {}
        indicator = status.get("indicator") or "none"

        components = []
        for c in data.get("components") or []:
            if c.get("group"):
                continue
            name = c.get("name") or ""
            state = c.get("status") or "operational"
            # Keep the shortlist always, plus anything currently unhealthy —
            # an outage in a component we don't normally show still matters.
            if name in PRIMARY_COMPONENTS or state != "operational":
                components.append({
                    "name": name,
                    "status": state,
                    "primary": name in PRIMARY_COMPONENTS,
                })

        incidents = []
        for i in data.get("incidents") or []:
            updates = i.get("incident_updates") or []
            incidents.append({
                "name": i.get("name") or "",
                "status": i.get("status") or "",
                "impact": i.get("impact") or "none",
                "url": i.get("shortlink") or PAGE_URL,
                "updated_at": i.get("updated_at"),
                # Statuspage returns updates newest-first; the latest one is
                # the only text worth the space in a popup this size.
                "body": (updates[0].get("body") if updates else "") or "",
            })

        self._last = {
            "ok": True,
            "error": None,
            "indicator": indicator,
            "severity": SEVERITY.get(indicator, 0),
            "description": status.get("description") or "",
            "components": components,
            "incidents": incidents,
            "url": PAGE_URL,
        }
        return self._last

    def _degrade(self, msg: str) -> dict:
        """Never claim an outage we failed to read. A stale snapshot is marked
        not-ok so the widget can grey it out, and if we never got one we report
        unknown rather than 'operational'."""
        if self._last:
            stale = dict(self._last)
            stale["ok"] = False
            stale["error"] = msg
            return stale
        return {"ok": False, "error": msg, "indicator": "unknown", "severity": 0,
                "description": "", "components": [], "incidents": [], "url": PAGE_URL}
