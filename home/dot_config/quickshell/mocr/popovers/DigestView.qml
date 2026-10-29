import QtQuick
import "../theme"
import "../services" as Services

// Read-only rendering of the newest local daily anomaly digest.
Item {
    id: digestView

    Text {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        text: Services.DigestService.available
              ? "DAILY DIGEST // " + Services.DigestService.latestDate
              : "DAILY DIGEST // NONE"
        color: Colors.cyan
        font.family: Geometry.fontFamily
        font.pixelSize: Geometry.fontSize
        font.weight: Font.Bold
        elide: Text.ElideRight
    }

    Rectangle {
        anchors.top: header.bottom
        anchors.topMargin: 6
        anchors.left: parent.left
        anchors.right: parent.right
        height: Geometry.borderWidth
        color: Colors.fg_dark
    }

    Text {
        anchors.centerIn: parent
        visible: !Services.DigestService.available
        text: "NO DIGESTS FOUND"
        color: Colors.fg_dark
        font.family: Geometry.fontFamily
        font.pixelSize: Geometry.fontSize
        font.weight: Geometry.fontWeight
    }

    Flickable {
        visible: Services.DigestService.available
        anchors.top: header.bottom
        anchors.topMargin: 12
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        contentWidth: width
        contentHeight: digestText.implicitHeight
        flickableDirection: Flickable.VerticalFlick

        Text {
            id: digestText
            width: parent.width
            text: Services.DigestService.latestText
            textFormat: Text.MarkdownText
            wrapMode: Text.WordWrap
            color: Colors.fg
            font.family: Geometry.fontFamily
            font.pixelSize: Geometry.fontSize
            font.weight: Geometry.fontWeight
        }
    }
}
