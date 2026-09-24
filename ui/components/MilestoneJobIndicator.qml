import QtQuick
import qs.Commons
import "../../core/domain/board.js" as Board
import "../components" as UI
import "../theme" as T

// The strip the Board toolbar shows instead of the ＋ New milestone button
// while a milestone job is alive: a spinning glyph, what is happening, how
// long it has taken and a way out. Once the job ends it becomes the result --
// a status word in the board's own status colours, the detail (the count or
// the error), the log path, and Dismiss.
//
// Presentation only: `state` (Item's own string property, used as plain text)
// is "" | "running" | "done" | "failed", and every button reports upwards.
Item {
  id: indicator
  objectName: "milestoneIndicator"

  property string label: "Creating milestone…"
  property string elapsed: ""
  property string detail: ""
  property string logPath: ""
  // How wide the owner's toolbar is. 0 (the default) means "no cap": every
  // piece of text keeps its natural width. When it is set, the detail and the
  // log path are elided to a share of it, so a long error or a deep log path
  // cannot push the row past the panel's edge.
  property real maxTextWidth: 0
  // The one input for every colour and font: Panel passes its Theme down,
  // and a standalone instance renders with the shell defaults.
  property var theme: T.Theme {}

  readonly property bool running: indicator.state === "running"
  readonly property bool ended: indicator.state === "done" || indicator.state === "failed"
  // The board's own status colours, so "done" reads the same here as on a card.
  readonly property color statusTint: indicator.state === "done"
    ? Board.statusColor("done", indicator.theme.foreground)
    : indicator.state === "failed" ? indicator.theme.urgent
    : indicator.theme.foreground

  signal cancelRequested()
  signal dismissRequested()

  visible: indicator.state !== ""
  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(8)

    // The line every child is as tall as, so the glyph, the words and the
    // buttons sit on one baseline without anchoring inside the Row.
    readonly property real lineHeight: spinner.implicitHeight

    UI.ActionButton {
      id: spinner
      objectName: "milestoneSpinner"
      visible: indicator.running
      theme: indicator.theme
      text: ""
      // U+F021, the refresh glyph the toolbar already uses; the shell's own
      // Button spins it for us.
      iconText: ""
      iconSpinning: true
      // A picture, not a control: never clickable, and never dimmed for it.
      enabled: false
      opacity: 1
    }

    UI.ThemedText {
      objectName: "milestoneStatus"
      theme: indicator.theme
      height: row.lineHeight
      verticalAlignment: Text.AlignVCenter
      text: indicator.state === "done" ? "Done"
        : indicator.state === "failed" ? "Failed"
        : indicator.label
      color: indicator.statusTint
      font.bold: indicator.ended
    }

    UI.ThemedText {
      objectName: "milestoneElapsed"
      variant: "caption"
      theme: indicator.theme
      visible: indicator.elapsed !== ""
      height: row.lineHeight
      verticalAlignment: Text.AlignVCenter
      text: indicator.elapsed
    }

    UI.ThemedText {
      id: detailText
      objectName: "milestoneDetail"
      variant: "caption"
      theme: indicator.theme
      visible: indicator.detail !== ""
      width: indicator.maxTextWidth > 0
        ? Math.min(detailText.implicitWidth, Math.max(Style.space(80), indicator.maxTextWidth * 0.35))
        : detailText.implicitWidth
      height: row.lineHeight
      verticalAlignment: Text.AlignVCenter
      text: indicator.detail
      elide: Text.ElideRight
    }

    UI.ThemedText {
      id: logText
      objectName: "milestoneLog"
      variant: "caption"
      theme: indicator.theme
      visible: indicator.logPath !== ""
      width: Math.min(Style.space(180), indicator.maxTextWidth > 0
        ? Math.max(Style.space(80), indicator.maxTextWidth * 0.3) : Style.space(180))
      height: row.lineHeight
      verticalAlignment: Text.AlignVCenter
      text: indicator.logPath
      elide: Text.ElideMiddle
    }

    UI.ActionButton {
      objectName: "milestoneCancel"
      visible: indicator.running
      theme: indicator.theme
      text: "Cancel"
      tone: "danger"
      onClicked: indicator.cancelRequested()
    }

    UI.ActionButton {
      objectName: "milestoneDismiss"
      visible: indicator.ended
      theme: indicator.theme
      text: "Dismiss"
      onClicked: indicator.dismissRequested()
    }
  }
}
