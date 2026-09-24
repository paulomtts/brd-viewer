import QtQuick
Item {
  property Item anchorItem; property var owner; property var bar; property bool open; property bool centerOnBar; property Item focusTarget
  property real screenW: 2000; property real screenH: 1000; property real verticalContentInset: 0; property real contentWidth; property real contentHeight
  function fittedContentWidth(w) { return w }
  function fittedContentHeight(a, b) { return Math.min(a, b) }
  width: 380; height: 560
}
