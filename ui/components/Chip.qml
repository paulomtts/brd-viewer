import QtQuick
import qs.Commons
import "../theme" as T

// A filter pill: the tint at 12% behind a caption, filled and bold while
// active. A busy chip is dimmed and swallows its clicks.
Rectangle {
  id: chip

  // The owner's Theme, or none: `palette` then falls back to the chip's own.
  // Both are objects, and tearing a view down nulls them while the bindings
  // below still run once, so every read of `palette` is guarded; the guard's
  // value is never painted.
  property var theme: null
  property string text: ""
  property color tint: chip.palette ? chip.palette.dim : Color.foreground
  property bool active: false
  property bool busy: false

  readonly property var palette: chip.theme || chipTheme

  signal clicked()

  opacity: chip.busy ? 0.5 : 1
  width: label.implicitWidth + Style.space(20)
  height: label.implicitHeight + Style.space(8)
  radius: height / 2
  color: chip.active ? Qt.alpha(chip.tint, 0.35) : Qt.alpha(chip.tint, 0.12)
  border.width: 1
  border.color: chip.active ? chip.tint : Qt.alpha(chip.tint, 0.4)

  Text {
    id: label
    anchors.centerIn: parent
    text: chip.text
    color: chip.palette ? chip.palette.foreground : Color.foreground
    font.family: chip.palette ? chip.palette.fontFamily : Style.font.family
    font.pixelSize: chip.palette ? chip.palette.captionSize : Style.font.caption
    font.bold: chip.active
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: if (!chip.busy) chip.clicked()
  }

  T.Theme { id: chipTheme }
}
