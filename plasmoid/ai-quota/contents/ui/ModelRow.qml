import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

// One Ollama model: name + specs on the left, a "preferred" star, a resident
// badge and a load/unload button on the right.
Rectangle {
    id: row

    property string name: ""
    property string paramSize: ""
    property string quant: ""
    property double sizeBytes: 0
    property bool   loaded: false
    property bool   preferred: false
    property bool   busy: false

    property color colBg:   "#201F1D"     // popup background (text on fills)
    property color colText: "#C1AB85"     // sand — primary text
    property color colLine: "#3E6868"     // teal — borders
    property color colFill: "#C1AB85"     // sand — resident badge / active

    signal loadRequested(string name)
    signal unloadRequested(string name)
    signal preferRequested(string name)

    Layout.fillWidth: true
    implicitHeight: 42
    color: preferred ? Qt.rgba(0.24, 0.41, 0.41, 0.18) : "transparent"
    border.color: colLine
    border.width: 1

    function sizeGb() {
        if (!sizeBytes) return ""
        return (sizeBytes / 1e9).toFixed(1) + " GB"
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 6
        spacing: 8

        // Preferred star
        Text {
            text: row.preferred ? "★" : "☆"
            font.pixelSize: 16
            color: row.colText
            opacity: row.preferred ? 1 : 0.4
            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                onClicked: row.preferRequested(row.name)
                QQC2.ToolTip.text: "Marcar como preferido"
                QQC2.ToolTip.visible: containsMouse
                hoverEnabled: true
            }
        }

        Column {
            Layout.fillWidth: true
            spacing: 1
            Text {
                text: row.name
                font.family: "monospace"
                font.pixelSize: 12
                font.bold: true
                color: row.colText
                elide: Text.ElideRight
                width: parent.width
            }
            Text {
                text: [row.paramSize, row.quant, row.sizeGb()].filter(function (x) { return x }).join("  ·  ")
                font.family: "monospace"
                font.pixelSize: 8
                color: row.colText
                opacity: 0.55
            }
        }

        // Resident badge
        Rectangle {
            visible: row.loaded
            width: residentTxt.width + 10
            height: 16
            color: row.colFill
            Text {
                id: residentTxt
                anchors.centerIn: parent
                text: "EN RAM"
                font.family: "monospace"
                font.pixelSize: 8
                font.bold: true
                font.letterSpacing: 1
                color: row.colBg
            }
        }

        // Load / unload button
        Rectangle {
            width: 68
            height: 22
            color: row.loaded ? row.colLine : "transparent"
            border.color: row.colLine
            border.width: 1
            opacity: row.busy ? 0.5 : 1

            Text {
                anchors.centerIn: parent
                text: row.busy ? "···" : (row.loaded ? "LIBERAR" : "CARGAR")
                font.family: "monospace"
                font.pixelSize: 9
                font.bold: true
                font.letterSpacing: 1
                color: row.colText
            }

            MouseArea {
                anchors.fill: parent
                enabled: !row.busy
                cursorShape: Qt.PointingHandCursor
                onClicked: row.loaded ? row.unloadRequested(row.name)
                                      : row.loadRequested(row.name)
            }
        }
    }
}
