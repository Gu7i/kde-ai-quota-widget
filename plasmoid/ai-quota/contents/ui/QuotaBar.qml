import QtQuick
import QtQuick.Layouts

// A single utilization window (e.g. "5 horas — 60%") rendered as a labelled
// progress bar with a reset hint. Fill shifts teal → sand → red as it fills.
ColumnLayout {
    id: bar

    property string label: ""
    property real   utilization: 0        // 0..100
    property string resetsAt: ""          // ISO-8601 or ""

    property color colText: "#C1AB85"     // labels / reset hint
    property color colLine: "#3E6868"     // track border
    property color colLow:  "#3E6868"     // teal — low usage
    property color colWarn: "#C1AB85"     // sand — mid usage
    property color colHigh: "#C94E44"     // red  — high usage

    spacing: 2

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
        var h = Math.floor(mins / 60)
        var m = mins % 60
        var when = h > 0 ? (h + "h " + m + "m") : (m + "m")
        return "reinicia en " + when
    }

    RowLayout {
        Layout.fillWidth: true
        Text {
            text: bar.label.toUpperCase()
            font.family: "monospace"
            font.pixelSize: 10
            font.bold: true
            font.letterSpacing: 1
            color: bar.colText
        }
        Item { Layout.fillWidth: true }
        Text {
            text: Math.round(bar.utilization) + "%"
            font.family: "monospace"
            font.pixelSize: 12
            font.bold: true
            color: bar.fillColor()
        }
    }

    // Track + fill
    Rectangle {
        Layout.fillWidth: true
        height: 12
        color: "transparent"
        border.color: bar.colLine
        border.width: 1

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 2
            width: Math.max(0, (parent.width - 4) * Math.min(100, bar.utilization) / 100)
            color: bar.fillColor()
            Behavior on width { NumberAnimation { duration: 300 } }
        }
    }

    Text {
        text: bar.resetText()
        visible: text.length > 0
        font.family: "monospace"
        font.pixelSize: 8
        color: bar.colText
        opacity: 0.55
    }
}
