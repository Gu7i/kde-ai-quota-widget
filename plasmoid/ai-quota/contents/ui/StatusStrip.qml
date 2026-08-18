import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// status.claude.com, condensed to a strip.
//
// This answers the one question the quota bars can't: when a request fails, is
// it your limit or theirs? So it stays out of the way while everything is
// operational (a single quiet line) and only grows — components, incident
// headline, latest update — once something is actually wrong.
ColumnLayout {
    id: strip

    property string indicator: "none"     // none | minor | major | critical | unknown
    property string description: ""       // "All Systems Operational", …
    property var    components: []        // [{name, status, primary}]
    property var    incidents: []         // [{name, status, impact, url, body}]
    property string pageUrl: "https://status.claude.com"
    property bool   stale: false          // last fetch failed; numbers are old
    property string error: ""

    // Palette, injected by main.qml so light and dark stay in one place.
    property color colText: "#E8DFCB"
    property color colDim:  "#9A917D"
    property color colSand: "#C1AB85"
    property color colLine: "#3A362E"
    property color colSurface: "#282622"
    property color colLow:  "#6FA6A0"
    property color colWarn: "#D8933D"
    property color colHigh: "#C94E44"

    readonly property int fsMicro: Math.round(Kirigami.Units.gridUnit * 0.5)
    readonly property int fsSmall: Math.round(Kirigami.Units.gridUnit * 0.58)

    readonly property bool healthy: indicator === "none"
    readonly property bool unknown: indicator === "unknown"

    // Degraded components are the useful detail; while everything is
    // operational the list is six rows saying nothing, so it stays collapsed.
    readonly property var troubled: components.filter(function (c) {
        return c.status !== "operational"
    })

    function severityColor() {
        if (strip.unknown) return colDim
        if (indicator === "critical" || indicator === "major") return colHigh
        if (indicator === "minor") return colWarn
        return colLow
    }

    // Statuspage speaks English; the rest of the widget doesn't.
    function stateText(s) {
        switch (s) {
        case "operational":          return "operativo"
        case "degraded_performance": return "rendimiento degradado"
        case "partial_outage":       return "caída parcial"
        case "major_outage":         return "caída total"
        case "under_maintenance":    return "en mantenimiento"
        default:                     return s
        }
    }

    function headlineText() {
        if (strip.unknown) return "ESTADO DESCONOCIDO"
        switch (indicator) {
        case "none":     return "TODO OPERATIVO"
        case "minor":    return "SERVICIO DEGRADADO"
        case "major":    return "INTERRUPCIÓN PARCIAL"
        case "critical": return "INTERRUPCIÓN GRAVE"
        default:         return String(indicator).toUpperCase()
        }
    }

    function incidentStateText(s) {
        switch (s) {
        case "investigating": return "investigando"
        case "identified":    return "identificado"
        case "monitoring":    return "monitorizando"
        case "resolved":      return "resuelto"
        default:              return s
        }
    }

    spacing: Math.round(Kirigami.Units.smallSpacing * 0.75)

    // ── Headline row ─────────────────────────────────────────────────────────
    Item {
        Layout.fillWidth: true
        implicitHeight: headRow.implicitHeight + Kirigami.Units.smallSpacing * 2

        // Tinted plate only when something is wrong — an "all clear" that
        // shouts is an "all clear" you stop reading.
        Rectangle {
            anchors.fill: parent
            visible: !strip.healthy
            color: Qt.rgba(strip.severityColor().r, strip.severityColor().g,
                           strip.severityColor().b, 0.10)
        }
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            visible: !strip.healthy
            width: 2
            color: strip.severityColor()
        }

        RowLayout {
            id: headRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: strip.healthy ? 0 : Kirigami.Units.smallSpacing * 2.5
            anchors.rightMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            Rectangle {
                implicitWidth: Math.max(4, Math.round(Kirigami.Units.gridUnit * 0.33))
                implicitHeight: implicitWidth
                radius: implicitWidth / 2
                color: strip.severityColor()
                opacity: strip.stale ? 0.5 : 1

                // A live incident earns a pulse; a healthy dot stays still.
                SequentialAnimation on opacity {
                    running: !strip.healthy && !strip.unknown && !strip.stale
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 900 }
                    NumberAnimation { to: 1.0;  duration: 900 }
                }
            }

            Text {
                text: strip.headlineText()
                font.family: "monospace"
                font.pixelSize: strip.fsMicro
                font.bold: true
                font.letterSpacing: 1.4
                color: strip.healthy || strip.unknown ? strip.colDim : strip.severityColor()
            }

            Item { Layout.fillWidth: true }

            // Link out to the full page — everything here is a summary.
            Text {
                id: linkTxt
                text: "status ↗"
                font.family: "monospace"
                font.pixelSize: strip.fsMicro
                color: linkArea.containsMouse ? strip.colSand : strip.colDim
                opacity: linkArea.containsMouse ? 1 : 0.7

                MouseArea {
                    id: linkArea
                    anchors.fill: parent
                    anchors.margins: -Kirigami.Units.smallSpacing
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Qt.openUrlExternally(strip.pageUrl)
                    QQC2.ToolTip.text: strip.pageUrl
                    QQC2.ToolTip.visible: containsMouse
                }
            }
        }
    }

    // ── Stale / unreachable note ─────────────────────────────────────────────
    Text {
        visible: strip.stale && strip.error.length > 0
        Layout.fillWidth: true
        Layout.leftMargin: strip.healthy ? 0 : Kirigami.Units.smallSpacing * 2.5
        text: "· estado sin actualizar (" + strip.error + ")"
        wrapMode: Text.WordWrap
        font.family: "monospace"
        font.pixelSize: strip.fsMicro
        color: strip.colDim
    }

    // ── Affected components ──────────────────────────────────────────────────
    Repeater {
        model: strip.troubled
        delegate: RowLayout {
            required property var modelData

            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing * 2.5
            spacing: Kirigami.Units.smallSpacing

            Text {
                text: modelData.name
                elide: Text.ElideRight
                Layout.maximumWidth: strip.width * 0.5
                font.family: "monospace"
                font.pixelSize: strip.fsMicro
                color: strip.colText
            }
            Text {
                text: "· " + strip.stateText(modelData.status)
                elide: Text.ElideRight
                Layout.fillWidth: true
                font.family: "monospace"
                font.pixelSize: strip.fsMicro
                color: strip.colDim
            }
        }
    }

    // ── Incidents ────────────────────────────────────────────────────────────
    Repeater {
        model: strip.incidents
        delegate: ColumnLayout {
            required property var modelData

            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing * 2.5
            Layout.topMargin: Kirigami.Units.smallSpacing
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: "⚠ " + modelData.name
                wrapMode: Text.WordWrap
                font.family: "monospace"
                font.pixelSize: strip.fsMicro
                font.bold: true
                color: incArea.containsMouse ? strip.colSand : strip.colText

                MouseArea {
                    id: incArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Qt.openUrlExternally(modelData.url || strip.pageUrl)
                    QQC2.ToolTip.text: "Abrir el incidente"
                    QQC2.ToolTip.visible: containsMouse
                }
            }

            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: {
                    var s = strip.incidentStateText(modelData.status)
                    var b = modelData.body || ""
                    return b ? (s + " — " + b) : s
                }
                wrapMode: Text.WordWrap
                // The latest update can be a paragraph; two lines is the most a
                // popup this size can spare before it stops being a summary.
                maximumLineCount: 3
                elide: Text.ElideRight
                font.family: "monospace"
                font.pixelSize: strip.fsMicro
                color: strip.colDim
            }
        }
    }

    // Hairline closing the strip off from the quota bars below.
    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        implicitHeight: 1
        color: strip.colLine
    }
}
