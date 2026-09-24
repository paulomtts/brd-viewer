import QtQuick
import qs.Commons
import "../../core/domain/documents.js" as Documents
import "../components" as UI
import "../theme" as T

// The Documents pieces that belong to the panel's FIXED toolbar rather than to
// the scrolling content: the category filter chips of the list, and the path
// and type picker of an open document. It reads the documents store and calls
// it; it owns no state of its own.
Column {
  id: bar

  property var app
  property var theme: T.Theme {}

  readonly property bool listMode: bar.app.nav.viewMode === "documents"
  readonly property bool docMode: bar.app.nav.viewMode === "document"
  readonly property var categories: Documents.docCategoryCounts(bar.app.docs.docs)
  // The merged entry of the open document: what says whether brd knows it.
  readonly property var selectedEntry: ({ brd: bar.app.docs.selectedDocBrd })

  visible: bar.listMode || bar.docMode
  spacing: Style.space(6)

  UI.ChipRow {
    objectName: "docChips"
    visible: bar.listMode && bar.categories.length > 0 && !bar.app.docs.docsLoading && bar.app.docs.docsError === ""
    width: parent.width
    theme: bar.theme
    chipPrefix: "docChip"
    active: bar.app.docs.docCategory
    model: bar.categories.map(function(category) {
      return {
        id: category.id,
        label: category.label,
        count: category.count,
        tint: Documents.docCategoryColor(category.id, bar.theme.dim)
      }
    })
    onChosen: function(id) { bar.app.docs.toggleDocCategory(id) }
  }

  UI.ThemedText {
    objectName: "docPath"
    variant: "caption"
    theme: bar.theme
    visible: bar.docMode
    width: parent.width
    text: bar.app.docs.selectedDocPath
    elide: Text.ElideMiddle
  }

  // brd's backup of the open document, and brd's own tags -- separate from the
  // type picker below, which writes the document's own frontmatter tag.
  UI.ThemedText {
    objectName: "docBrdState"
    variant: "caption"
    theme: bar.theme
    visible: bar.docMode && text !== ""
    width: parent.width
    text: Documents.brdStateLabel(bar.selectedEntry)
    color: bar.theme.dim
  }

  UI.ThemedText {
    objectName: "docBrdTags"
    variant: "caption"
    theme: bar.theme
    visible: bar.docMode && text !== ""
    width: parent.width
    text: bar.app.docs.selectedDocBrd ? bar.app.docs.selectedDocBrd.tags.join(" · ") : ""
    color: bar.theme.dim
    elide: Text.ElideRight
  }

  UI.TagPicker {
    visible: bar.docMode
    width: parent.width
    current: bar.app.docs.selectedDocCategory
    busy: bar.app.docs.docTagBusy
    error: bar.app.docs.docTagError
    theme: bar.theme
    onTagChosen: function(id) { bar.app.docs.setDocTag(id) }
  }
}
