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

  UI.ChipRow {
    objectName: "memoryChips"
    visible: view.types.length > 0 && !view.loading && view.error === ""
    width: parent.width
    theme: view.theme
    chipPrefix: "memoryChip"
    active: view.activeType
    model: view.types.map(function(type) {
      return {
        id: type.id,
        label: type.label,
        count: type.count,
        tint: Memories.memoryTypeColor(type.id, view.dim)
      }
    })
    onChosen: function(id) { view.typeToggled(id) }
  }

  UI.ListStatus {
    objectName: "memoriesMessage"
    theme: view.theme
    width: parent.width
    loading: view.loading
    loadingText: "Loading memories…"
    error: view.error
    empty: !view.found || view.notes.length === 0
    filtered: view.found && (view.query !== "" || view.activeType !== "")
    filteredText: view.query !== "" ? "No memories match “" + view.query + "”."
      : "No " + Memories.memoryTypeLabel(view.activeType) + " memories."
    emptyText: !view.found ? "Claude Code has no memory for this project yet."
      : "No memories yet. Use ＋ New to add one."
  }

  Repeater {
    model: view.loading || view.error !== "" ? [] : view.notes
    delegate: NoteRow {}
  }

  component NoteRow: UI.ListRow {
    id: row
    required property var modelData
    required index
    objectName: "memoryRow" + row.index

    width: view.width
    theme: view.theme
    cursorIndex: view.cursorIndex
    scrollOnCursor: view.scrollOnCursor
    onHovered: function(index) { view.hovered(index) }
    onActivated: view.noteChosen(row.modelData.file)
    onRevealRequested: function(item) { view.revealRequested(item) }

    Row {
      width: parent.width
      spacing: Style.space(8)

      UI.ThemedText {
        objectName: "memoryRowTitle" + row.index
        theme: view.theme
        width: Math.max(0, parent.width - badge.width - parent.spacing)
        text: row.modelData.name
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

    UI.ThemedText {
      objectName: "memoryRowDescription" + row.index
      variant: "caption"
      theme: view.theme
      visible: text !== ""
      width: parent.width
      text: row.modelData.description
      elide: Text.ElideRight
    }
  }
}
