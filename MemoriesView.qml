import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "core/domain/memories.js" as Memories
import "ui/components" as UI
import "ui/theme" as T

// The Memories section's list: one row per memory note (name, description,
// type badge) under type filter chips. Renders and emits only; Panel.qml owns
// the list, the cursor, the query and the type filter.
Column {
  id: view
  objectName: "memoriesView"
  spacing: Style.space(6)

  property var notes: []
  property var types: []
  property string activeType: ""
  property string query: ""
  property int cursorIndex: -1
  property bool loading: false
  property bool found: true
  property string error: ""
  property bool scrollOnCursor: false
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.55)
  property string fontFamily: Style.font.family
  // What the shared components draw with; Panel still passes the colours one
  // by one, so the theme follows them.
  property var theme: T.Theme {
    foreground: view.foreground
    dim: view.dim
    fontFamily: view.fontFamily
  }

  signal noteChosen(string file)
  signal hovered(int index)
  signal revealRequested(var item)
  signal typeToggled(string id)

  Flow {
    objectName: "memoryChips"
    visible: view.types.length > 0 && !view.loading && view.error === ""
    width: parent.width
    spacing: Style.space(6)

    Repeater {
      model: view.types
      delegate: TypeChip {}
    }
  }

  Text {
    objectName: "memoriesMessage"
    visible: text !== ""
    width: parent.width
    text: view.loading ? "Loading memories…"
      : view.error !== "" ? view.error
      : !view.found ? "Claude Code has no memory for this project yet."
      : view.notes.length === 0 ? (view.query !== "" ? "No memories match “" + view.query + "”."
        : view.activeType !== "" ? "No " + Memories.memoryTypeLabel(view.activeType) + " memories."
        : "No memories yet. Use ＋ New to add one.")
      : ""
    color: view.dim
    font.family: view.fontFamily
    font.pixelSize: Style.font.body
    wrapMode: Text.WordWrap
  }

  Repeater {
    model: view.loading || view.error !== "" ? [] : view.notes
    delegate: NoteRow {}
  }

  component NoteRow: CursorSurface {
    id: row
    required property var modelData
    required property int index
    objectName: "memoryRow" + index

    width: view.width
    implicitHeight: rowColumn.implicitHeight + Style.spacing.rowPaddingX
    hasCursor: view.cursorIndex === index
    foreground: view.foreground
    onHasCursorChanged: if (hasCursor && view.scrollOnCursor) view.revealRequested(row)

    Column {
      id: rowColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(2)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          objectName: "memoryRowTitle" + row.index
          width: Math.max(0, parent.width - badge.width - parent.spacing)
          text: row.modelData.name
          color: view.foreground
          font.family: view.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        UI.Badge {
          id: badge
          theme: view.theme
          textObjectName: "memoryRowBadge" + row.index
          text: Memories.memoryTypeLabel(row.modelData.type)
          tint: Memories.memoryTypeColor(row.modelData.type, view.dim)
        }
      }

      Text {
        objectName: "memoryRowDescription" + row.index
        visible: text !== ""
        width: parent.width
        text: row.modelData.description
        color: view.dim
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: view.hovered(row.index)
      onClicked: view.noteChosen(row.modelData.file)
    }
  }

  component TypeChip: Rectangle {
    id: chip
    required property var modelData
    readonly property bool active: view.activeType === modelData.id
    readonly property color tint: Memories.memoryTypeColor(modelData.id, view.dim)
    property alias text: chipText.text
    objectName: "memoryChip" + modelData.id

    width: chipText.implicitWidth + Style.space(20)
    height: chipText.implicitHeight + Style.space(8)
    radius: height / 2
    color: active ? Qt.alpha(tint, 0.35) : Qt.alpha(tint, 0.12)
    border.width: 1
    border.color: active ? tint : Qt.alpha(tint, 0.4)

    Text {
      id: chipText
      anchors.centerIn: parent
      text: chip.modelData.label + " " + chip.modelData.count
      color: view.foreground
      font.family: view.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: chip.active
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: view.typeToggled(chip.modelData.id)
    }
  }
}
