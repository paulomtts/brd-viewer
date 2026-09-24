import QtQuick
import qs.Commons
import "../../core/domain/board.js" as Board
import "../theme" as T

// One small circle per subtask, in the board's own status colours, with
// whatever does not fit collapsed into a "+N". The in-progress ones fade in and
// out together; every other status is static.
//
// The animation runs ONLY while this row is visible and holds an in-progress
// pip, so a graph of finished (or unstarted) work animates nothing at all.
Row {
  id: pips

  // [{ id, status }], one entry per subtask the node shows.
  property var model: []
  // How many subtasks the entries above leave out; 0 draws no "+N".
  property int more: 0
  // The owner's Theme, or none: `palette` then falls back to this row's own.
  property var theme: null

  readonly property var palette: pips.theme || pipsTheme

  readonly property bool hasInProgress: (pips.model || []).some(function(pip) {
    return pip && pip.status === "in_progress"
  })
  readonly property bool pulsing: pulse.running

  // What an in-progress pip's opacity follows. 1 whenever nothing is running,
  // so a stopped animation never leaves a pip faded.
  property real pulseOpacity: 1

  spacing: Style.space(4)
  visible: (pips.model || []).length > 0 || pips.more > 0

  SequentialAnimation {
    id: pulse
    running: pips.visible && pips.hasInProgress
    loops: Animation.Infinite
    NumberAnimation { target: pips; property: "pulseOpacity"; from: 1; to: 0.3; duration: 800; easing.type: Easing.InOutSine }
    NumberAnimation { target: pips; property: "pulseOpacity"; from: 0.3; to: 1; duration: 800; easing.type: Easing.InOutSine }
    onRunningChanged: if (!running) pips.pulseOpacity = 1
  }

  Repeater {
    model: pips.model

    delegate: Rectangle {
      id: pip
      required property var modelData

      objectName: "statusPip" + (pip.modelData ? pip.modelData.id : "")
      width: Style.space(8)
      height: width
      radius: height / 2
      anchors.verticalCenter: parent ? parent.verticalCenter : undefined
      color: Board.statusColor(pip.modelData ? pip.modelData.status : "",
                               pips.palette ? pips.palette.dim : Color.foreground)
      opacity: (pip.modelData && pip.modelData.status === "in_progress") ? pips.pulseOpacity : 1
    }
  }

  ThemedText {
    objectName: "statusPipsMore"
    variant: "caption"
    theme: pips.palette
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    visible: pips.more > 0
    text: "+" + pips.more
  }

  T.Theme { id: pipsTheme }
}
