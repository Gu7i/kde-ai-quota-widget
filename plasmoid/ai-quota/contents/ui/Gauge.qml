import QtQuick

// A utilization track with the 70 / 90 thresholds marked on it.
//
// The fill color already changes at those two cut-offs, but a bare bar gives no
// way to tell 68% from 72% at a glance — the ticks make the rule the color is
// applying visible instead of implicit.
Item {
    id: g

    property real  value: 0               // 0..100
    property color fillColor: "#6FA6A0"
    property color trackColor: "#282622"
    property color lineColor: "#3A362E"
    property color critColor: "#C94E44"
    property bool  showTicks: true

    implicitHeight: 10

    Rectangle {
        id: track
        anchors.fill: parent
        color: g.trackColor
        border.color: g.lineColor
        border.width: 1

        Rectangle {
            x: 1
            y: 1
            height: parent.height - 2
            width: Math.max(0, (parent.width - 2)
                            * Math.min(100, Math.max(0, g.value)) / 100)
            color: g.fillColor
            Behavior on width {
                NumberAnimation { duration: 350; easing.type: Easing.OutCubic }
            }
        }
    }

    Repeater {
        model: g.showTicks ? [70, 90] : []
        delegate: Rectangle {
            required property int modelData
            x: Math.round(track.width * modelData / 100)
            y: -2
            width: 1
            height: g.height + 4
            color: modelData >= 90 ? g.critColor : g.lineColor
            opacity: modelData >= 90 ? 0.65 : 1
        }
    }
}
