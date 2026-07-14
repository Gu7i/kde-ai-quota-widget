import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property string daemonUrl: "http://127.0.0.1:7183"
    readonly property int pollMs: 8000

    // ── Palette — American-vintage dark ───────────────────────────────────────
    readonly property color bg:   "#201F1D"   // warm charcoal popup background
    readonly property color text: "#C1AB85"   // sand — primary text & thin lines
    readonly property color teal: "#3E6868"   // structural accent / low usage
    readonly property color red:  "#C94E44"   // danger / high usage

    // ── State ─────────────────────────────────────────────────────────────────
    property var  providersData: []      // quota snapshots from /providers
    property var  ollamaModels: []
    property string ollamaPreferred: ""
    property bool ollamaOk: false
    property bool daemonOk: false
    property int  activeTab: 0
    property var  tabLabels: ["OLLAMA"]
    property var  busyModels: ({})        // name -> expected loaded state

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
        if (u >= 70) return text
        return teal
    }

    // ── Compact (panel) ───────────────────────────────────────────────────────
    compactRepresentation: Item {
        Kirigami.Icon {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height)
            height: width
            source: Qt.resolvedUrl("../icons/ai-neural.svg")
            isMask: true
            color: Kirigami.Theme.textColor
            opacity: root.daemonOk ? 1 : 0.4
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
                anchors.margins: 10
                spacing: 6

                // ── Header ────────────────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Column {
                        spacing: 1
                        RowLayout {
                            spacing: 5
                            Text {
                                text: "AI·QUOTA"
                                font.bold: true
                                font.pixelSize: 22
                                font.family: "monospace"
                                font.letterSpacing: 2
                                color: root.text
                            }
                            Rectangle {
                                width: 5; height: 5; radius: 3
                                color: root.daemonOk ? root.teal : root.red
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }
                        Text {
                            text: {
                                var plan = ""
                                if (root.providersData.length > 0 && root.providersData[0].meta)
                                    plan = (root.providersData[0].meta.plan || "").toUpperCase()
                                return "PLAN " + (plan || "—")
                            }
                            font.pixelSize: 9
                            font.family: "monospace"
                            color: root.text
                            opacity: 0.5
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        visible: !root.daemonOk
                        text: "DAEMON OFFLINE"
                        font.pixelSize: 9
                        font.bold: true
                        font.family: "monospace"
                        color: root.red
                    }

                    Rectangle {
                        width: 28; height: 28
                        color: "transparent"
                        border.color: root.teal
                        border.width: 1
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { fetchProviders(); fetchOllama() }
                            hoverEnabled: true
                            QQC2.ToolTip.text: "Actualizar"
                            QQC2.ToolTip.visible: containsMouse
                            Text {
                                anchors.centerIn: parent
                                text: "↺"
                                font.pixelSize: 16
                                font.bold: true
                                color: root.text
                            }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: root.text; opacity: 0.2 }

                // ── Tab bar ───────────────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    Repeater {
                        model: root.tabLabels
                        delegate: Rectangle {
                            property bool active: root.activeTab === index
                            Layout.fillWidth: true
                            height: 22
                            color: active ? root.text : "transparent"
                            border.color: root.teal
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: modelData
                                font.bold: true
                                font.pixelSize: 9
                                font.family: "monospace"
                                font.letterSpacing: 1
                                color: active ? root.bg : root.text
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.activeTab = index
                            }
                        }
                    }
                }

                // ── Content ───────────────────────────────────────────────────
                QQC2.ScrollView {
                    id: scroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    ColumnLayout {
                        width: scroll.availableWidth
                        spacing: 8

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

                Rectangle { Layout.fillWidth: true; height: 1; color: root.text; opacity: 0.2 }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "#3E6868"
                        font.pixelSize: 8; font.family: "monospace"
                        color: root.text; opacity: 0.4
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "LLM CORP™"
                        font.pixelSize: 8; font.bold: true; font.family: "monospace"
                        color: root.text; opacity: 0.4
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
            spacing: 8
            property var prov: root.providersData[root.activeTab] || ({})

            // Error banner (still show stale numbers below if any)
            Rectangle {
                Layout.fillWidth: true
                visible: prov.ok === false
                color: "transparent"
                border.color: root.red
                border.width: 1
                implicitHeight: errTxt.implicitHeight + 10
                Text {
                    id: errTxt
                    anchors.fill: parent
                    anchors.margins: 5
                    text: "⚠ " + (prov.error || "sin conexión")
                    wrapMode: Text.WordWrap
                    font.family: "monospace"; font.pixelSize: 9
                    color: root.red
                }
            }

            Repeater {
                model: prov.windows || []
                delegate: QuotaBar {
                    Layout.fillWidth: true
                    colText: root.text; colLine: root.teal
                    colLow: root.teal; colWarn: root.text; colHigh: root.red
                    label: modelData.label
                    utilization: modelData.utilization
                    resetsAt: modelData.resets_at || ""
                }
            }

            Text {
                visible: (prov.windows || []).length === 0 && prov.ok !== false
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                topPadding: Kirigami.Units.gridUnit
                text: "// SIN DATOS //"
                font.family: "monospace"; font.pixelSize: 10
                color: root.text; opacity: 0.45
            }

            // Meta footer for this provider
            Text {
                visible: prov.meta && (prov.meta.tier || prov.meta.extra_usage)
                Layout.fillWidth: true
                text: {
                    var m = prov.meta || {}
                    var parts = []
                    if (m.tier) parts.push("tier: " + m.tier)
                    if (m.extra_usage) parts.push("uso extra: ON")
                    return parts.join("   ·   ")
                }
                font.family: "monospace"; font.pixelSize: 8
                color: root.text; opacity: 0.5
            }
        }
    }

    // ── Ollama view ──────────────────────────────────────────────────────────
    Component {
        id: ollamaView
        ColumnLayout {
            width: parent ? parent.width : 0
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: root.ollamaModels.length + " MODELOS"
                    font.family: "monospace"; font.pixelSize: 9; font.bold: true
                    font.letterSpacing: 1; color: root.text
                }
                Item { Layout.fillWidth: true }
                Text {
                    visible: !root.ollamaOk
                    text: "OLLAMA OFFLINE"
                    font.family: "monospace"; font.pixelSize: 9; font.bold: true
                    color: root.red
                }
            }

            Repeater {
                model: root.ollamaModels
                delegate: ModelRow {
                    Layout.fillWidth: true
                    colBg: root.bg; colText: root.text; colLine: root.teal; colFill: root.text
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
                font.family: "monospace"; font.pixelSize: 10
                color: root.text; opacity: 0.45
            }
        }
    }

    // ── Polling ──────────────────────────────────────────────────────────────
    Timer {
        interval: root.pollMs; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { fetchProviders(); fetchOllama() }
    }

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

    function postJson(path, body, done) {
        const xhr = new XMLHttpRequest()
        xhr.open("POST", root.daemonUrl + path)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.timeout = 8000
        xhr.onreadystatechange = () => {
            if (xhr.readyState === XMLHttpRequest.DONE && done) done()
        }
        xhr.send(JSON.stringify(body || {}))
    }

    function fetchProviders() {
        getJson("/providers", (data) => {
            root.daemonOk = true
            root.providersData = data
            var labels = data.map((p) => (p.label || p.id).toUpperCase())
            labels.push("OLLAMA")
            root.tabLabels = labels
        }, () => { root.daemonOk = false })
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
