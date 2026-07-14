#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAEMON_DIR="$SCRIPT_DIR/daemon"
PLASMOID_DIR="$SCRIPT_DIR/plasmoid/ai-quota"
SERVICE_DIR="$HOME/.config/systemd/user"
PLASMOID_DEST="$HOME/.local/share/plasma/plasmoids/org.kde.ai-quota"

echo "=== AI Quota KDE Widget Installer ==="
echo ""

# ── 1. Python >= 3.11 ─────────────────────────────────────────────────────────
echo "[1/4] Checking Python version…"
PY=$(python3 -c 'import sys; print(sys.version_info >= (3, 11))' 2>/dev/null || echo False)
if [[ "$PY" != "True" ]]; then
    echo "Error: Python 3.11+ is required."
    exit 1
fi
echo "  OK: $(python3 --version)"
echo "  Claude quota is read from ~/.claude/.credentials.json (run Claude Code once if missing)."
echo "  Ollama is auto-detected at http://127.0.0.1:11434"

# ── 2. systemd user service ───────────────────────────────────────────────────
echo ""
echo "[2/4] Installing systemd user service…"
mkdir -p "$SERVICE_DIR"
cat > "$SERVICE_DIR/ai-quota-daemon.service" << EOF
[Unit]
Description=AI Quota Daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${DAEMON_DIR}
ExecStart=$(command -v python3) -u ai_quota_service.py
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable ai-quota-daemon.service
systemctl --user start ai-quota-daemon.service
loginctl enable-linger "$USER" 2>/dev/null || true
echo "  Service enabled and started."

# ── 3. Plasma plasmoid ────────────────────────────────────────────────────────
echo ""
echo "[3/4] Installing Plasma plasmoid…"
mkdir -p "$(dirname "$PLASMOID_DEST")"
rm -rf "$PLASMOID_DEST"
ln -s "$PLASMOID_DIR" "$PLASMOID_DEST"
rm -rf "$HOME/.cache/plasmashell/qmlcache/" 2>/dev/null || true
echo "  Plasmoid installed (symlink → $PLASMOID_DIR)."

# ── 4. Add widget to panel ────────────────────────────────────────────────────
echo ""
echo "[4/4] Adding widget to KDE panel…"
DBUS=unix:path=/run/user/$(id -u)/bus
if command -v qdbus6 &>/dev/null && \
   DBUS_SESSION_BUS_ADDRESS=$DBUS qdbus6 org.kde.plasmashell /PlasmaShell \
     org.kde.PlasmaShell.evaluateScript 'print(panels().length)' &>/dev/null; then

    DBUS_SESSION_BUS_ADDRESS=$DBUS \
    qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '
var ps = panels();
for (var i = 0; i < ps.length; i++) {
    var ws = ps[i].widgets();
    var found = false;
    for (var j = 0; j < ws.length; j++) {
        if (ws[j].type === "org.kde.ai-quota") { found = true; break; }
    }
    if (!found) {
        ps[i].addWidget("org.kde.ai-quota");
        print("added to panel " + ps[i].id);
        break;
    }
}
' 2>/dev/null && echo "  Widget added to panel." \
             || echo "  Add the widget manually: right-click panel → Add widgets → AI Quota"
else
    echo "  Plasma not running — add the widget manually after login."
fi

echo ""
echo "Done! Click the AI Quota icon in your panel."
echo ""
echo "Useful commands:"
echo "  systemctl --user status ai-quota-daemon"
echo "  journalctl --user -u ai-quota-daemon -f"
echo "  curl http://127.0.0.1:7183/providers | python3 -m json.tool"
