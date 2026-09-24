import QtQuick
import qs.Commons
import "../components" as UI
import "../theme" as T

// The Documents section's list, fed from the documents store. The wrapper is a
// Column so the list keeps sizing itself, exactly as it did in the panel.
Column {
  id: documentsScreen

  property var app
  property var navigator
  property var theme: T.Theme {}

  // The panel scrolls; a row that takes the cursor asks for it here.
  signal revealRequested(var item)

  visible: documentsScreen.app.nav.viewMode === "documents" && !!documentsScreen.app.projects.selectedProject

  UI.DocumentsView {
    width: parent.width
    docs: documentsScreen.app.docs.filteredDocs
    query: documentsScreen.app.nav.searchQuery
    activeCategory: documentsScreen.app.docs.docCategory
    cursorIndex: documentsScreen.app.nav.cursorIndex
    loading: documentsScreen.app.docs.docsLoading
    error: documentsScreen.app.docs.docsError
    truncated: documentsScreen.app.docs.docsTruncated
    scrollOnCursor: documentsScreen.app.nav.scrollOnCursor
    theme: documentsScreen.theme
    onDocChosen: function(path) { documentsScreen.navigator.openDoc(path) }
    onHovered: function(index) { documentsScreen.navigator.hoverCursor(index) }
    onRevealRequested: function(item) { documentsScreen.revealRequested(item) }
  }
}
