import QtQuick
import qs.Commons
import "../../core/domain/memories.js" as Memories
import "../components" as UI
import "../theme" as T

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
  // The one input for every colour and font: Panel passes its Theme down,
  // and a standalone instance renders with the shell defaults.
  property var theme: T.Theme {}

  signal noteChosen(string file)
  signal hovered(int index)
  signal revealRequested(var item)
  signal typeToggled(string id)

  UI.FilterableList {
    width: parent.width
    theme: view.theme

    chipsObjectName: "memoryChips"
    chipPrefix: "memoryChip"
    activeChip: view.activeType
    chips: view.types.map(function(type) {
      return {
        id: type.id,
        label: type.label,
        count: type.count,
        tint: Memories.memoryTypeColor(type.id, view.theme.dim)
      }
    })
    onChipToggled: function(id) { view.typeToggled(id) }

    statusObjectName: "memoriesMessage"
    loading: view.loading
    loadingText: "Loading memories…"
    error: view.error
    empty: !view.found || view.notes.length === 0
    filtered: view.found && (view.query !== "" || view.activeType !== "")
    filteredText: view.query !== "" ? "No memories match “" + view.query + "”."
      : "No " + Memories.memoryTypeLabel(view.activeType) + " memories."
    emptyText: !view.found ? "Claude Code has no memory for this project yet."
      : "No memories yet. Use ＋ New to add one."

    model: view.notes
    rowDelegate: Component { NoteRow {} }
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
        tint: Memories.memoryTypeColor(row.modelData.type, view.theme.dim)
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
