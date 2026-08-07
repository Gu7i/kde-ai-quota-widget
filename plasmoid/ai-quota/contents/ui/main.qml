import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property string daemonUrl: "http://127.0.0.1:7183"
    // Fast poll while the popup is open; the daemon only re-queries the
    // providers every 60s, so polling that fast with the popup closed is waste.
    readonly property int pollMs: 8000
    readonly property int idlePollMs: 30000

    // ── Palette — American-vintage, in two grounds ────────────────────────────
    // The identity (sand / teal / rust) is the point of this widget, so it is
    // kept by hand rather than derived from the Plasma theme — but it now comes
    // in a light variant too, because a hardcoded charcoal slab sitting in a
    // Breeze Light desktop was the single loudest thing on screen.
    readonly property bool darkUi: Kirigami.Theme.backgroundColor.hsvValue < 0.5

    readonly property color bg:       darkUi ? "#201F1D" : "#F6F2E8"
    readonly property color surface2: darkUi ? "#282622" : "#EAE3D4"
    readonly property color line:     darkUi ? "#3A362E" : "#CFC4AC"
    readonly property color text:     darkUi ? "#E8DFCB" : "#241F19"  // body ink
    readonly property color textDim:  darkUi ? "#9A917D" : "#6A6153"
    readonly property color sand:     darkUi ? "#C1AB85" : "#6B5B41"  // brand accent
    readonly property color teal:     darkUi ? "#6FA6A0" : "#35706B"  // ok / low
    readonly property color amber:    darkUi ? "#D8933D" : "#9A6314"  // 70..90
    readonly property color red:      darkUi ? "#C94E44" : "#A93B32"  // 90+ / error

    // ── Type scale ───────────────────────────────────────────────────────────
    // gridUnit follows the user's font metrics, so every size below scales with
    // the desktop's DPI instead of being frozen at 100%.
    readonly property int fsMicro: Math.round(Kirigami.Units.gridUnit * 0.5)
    readonly property int fsSmall: Math.round(Kirigami.Units.gridUnit * 0.58)
    readonly property int fsBase:  Math.round(Kirigami.Units.gridUnit * 0.7)

    // ── State ─────────────────────────────────────────────────────────────────
    property var  providersData: []      // quota snapshots from /providers
    property var  ollamaModels: []
    property string ollamaPreferred: ""
    property bool ollamaOk: false
    property bool daemonOk: false
    property int  activeTab: 0
    property var  tabLabels: ["OLLAMA"]
    property var  busyModels: ({})        // name -> expected loaded state
    property bool refreshing: false       // a forced /refresh is in flight
    property double lastUpdate: 0         // ms epoch of the last good poll
    property double nowMs: Date.now()     // ticks so "hace Xs" stays live
    property int  failStreak: 0           // consecutive failed polls

    readonly property real headlineUtil: {
        if (providersData.length > 0 && providersData[0].windows
                && providersData[0].windows.length > 0)
            return providersData[0].windows[0].utilization
        return -1
    }

    preferredRepresentation: compactRepresentation
    toolTipMainText: "AI Quota"
    toolTipSubText: daemonOk
        ? (headlineUtil >= 0 ? ("Claude 5h: " + Math.round(headlineUtil) + "%") : "Conectado")
        : "Daemon offline"

    function utilColor(u) {
        if (u >= 90) return red
        if (u >= 70) return amber
        return teal
    }

    // ── Compact (panel) ───────────────────────────────────────────────────────
    compactRepresentation: Item {
        Kirigami.Icon {
            id: panelIcon
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height)
            height: width
            source: Qt.resolvedUrl("../icons/ai-neural.svg")
            isMask: true
            // Deliberately the plain theme color: the panel is a row of
            // monochrome icons and a tinted one breaks that line.
            color: Kirigami.Theme.textColor
            opacity: root.daemonOk ? 1 : 0.4
        }

        // Status badge instead of tinting the glyph — carries "you are near the
        // limit" without turning the icon into the odd one out.
        Rectangle {
            visible: root.daemonOk && root.headlineUtil >= 70
            anchors.right: panelIcon.right
            anchors.top: panelIcon.top
            width: Math.max(4, Math.round(panelIcon.width * 0.26))
            height: width
            radius: width / 2
            color: root.headlineUtil >= 90 ? root.red : root.amber
            border.width: 1
            border.color: Kirigami.Theme.backgroundColor
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
        }
    }

    // ── Full (popup) ──────────────────────────────────────────────────────────
    fullRepresentation: Item {
        implicitWidth:  Kirigami.Units.gridUnit * 24
        implicitHeight: Kirigami.Units.gridUnit * 24
        Layout.preferredWidth:  Kirigami.Units.gridUnit * 24
        Layout.preferredHeight: Kirigami.Units.gridUnit * 24
        Layout.minimumWidth:    Kirigami.Units.gridUnit * 22

        Rectangle {
            anchors.fill: parent
            color: root.bg

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // ── Header ────────────────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: Kirigami.Units.smallSpacing * 2
                    Layout.bottomMargin: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing * 2

                    Text {
                        text: "AI·QUOTA"
                        font.bold: true
                        font.pixelSize: root.fsSmall
                        font.family: "monospace"
                        font.letterSpacing: 2.4
                        color: root.sand
                    }

                    Rectangle {
                        visible: planTxt.text.length > 0
                        implicitWidth: planTxt.implicitWidth + Kirigami.Units.smallSpacing * 2.5
                        implicitHeight: Math.round(Kirigami.Units.gridUnit * 0.85)
                        color: "transparent"
                        border.color: root.line
                        border.width: 1
                        Text {
                            id: planTxt
                            anchors.centerIn: parent
                            text: {
                                if (root.providersData.length > 0 && root.providersData[0].meta)
                                    return (root.providersData[0].meta.plan || "").toUpperCase()
                                return ""
                            }
                            font.pixelSize: root.fsMicro
                            font.family: "monospace"
                            font.letterSpacing: 1.2
                            color: root.textDim
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        visible: !root.daemonOk
                        text: "DAEMON OFFLINE"
                        font.pixelSize: root.fsMicro
                        font.bold: true
                        font.family: "monospace"
                        color: root.red
                    }

                    // Refresh
                    Rectangle {
                        implicitWidth: Math.round(Kirigami.Units.gridUnit * 1.45)
                        implicitHeight: implicitWidth
                        color: refreshArea.containsMouse ? root.surface2 : "transparent"
                        border.color: refreshArea.containsMouse ? root.line : "transparent"
                        border.width: 1
                        opacity: root.refreshing ? 0.6 : 1

                        Text {
                            id: refreshGlyph
                            anchors.centerIn: parent
                            text: "↺"
                            font.pixelSize: root.fsBase
                            font.bold: true
                            color: refreshArea.containsMouse ? root.text : root.textDim

                            RotationAnimation on rotation {
                                running: root.refreshing
                                from: 0; to: 360
                                duration: 900
                                loops: Animation.Infinite
                                onRunningChanged: if (!running) refreshGlyph.rotation = 0
                            }
                        }

                        MouseArea {
                            id: refreshArea
                            anchors.fill: parent
                            enabled: !root.refreshing
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.forceRefresh()
                            QQC2.ToolTip.text: root.refreshing ? "Actualizando…"
                                                               : "Actualizar ahora"
                            QQC2.ToolTip.visible: containsMouse
                        }
                    }
                }

                // ── Tab bar ───────────────────────────────────────────────────
                // Underline instead of a solid sand fill: the selected tab was
                // the highest-contrast element in the popup, for information
                // worth one word.
                Item {
                    Layout.fillWidth: true
                    implicitHeight: tabRow.implicitHeight

                    RowLayout {
                        id: tabRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Kirigami.Units.smallSpacing
                        spacing: 0

                        Repeater {
                            model: root.tabLabels
                            delegate: Item {
                                id: tabItem
                                required property int index
                                required property string modelData

                                readonly property bool active: root.activeTab === tabItem.index
                                readonly property bool healthy: {
                                    if (tabItem.index < root.providersData.length)
                                        return root.providersData[tabItem.index].ok !== false
                                    return root.ollamaOk
                                }

                                implicitWidth: tabContent.implicitWidth
                                               + Kirigami.Units.smallSpacing * 4
                                implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.5)

                                RowLayout {
                                    id: tabContent
                                    anchors.centerIn: parent
                                    spacing: Kirigami.Units.smallSpacing

                                    Rectangle {
                                        implicitWidth: Math.max(4, Math.round(Kirigami.Units.gridUnit * 0.28))
                                        implicitHeight: implicitWidth
                                        radius: implicitWidth / 2
                                        color: tabItem.healthy ? root.teal : root.red
                                    }
                                    Text {
                                        text: tabItem.modelData
                                        font.bold: true
                                        font.pixelSize: root.fsMicro
                                        font.family: "monospace"
                                        font.letterSpacing: 1.4
                                        color: tabItem.active ? root.sand
                                             : (tabArea.containsMouse ? root.text : root.textDim)
                                    }
                                }

                                Rectangle {
                                    visible: tabItem.active
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.leftMargin: Kirigami.Units.smallSpacing
                                    anchors.rightMargin: Kirigami.Units.smallSpacing
                                    height: 2
                                    color: root.sand
                                }

                                MouseArea {
                                    id: tabArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.activeTab = tabItem.index
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: root.line
                    }
                }

                // ── Content ───────────────────────────────────────────────────
                QQC2.ScrollView {
                    id: scroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: Kirigami.Units.smallSpacing * 2
                    clip: true

                    ColumnLayout {
                        width: scroll.availableWidth
                        spacing: Kirigami.Units.smallSpacing * 2

                        // ═══ QUOTA PROVIDER VIEW ═══
                        Loader {
                            active: root.activeTab < root.providersData.length
                            visible: active
                            Layout.fillWidth: true
                            sourceComponent: providerView
                        }

                        // ═══ OLLAMA VIEW ═══
                        Loader {
                            active: root.activeTab >= root.providersData.length
                            visible: active
                            Layout.fillWidth: true
                            sourceComponent: ollamaView
                        }
                    }
                }

                // ── Status bar ────────────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: root.line
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: Kirigami.Units.smallSpacing * 2
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing

                    Rectangle {
                        implicitWidth: Math.max(4, Math.round(Kirigami.Units.gridUnit * 0.33))
                        implicitHeight: implicitWidth
                        radius: implicitWidth / 2
                        color: root.daemonOk ? root.teal : root.red
                    }
                    Text {
                        text: root.freshnessText()
                        font.pixelSize: root.fsMicro
                        font.family: "monospace"
                        color: root.textDim
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "LLM CORP™"
                        font.pixelSize: root.fsMicro
                        font.bold: true
                        font.family: "monospace"
                        font.letterSpacing: 1.4
                        color: root.textDim
                        opacity: 0.55
                    }
                }
            }
        }
    }

    // ── Provider (quota) view ───────────────────────────────────────────────
    Component {
        id: providerView
        ColumnLayout {
            width: parent ? parent.width : 0
            spacing: Kirigami.Units.largeSpacing
            property var prov: root.providersData[root.activeTab] || ({})

            // Error banner (still show stale numbers below if any)
            Item {
                Layout.fillWidth: true
                visible: prov.ok === false
                implicitHeight: errTxt.implicitHeight + Kirigami.Units.smallSpacing * 3

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(root.red.r, root.red.g, root.red.b, 0.10)
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 2
                    color: root.red
                }
                Text {
                    id: errTxt
                    anchors.fill: parent
                    anchors.leftMargin: Kirigami.Units.smallSpacing * 2.5
                    anchors.rightMargin: Kirigami.Units.smallSpacing * 1.5
                    anchors.topMargin: Kirigami.Units.smallSpacing * 1.5
                    text: "⚠ " + (prov.error || "sin conexión")
                    wrapMode: Text.WordWrap
                    font.family: "monospace"
                    font.pixelSize: root.fsMicro
                    color: root.text
                }
            }

            Repeater {
                model: prov.windows || []
                delegate: QuotaBar {
                    required property int index
                    required property var modelData

                    Layout.fillWidth: true
                    Layout.bottomMargin: index === 0 ? Kirigami.Units.smallSpacing : 0
                    hero: index === 0
                    colText: root.text; colDim: root.textDim; colSand: root.sand
                    colLine: root.line; colTrack: root.surface2
                    colLow: root.teal; colWarn: root.amber; colHigh: root.red
                    label: modelData.label
                    utilization: modelData.utilization
                    resetsAt: modelData.resets_at || ""
                    windowSeconds: modelData.window_seconds || 0
                }
            }

            Text {
                visible: (prov.windows || []).length === 0 && prov.ok !== false
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                topPadding: Kirigami.Units.gridUnit
                text: "// SIN DATOS //"
                font.family: "monospace"
                font.pixelSize: root.fsSmall
                color: root.textDim
            }

            // Meta chips for this provider
            Flow {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: prov.meta && (prov.meta.tier || prov.meta.extra_usage)
                spacing: Kirigami.Units.smallSpacing

                Repeater {
                    model: {
                        var m = prov.meta || {}
                        var out = []
                        if (m.tier) out.push("tier " + String(m.tier).replace("_claude_ai", ""))
                        if (m.extra_usage) out.push("uso extra ON")
                        return out
                    }
                    delegate: Rectangle {
                        required property string modelData
                        implicitWidth: chipTxt.implicitWidth + Kirigami.Units.smallSpacing * 2.5
                        implicitHeight: Math.round(Kirigami.Units.gridUnit * 0.85)
                        color: "transparent"
                        border.color: root.line
                        border.width: 1
                        Text {
                            id: chipTxt
                            anchors.centerIn: parent
                            text: parent.modelData
                            font.family: "monospace"
                            font.pixelSize: root.fsMicro
                            color: root.textDim
                        }
                    }
                }
            }
        }
    }

    // ── Ollama view ──────────────────────────────────────────────────────────
    Component {
        id: ollamaView
        ColumnLayout {
            width: parent ? parent.width : 0
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: Kirigami.Units.smallSpacing * 1.5
                spacing: Kirigami.Units.smallSpacing

                Text {
                    text: root.ollamaModels.length + " MODELOS"
                    font.family: "monospace"
                    font.pixelSize: root.fsMicro
                    font.bold: true
                    font.letterSpacing: 1.4
                    color: root.sand
                }
                Text {
                    property int inRam: root.ollamaModels.filter(function (m) {
                        return m.loaded
                    }).length
                    text: "· " + inRam + " en RAM"
                    visible: root.ollamaModels.length > 0
                    font.family: "monospace"
                    font.pixelSize: root.fsMicro
                    color: root.textDim
                }
                Item { Layout.fillWidth: true }
                Text {
                    visible: !root.ollamaOk
                    text: "OLLAMA OFFLINE"
                    font.family: "monospace"
                    font.pixelSize: root.fsMicro
                    font.bold: true
                    color: root.red
                }
            }

            // Top hairline so the first row closes against the header.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: root.ollamaModels.length > 0 ? 1 : 0
                color: root.line
            }

            Repeater {
                model: root.ollamaModels
                delegate: ModelRow {
                    required property var modelData

                    Layout.fillWidth: true
                    colText: root.text; colDim: root.textDim; colSand: root.sand
                    colLine: root.line; colHover: root.surface2; colAccent: root.teal
                    name: modelData.name
                    paramSize: modelData.param_size || ""
                    quant: modelData.quant || ""
                    sizeBytes: modelData.size || 0
                    loaded: modelData.loaded
                    preferred: modelData.name === root.ollamaPreferred
                    busy: root.busyModels[modelData.name] !== undefined
                    onLoadRequested:   (n) => root.loadModel(n)
                    onUnloadRequested: (n) => root.unloadModel(n)
                    onPreferRequested: (n) => root.preferModel(n)
                }
            }

            Text {
                visible: root.ollamaModels.length === 0
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                topPadding: Kirigami.Units.gridUnit
                text: root.ollamaOk ? "// SIN MODELOS //" : "// OLLAMA NO RESPONDE //"
                font.family: "monospace"
                font.pixelSize: root.fsSmall
                color: root.textDim
            }
        }
    }

    // ── Polling ──────────────────────────────────────────────────────────────
    Timer {
        interval: root.expanded ? root.pollMs : root.idlePollMs
        running: true; repeat: true; triggeredOnStart: true
        onTriggered: { fetchProviders(); fetchOllama() }
    }

    // Keeps the "actualizado hace Xs" label ticking while the popup is open.
    Timer {
        interval: 1000; running: root.expanded; repeat: true
        onTriggered: root.nowMs = Date.now()
    }

    // Poll immediately when the popup opens instead of waiting out the idle tick.
    onExpandedChanged: if (expanded) { nowMs = Date.now(); fetchProviders(); fetchOllama() }

    // ── API ──────────────────────────────────────────────────────────────────
    function getJson(path, onOk, onFail) {
        const xhr = new XMLHttpRequest()
        xhr.open("GET", root.daemonUrl + path)
        xhr.timeout = 5000
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) onOk(JSON.parse(xhr.responseText))
            else if (onFail) onFail()
        }
        xhr.ontimeout = () => { if (onFail) onFail() }
        xhr.onerror   = () => { if (onFail) onFail() }
        xhr.send()
    }

    // `done` receives whether the request actually succeeded, and is guaranteed
    // to fire exactly once — including on timeout or a transport error, so a
    // caller can never be left waiting on a callback that never arrives.
    function postJson(path, body, done, timeoutMs) {
        const xhr = new XMLHttpRequest()
        var settled = false
        function settle(ok) {
            if (settled) return
            settled = true
            if (done) done(ok)
        }
        xhr.open("POST", root.daemonUrl + path)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.timeout = timeoutMs || 8000
        xhr.onreadystatechange = () => {
            if (xhr.readyState === XMLHttpRequest.DONE)
                settle(xhr.status >= 200 && xhr.status < 300)
        }
        xhr.ontimeout = () => settle(false)
        xhr.onerror   = () => settle(false)
        xhr.send(JSON.stringify(body || {}))
    }

    /* Force a real re-query instead of re-reading the daemon's cache.
     *
     * GET /providers only returns the last snapshot, which the daemon refreshes
     * on its own 180s loop — so refreshing with a GET can hand back numbers
     * minutes old and look like the button does nothing. POST /refresh makes
     * the daemon hit the provider APIs now (skipping its rate-limit backoff)
     * and answer with the fresh snapshot.
     */
    function forceRefresh() {
        if (root.refreshing) return
        root.refreshing = true
        postJson("/refresh", {}, (ok) => {
            root.refreshing = false
            if (!ok) { root.failStreak = 2; root.daemonOk = false }
            fetchProviders()
            fetchOllama()
        }, 20000)   // a cold provider call can outlast the default timeout
    }

    function fetchProviders() {
        getJson("/providers", (data) => {
            root.daemonOk = true
            root.failStreak = 0
            root.lastUpdate = Date.now()
            root.nowMs = root.lastUpdate
            root.providersData = data
            var labels = data.map((p) => (p.label || p.id).toUpperCase())
            labels.push("OLLAMA")
            root.tabLabels = labels
        }, () => {
            // One dropped request is usually a slow reply, not a dead daemon.
            // Only flip the whole popup to "offline" after two in a row.
            root.failStreak++
            if (root.failStreak >= 2) root.daemonOk = false
        })
    }

    function freshnessText() {
        if (root.refreshing) return "actualizando…"
        if (!root.lastUpdate) return ""
        var secs = Math.max(0, Math.round((root.nowMs - root.lastUpdate) / 1000))
        if (secs < 60) return "actualizado hace " + secs + " s"
        return "actualizado hace " + Math.floor(secs / 60) + " min"
    }

    function fetchOllama() {
        getJson("/ollama/models", (data) => {
            root.ollamaOk = data.ok !== false
            root.ollamaModels = data.models || []
            root.ollamaPreferred = data.preferred || ""
            // Clear busy flags whose expected state has been reached
            var busy = root.busyModels
            var changed = false
            for (var i = 0; i < root.ollamaModels.length; i++) {
                var m = root.ollamaModels[i]
                if (busy[m.name] !== undefined && m.loaded === busy[m.name]) {
                    delete busy[m.name]; changed = true
                }
            }
            if (changed) root.busyModels = busy
        }, () => { root.ollamaOk = false })
    }

    function markBusy(name, expected) {
        var b = root.busyModels
        b[name] = expected
        root.busyModels = Object.assign({}, b)
    }

    function loadModel(name) {
        markBusy(name, true)
        postJson("/ollama/load", { name: name }, () => fetchOllama())
    }

    function unloadModel(name) {
        markBusy(name, false)
        postJson("/ollama/unload", { name: name }, () => fetchOllama())
    }

    function preferModel(name) {
        root.ollamaPreferred = name  // optimistic
        postJson("/ollama/preferred", { name: name }, () => fetchOllama())
    }
}
