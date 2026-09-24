import QtQuick
import qs.Commons
import "../theme" as T

// A small coloured pill: the tint at 18% behind the tint-coloured caption.
Rectangle {
  id: badge

  property var theme: T.Theme {}
  property string text: ""
  property color tint: badge.theme.dim
  // The badges in the lists are tighter than the one in a memory's header.
  property real paddingY: Style.space(2)
  property alias textObjectName: label.objectName

  width: label.implicitWidth + Style.space(12)
  height: label.implicitHeight + badge.paddingY
  radius: height / 2
  color: Qt.alpha(label.color, 0.18)

  Text {
    id: label
    anchors.centerIn: parent
    text: badge.text
    color: badge.tint
    font.family: badge.theme.fontFamily
    font.pixelSize: badge.theme.captionSize
  }
}
