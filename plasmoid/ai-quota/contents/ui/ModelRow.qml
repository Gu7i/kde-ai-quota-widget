import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// One Ollama model. A boxed grid of bordered cards made five models look like
// five competing objects, so the row is now a list item: hairline separators,
// and the preferred model marked by an accent stripe you can actually see
// instead of an 18%-opacity tint.
Rectangle {
    id: row

    property string name: ""
    property string paramSize: ""
    property string quant: ""
    property double sizeBytes: 0
    property bool   loaded: false
    property bool   preferred: false
    property bool   busy: false

    property color colText: "#E8DFCB"
    property color colDim:  "#9A917D"
    property color colSand: "#C1AB85"
    property color colLine: "#3A362E"
    property color colHover: "#282622"
    property color colAccent: "#6FA6A0"

    signal loadRequested(string name)
    signal unloadRequested(string name)
    signal preferRequested(string name)

    readonly property int fsMicro: Math.round(Kirigami.Units.gridUnit * 0.5)
    readonly property int fsSmall: Math.round(Kirigami.Units.gridUnit * 0.58)
    readonly property int fsBase:  Math.round(Kirigami.Units.gridUnit * 0.66)

    Layout.fillWidth: true
    implicitHeight: Math.round(Kirigami.Units.gridUnit * 2.4)
    color: preferred ? Qt.rgba(colSand.r, colSand.g, colSand.b, 0.08) : "transparent"

    function sizeGb() {
        if (!sizeBytes) return ""
        return (sizeBytes / 1e9).toFixed(1) + " GB"
    }

    // Preferred stripe
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 2
        color: row.preferred ? row.colSand : "transparent"
    }

    // Separator
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: row.colLine
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.smallSpacing * 2
        anchors.rightMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing * 2

        Text {
            text: row.preferred ? "★" : "☆"
            font.pixelSize: row.fsBase
            color: row.preferred ? row.colSand : row.colDim
            MouseArea {
                anchors.fill: parent
                anchors.margins: -Kirigami.Units.smallSpacing
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: row.preferRequested(row.name)
                QQC2.ToolTip.text: "Marcar como preferido"
                QQC2.ToolTip.visible: containsMouse
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text {
                Layout.fillWidth: true
                text: row.name
                font.family: "monospace"
                font.pixelSize: row.fsSmall
                font.bold: true
                color: row.colText
                elide: Text.ElideRight
            }
            Text {
                text: [row.paramSize, row.quant, row.sizeGb()]
                      .filter(function (x) { return x }).join(" · ")
                font.family: "monospace"
                font.pixelSize: row.fsMicro
                color: row.colDim
            }
        }

        // Resident badge — outlined, so it reads as a state and not as a button.
        Rectangle {
            visible: row.loaded
            implicitWidth: residentTxt.implicitWidth + Kirigami.Units.smallSpacing * 2.5
            implicitHeight: Math.round(Kirigami.Units.gridUnit * 0.85)
            color: "transparent"
            border.color: row.colAccent
            border.width: 1
            Text {
                id: residentTxt
                anchors.centerIn: parent
                text: "EN RAM"
                font.family: "monospace"
                font.pixelSize: row.fsMicro
                font.bold: true
                font.letterSpacing: 1
                color: row.colAccent
            }
        }

        Rectangle {
            implicitWidth: Math.round(Kirigami.Units.gridUnit * 3.9)
            implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.25)
            color: actArea.containsMouse && !row.busy ? row.colHover : "transparent"
            border.color: row.loaded || actArea.containsMouse ? row.colSand : row.colLine
            border.width: 1
            opacity: row.busy ? 0.5 : 1

            Text {
                anchors.centerIn: parent
                text: row.busy ? "···" : (row.loaded ? "LIBERAR" : "CARGAR")
                font.family: "monospace"
                font.pixelSize: row.fsMicro
                font.bold: true
                font.letterSpacing: 1
                color: row.loaded ? row.colSand : row.colDim
            }

            MouseArea {
                id: actArea
                anchors.fill: parent
                enabled: !row.busy
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: row.loaded ? row.unloadRequested(row.name)
                                      : row.loadRequested(row.name)
            }
        }
    }
}
