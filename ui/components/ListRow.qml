import QtQuick
import qs.Commons
import qs.Ui
import "../theme" as T

// One row of a keyboard-navigable list: the cursor highlight, the reveal a
// keyboard move asks for, and the hover/click handling every list row in the
// panel shares. The declared children go into the row's content column.
CursorSurface {
  id: row

  // -1 means "not a row of the list": it never takes the cursor and never
  // reports a hover (the card detail's link rows use that for a link that is
  // not in the cursor's list).
  property int index: -1
  property int cursorIndex: -1
  property bool scrollOnCursor: false
  property var theme: null
  property real contentMargin: Style.space(10)
  property int hoverCursorShape: Qt.PointingHandCursor

  default property alias content: contentColumn.data
  readonly property var palette: row.theme || rowTheme

  signal hovered(int index)
  signal activated()
  signal revealRequested(var item)

  implicitHeight: contentColumn.implicitHeight + Style.spacing.rowPaddingX
  hasCursor: row.index >= 0 && row.cursorIndex === row.index
  foreground: row.palette ? row.palette.foreground : Color.foreground
  onHasCursorChanged: if (hasCursor && row.scrollOnCursor) row.revealRequested(row)

  Column {
    id: contentColumn
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: row.contentMargin
    anchors.rightMargin: row.contentMargin
    spacing: Style.space(2)
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: row.hoverCursorShape
    onEntered: if (row.index >= 0) row.hovered(row.index)
    onClicked: row.activated()
  }

  T.Theme { id: rowTheme }
}
