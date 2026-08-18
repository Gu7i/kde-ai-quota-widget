#!/usr/bin/env python3
"""
AI Quota local HTTP daemon — exposes AI subscription quotas and Ollama models
on localhost:7183.

Endpoints:
  GET  /status                → daemon health
  GET  /providers             → quota snapshot for every configured provider
  GET  /claude/status         → status.claude.com (indicator, components, incidents)
  GET  /ollama/models         → installed models + which are resident in memory
  POST /ollama/load           → load a model into memory  (body: {"name": "..."})
  POST /ollama/unload         → evict a model from memory  (body: {"name": "..."})
  POST /ollama/preferred      → mark a model as preferred  (body: {"name": "..."})
"""

import json
import sys
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from providers.claude_provider import ClaudeProvider   # noqa: E402
from providers.claude_status_provider import ClaudeStatusProvider  # noqa: E402
from providers.ollama_provider import OllamaProvider    # noqa: E402

CONFIG_FILE = Path.home() / ".config" / "ai-quota-widget" / "config.json"
PORT = 7183
# Anthropic's usage endpoint allows roughly 30 requests/hour; at 60s we spent
# half of every hour being 429'd. Quotas don't move fast enough to care.
POLL_INTERVAL = 180  # seconds between quota refreshes
# At boot we can easily start before the network is up (DNS not resolving yet).
# Retry on this ramp until the first clean poll instead of showing an error for
# a full interval.
STARTUP_RETRIES = (5, 15, 30, 60)

# ── config ──────────────────────────────────────────────────────────────────

DEFAULT_CONFIG = {
    "ollama_url": "http://127.0.0.1:11434",
    "ollama_preferred": "",
}


def load_config() -> dict:
    cfg = dict(DEFAULT_CONFIG)
    if CONFIG_FILE.exists():
        try:
            cfg.update(json.load(open(CONFIG_FILE)))
        except Exception as e:
            print(f"[config] {e}", file=sys.stderr)
    return cfg


def save_config(cfg: dict) -> None:
    CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
    CONFIG_FILE.write_text(json.dumps(cfg, indent=2, ensure_ascii=False))


# ── global state ────────────────────────────────────────────────────────────

_config = load_config()
_quota_providers: list = []
_ollama: OllamaProvider | None = None
_status: ClaudeStatusProvider | None = None
_snapshots: list = []
_status_snapshot: dict = {}
_snap_lock = threading.Lock()
_last_refresh: float = 0


def build_providers() -> None:
    """Register the quota providers. Add Codex/Gemini here later."""
    global _quota_providers, _ollama, _status
    _quota_providers = [ClaudeProvider()]
    _status = ClaudeStatusProvider()
    _ollama = OllamaProvider(_config.get("ollama_url", DEFAULT_CONFIG["ollama_url"]), _config)


def _refresh_snapshots(force: bool = False) -> None:
    """Re-poll every provider. ``force`` comes from the widget's Actualizar
    button and lets a provider skip its own rate-limit backoff."""
    global _snapshots, _status_snapshot, _last_refresh
    snaps = []
    for p in _quota_providers:
        try:
            snaps.append(p.snapshot(force=force))
        except Exception as e:
            snaps.append({"id": getattr(p, "id", "?"), "label": getattr(p, "label", "?"),
                          "ok": False, "error": str(e), "windows": [], "meta": {}})
    # The status page is a separate, unauthenticated service: it must keep
    # working when the quota poll is failing, since "is Claude down?" is
    # exactly the question a failing quota poll raises.
    try:
        status = _status.snapshot(force=force)
    except Exception as e:
        status = {"ok": False, "error": str(e), "indicator": "unknown", "severity": 0,
                  "description": "", "components": [], "incidents": [],
                  "url": "https://status.claude.com"}
    with _snap_lock:
        _snapshots = snaps
        _status_snapshot = status
        _last_refresh = time.time()


def _all_ok() -> bool:
    with _snap_lock:
        return bool(_snapshots) and all(s.get("ok") for s in _snapshots)


def _refresh_loop() -> None:
    for delay in STARTUP_RETRIES:
        _refresh_snapshots()
        if _all_ok():
            break
        time.sleep(delay)
    while True:
        time.sleep(POLL_INTERVAL)
        _refresh_snapshots()


# ── HTTP handler ────────────────────────────────────────────────────────────

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def _send_json(self, code: int, data):
        body = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self) -> dict:
        length = int(self.headers.get("Content-Length", 0))
        if length:
            try:
                return json.loads(self.rfile.read(length))
            except Exception:
                return {}
        return {}

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path.rstrip("/")

        if path == "/status" or path == "":
            with _snap_lock:
                self._send_json(200, {
                    "ok": True,
                    "last_refresh": _last_refresh,
                    "providers": [s["id"] for s in _snapshots],
                })
        elif path == "/providers":
            with _snap_lock:
                self._send_json(200, list(_snapshots))
        elif path == "/claude/status":
            with _snap_lock:
                self._send_json(200, dict(_status_snapshot))
        elif path == "/ollama/models":
            self._send_json(200, _ollama.models())
        else:
            self._send_json(404, {"error": "not found"})

    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path.rstrip("/")
        body = self._read_body()
        name = (body.get("name") or "").strip()

        if path == "/ollama/load":
            if not name:
                return self._send_json(400, {"ok": False, "error": "name required"})
            # Loading a cold model can take a while — fire it off in the
            # background and let the model list reflect it on the next poll.
            threading.Thread(target=_ollama.load, args=(name,), daemon=True).start()
            self._send_json(200, {"ok": True, "started": True})

        elif path == "/ollama/unload":
            if not name:
                return self._send_json(400, {"ok": False, "error": "name required"})
            try:
                self._send_json(200, _ollama.unload(name))
            except Exception as e:
                self._send_json(500, {"ok": False, "error": str(e)})

        elif path == "/ollama/preferred":
            _config["ollama_preferred"] = name
            try:
                save_config(_config)
                self._send_json(200, {"ok": True, "preferred": name})
            except Exception as e:
                self._send_json(500, {"ok": False, "error": str(e)})

        elif path == "/refresh":
            _refresh_snapshots(force=True)
            with _snap_lock:
                self._send_json(200, list(_snapshots))

        else:
            self._send_json(404, {"error": "not found"})

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.end_headers()


# ── entry point ─────────────────────────────────────────────────────────────

def main():
    build_providers()
    # The first poll happens inside the loop (on the startup retry ramp) so a
    # network that isn't up yet can't delay binding the port.
    print("Fetching initial quotas…", flush=True)
    t = threading.Thread(target=_refresh_loop, daemon=True)
    t.start()

    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"AI Quota daemon running on http://127.0.0.1:{PORT}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("Stopped.")


if __name__ == "__main__":
    main()
