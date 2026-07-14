"""Ollama local-models provider.

Lists installed models (/api/tags), marks which are resident in memory
(/api/ps), and can load/unload a model from RAM/VRAM via keep_alive. The
"preferred" model is just a label we persist for the user; it does not force
anything on Ollama, other apps can read it if they want.
"""

import json
import urllib.request

DEFAULT_URL = "http://127.0.0.1:11434"


class OllamaProvider:
    id = "ollama"
    label = "Ollama"

    def __init__(self, base_url: str, config: dict):
        self.base = base_url.rstrip("/")
        self.config = config  # shared dict, persisted by the service

    # ── http helpers ─────────────────────────────────────────────────────────
    def _get(self, path: str) -> dict:
        with urllib.request.urlopen(self.base + path, timeout=8) as r:
            return json.load(r)

    def _post(self, path: str, payload: dict, timeout: int = 30) -> dict:
        req = urllib.request.Request(
            self.base + path, data=json.dumps(payload).encode(),
            method="POST", headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.load(r)

    # ── reads ────────────────────────────────────────────────────────────────
    def models(self) -> dict:
        try:
            tags = self._get("/api/tags").get("models", [])
        except Exception as e:
            return {"ok": False, "error": str(e), "models": [],
                    "preferred": self.config.get("ollama_preferred", "")}

        loaded = {}
        try:
            for m in self._get("/api/ps").get("models", []):
                loaded[m["name"]] = m
        except Exception:
            pass  # /api/ps is best-effort; server may be mid-restart

        out = []
        for m in tags:
            det = m.get("details", {}) or {}
            lm = loaded.get(m["name"])
            out.append({
                "name": m["name"],
                "size": m.get("size"),
                "family": det.get("family", ""),
                "param_size": det.get("parameter_size", ""),
                "quant": det.get("quantization_level", ""),
                "loaded": lm is not None,
                "size_vram": (lm or {}).get("size_vram"),
                "expires_at": (lm or {}).get("expires_at"),
            })
        out.sort(key=lambda x: x["name"])
        return {"ok": True, "error": None, "models": out,
                "preferred": self.config.get("ollama_preferred", "")}

    # ── writes ───────────────────────────────────────────────────────────────
    def load(self, name: str) -> dict:
        # Empty prompt + keep_alive=-1 loads the model and keeps it resident.
        # Cold loads of a multi-GB model can take a while, so allow generous time.
        self._post("/api/generate", {"model": name, "prompt": "", "keep_alive": -1},
                   timeout=300)
        return {"ok": True}

    def unload(self, name: str) -> dict:
        # keep_alive=0 evicts the model immediately.
        self._post("/api/generate", {"model": name, "prompt": "", "keep_alive": 0})
        return {"ok": True}
