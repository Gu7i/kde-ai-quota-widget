import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// One utilization window. The first window of a provider is the reason you
// opened the popup, so it renders as a hero readout; the rest are compact rows
// underneath. Every size derives from Kirigami.Units.gridUnit, which follows
// the user's font DPI — nothing here is a hardcoded pixel.
ColumnLayout {
    id: bar

    property string label: ""
    property real   utilization: 0        // 0..100
    property string resetsAt: ""          // ISO-8601 or ""
    property real   windowSeconds: 0      // window length, for the pace hint
    property bool   hero: false

    // Palette, injected by main.qml so light and dark stay in one place.
    property color colText: "#E8DFCB"     // body ink
    property color colDim:  "#9A917D"     // secondary ink
    property color colSand: "#C1AB85"     // brand accent — labels
    property color colLine: "#3A362E"
    property color colTrack: "#282622"
    property color colLow:  "#6FA6A0"     // teal  — under 70
    property color colWarn: "#D8933D"     // amber — 70..90
    property color colHigh: "#C94E44"     // rust  — 90+

    readonly property int fsMicro: Math.round(Kirigami.Units.gridUnit * 0.5)
    readonly property int fsSmall: Math.round(Kirigami.Units.gridUnit * 0.58)
    readonly property int fsBase:  Math.round(Kirigami.Units.gridUnit * 0.7)
    readonly property int fsHero:  Math.round(Kirigami.Units.gridUnit * 2.5)

    spacing: Math.round(Kirigami.Units.smallSpacing * 0.75)

    function fillColor() {
        if (utilization >= 90) return colHigh
        if (utilization >= 70) return colWarn
        return colLow
    }

    function resetText() {
        if (!resetsAt) return ""
        var d = new Date(resetsAt)
        if (isNaN(d.getTime())) return ""
        var mins = Math.max(0, Math.round((d.getTime() - Date.now()) / 60000))
        var days = Math.floor(mins / 1440)
        var h = Math.floor((mins % 1440) / 60)
        var m = mins % 60
        var when = days > 0 ? (days + "d " + h + "h")
                            : (h > 0 ? (h + "h " + m + "m") : (m + "m"))
        return "reinicia en " + when
    }

    // Linear projection of where this window lands if usage keeps its current
    // pace. Held back until the window is 10% spent, where the extrapolation is
    // still wild enough to be noise rather than information.
    function paceText() {
        if (!windowSeconds || !resetsAt) return ""
        var d = new Date(resetsAt)
        if (isNaN(d.getTime())) return ""
        var remain = (d.getTime() - Date.now()) / 1000
        var elapsed = windowSeconds - remain
        if (elapsed <= windowSeconds * 0.1 || elapsed <= 0) return ""
        var projected = utilization * windowSeconds / elapsed
        if (projected >= 100) return "a este ritmo agotas el límite antes del reinicio"
        if (projected < 1) return ""
        return "a este ritmo llegas al " + Math.round(projected) + "%"
    }

    readonly property bool paceHot: {
        if (!windowSeconds || !resetsAt) return false
        var d = new Date(resetsAt)
        if (isNaN(d.getTime())) return false
        var remain = (d.getTime() - Date.now()) / 1000
        var elapsed = windowSeconds - remain
        if (elapsed <= windowSeconds * 0.1 || elapsed <= 0) return false
        return utilization * windowSeconds / elapsed >= 70
    }

    // ── Hero head ────────────────────────────────────────────────────────────
    RowLayout {
        visible: bar.hero
        Layout.fillWidth: true
        spacing: Kirigami.Units.largeSpacing

        RowLayout {
            spacing: 0
            Text {
                text: Math.round(bar.utilization)
                font.family: "monospace"
                font.pixelSize: bar.fsHero
                font.bold: true
                font.letterSpacing: -1
                color: bar.fillColor()
                Layout.alignment: Qt.AlignTop
            }
            Text {
                text: "%"
                font.family: "monospace"
                font.pixelSize: Math.round(bar.fsHero * 0.38)
                font.bold: true
                color: bar.fillColor()
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: Math.round(bar.fsHero * 0.08)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: 1
            Text {
                text: bar.label.toUpperCase()
                font.family: "monospace"
                font.pixelSize: bar.fsSmall
                font.bold: true
                font.letterSpacing: 1.4
                color: bar.colSand
            }
            Text {
                text: bar.resetText()
                visible: text.length > 0
                font.family: "monospace"
                font.pixelSize: bar.fsMicro
                color: bar.colDim
            }
            Text {
                text: bar.paceText()
                visible: text.length > 0
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.family: "monospace"
                font.pixelSize: bar.fsMicro
                color: bar.paceHot ? bar.colWarn : bar.colLow
            }
        }
    }

    // ── Compact head ─────────────────────────────────────────────────────────
    RowLayout {
        visible: !bar.hero
        Layout.fillWidth: true
        Text {
            text: bar.label.toUpperCase()
            font.family: "monospace"
            font.pixelSize: bar.fsSmall
            font.bold: true
            font.letterSpacing: 1.4
            color: bar.colSand
        }
        Item { Layout.fillWidth: true }
        Text {
            text: Math.round(bar.utilization) + "%"
            font.family: "monospace"
            font.pixelSize: bar.fsBase
            font.bold: true
            color: bar.fillColor()
        }
    }

    Gauge {
        Layout.fillWidth: true
        Layout.topMargin: bar.hero ? Kirigami.Units.smallSpacing : 0
        implicitHeight: bar.hero ? Math.round(Kirigami.Units.gridUnit * 0.55)
                                 : Math.round(Kirigami.Units.gridUnit * 0.34)
        value: bar.utilization
        fillColor: bar.fillColor()
        trackColor: bar.colTrack
        lineColor: bar.colLine
        critColor: bar.colHigh
    }

    // Scale legend, hero only — one reference is enough per popup.
    Item {
        visible: bar.hero
        Layout.fillWidth: true
        implicitHeight: bar.fsMicro + 2
        Text {
            anchors.left: parent.left
            text: "0"
            font.family: "monospace"; font.pixelSize: bar.fsMicro
            color: bar.colDim; opacity: 0.8
        }
        Text {
            x: Math.round(parent.width * 0.70) - width / 2
            text: "70"
            font.family: "monospace"; font.pixelSize: bar.fsMicro
            color: bar.colDim; opacity: 0.8
        }
        Text {
            x: Math.min(parent.width - width, Math.round(parent.width * 0.90) - width / 2)
            text: "90"
            font.family: "monospace"; font.pixelSize: bar.fsMicro
            color: bar.colHigh; opacity: 0.8
        }
    }

    // Compact rows keep their own reset hint under the bar.
    Text {
        visible: !bar.hero && text.length > 0
        text: bar.resetText()
        font.family: "monospace"
        font.pixelSize: bar.fsMicro
        color: bar.colDim
    }
}
