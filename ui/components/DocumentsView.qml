import QtQuick
import qs.Commons
import "../../core/domain/documents.js" as Documents
import "../components" as UI
import "../theme" as T

// The Documents section's list: one row per Markdown file (title, dim path).
// It renders and emits only; Panel.qml owns the list, the cursor and the query.
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
  property var categories: []
  property string activeCategory: ""
  property bool scrollOnCursor: false
  // The one input for every colour and font: Panel passes its Theme down,
  // and a standalone instance renders with the shell defaults.
  property var theme: T.Theme {}

  signal docChosen(string path)
  signal hovered(int index)
  signal revealRequested(var item)
  signal categoryToggled(string id)

  UI.FilterableList {
    width: parent.width
    theme: view.theme

    chipsObjectName: "docChips"
    chipPrefix: "docChip"
    activeChip: view.activeCategory
    chips: view.categories.map(function(category) {
      return {
        id: category.id,
        label: category.label,
        count: category.count,
        tint: Documents.docCategoryColor(category.id, view.theme.dim)
      }
    })
    onChipToggled: function(id) { view.categoryToggled(id) }

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
        width: Math.max(0, parent.width - (rowBadge.visible ? rowBadge.width + parent.spacing : 0))
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
    }

    UI.ThemedText {
      variant: "caption"
      theme: view.theme
      width: parent.width
      text: row.modelData.path
      elide: Text.ElideMiddle
    }
  }
}
