import QtQuick
import qs.Commons
import "../../core/domain/board.js" as Board
import "../../core/domain/documents.js" as Documents
import "../components" as UI
import "../theme" as T

// The Documents section's list: one row per Markdown file (title, dim path).
// It renders and emits only; Panel.qml owns the list, the cursor and the query,
// and the panel's fixed toolbar owns the category chips (DocumentsToolbar).
// `activeCategory` is still needed here: it words the empty-list message.
Column {
  id: view
  objectName: "documentsView"
  spacing: Style.space(6)

  property var docs: []
  property string query: ""
  property int cursorIndex: -1
  property bool loading: false
  property string error: ""
  property bool truncated: false
  property string activeCategory: ""
  property bool scrollOnCursor: false
  // The one input for every colour and font: Panel passes its Theme down,
  // and a standalone instance renders with the shell defaults.
  property var theme: T.Theme {}

  signal docChosen(string path)
  signal hovered(int index)
  signal revealRequested(var item)

  UI.FilterableList {
    width: parent.width
    theme: view.theme

    statusObjectName: "docsMessage"
    loading: view.loading
    loadingText: "Loading documents…"
    error: view.error
    empty: view.docs.length === 0
    filtered: view.query !== "" || view.activeCategory !== ""
    filteredText: view.query !== "" ? "No documents match “" + view.query + "”."
      : "No " + Documents.docCategoryLabel(view.activeCategory) + " documents."
    emptyText: "No Markdown documents found in this project."

    model: view.docs
    rowDelegate: Component { DocRow {} }
  }

  UI.ThemedText {
    objectName: "docsTruncated"
    variant: "caption"
    theme: view.theme
    visible: view.truncated
    width: parent.width
    text: "Showing the first 500 documents."
  }

  component DocRow: UI.ListRow {
    id: row
    required property var modelData
    required index
    objectName: "docRow" + row.index

    // A row brd has a backup of but disk does not: still listed, so the backup
    // stays discoverable, but dimmed -- there is nothing to open.
    opacity: row.modelData.missing === true ? 0.5 : 1
    width: view.width
    theme: view.theme
    cursorIndex: view.cursorIndex
    scrollOnCursor: view.scrollOnCursor
    onHovered: function(index) { view.hovered(index) }
    onActivated: view.docChosen(row.modelData.path)
    onRevealRequested: function(item) { view.revealRequested(item) }

    Row {
      width: parent.width
      spacing: Style.space(8)

      UI.ThemedText {
        theme: view.theme
        width: Math.max(0, parent.width - (rowBadge.visible ? rowBadge.width + parent.spacing : 0)
                                        - (brdBadge.visible ? brdBadge.width + parent.spacing : 0))
        text: row.modelData.title
        elide: Text.ElideRight
      }

      UI.Badge {
        id: rowBadge
        theme: view.theme
        textObjectName: "docRowBadge" + row.index
        visible: text !== ""
        text: Documents.docCategoryLabel(row.modelData.category)
        tint: Documents.docCategoryColor(row.modelData.category, view.theme.dim)
      }

      // brd knows this file: the badge warns when brd's copy no longer matches
      // what is on disk, in the hue the board already uses for blocked.
      UI.Badge {
        id: brdBadge
        theme: view.theme
        objectName: "docRowBrdBadge" + row.index
        textObjectName: "docRowBrd" + row.index
        property color warnColor: Board.statusColor("blocked", view.theme.dim)
        visible: !!row.modelData.brd
        text: row.modelData.brd ? "brd" : ""
        tint: (row.modelData.brd && row.modelData.brd.sourceState !== "ok") ? brdBadge.warnColor : view.theme.dim
      }
    }

    UI.ThemedText {
      variant: "caption"
      theme: view.theme
      width: parent.width
      text: row.modelData.path
      elide: Text.ElideMiddle
    }

    // brd's own tags, kept apart from the plugin's category badge above.
    UI.ThemedText {
      objectName: "docRowBrdTags" + row.index
      variant: "caption"
      theme: view.theme
      width: parent.width
      visible: text !== ""
      text: row.modelData.brd ? row.modelData.brd.tags.join(" · ") : ""
      color: view.theme.dim
      elide: Text.ElideRight
    }

    UI.ThemedText {
      objectName: "docRowMissing" + row.index
      variant: "caption"
      theme: view.theme
      visible: row.modelData.missing === true
      width: parent.width
      text: "missing on disk"
      color: view.theme.dim
    }
  }
}
