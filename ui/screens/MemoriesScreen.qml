import QtQuick
import "../components" as UI
import "../theme" as T

// The Memories section's list, fed from the memories store. The wrapper is a
// Column so the list keeps sizing itself, exactly as it did in the panel.
Column {
  id: memoriesScreen

  property var app
  property var navigator
  property var theme: T.Theme {}

  // The panel scrolls; a row that takes the cursor asks for it here.
  signal revealRequested(var item)

  visible: memoriesScreen.app.nav.viewMode === "memories" && !!memoriesScreen.app.projects.selectedProject

  UI.MemoriesView {
    width: parent.width
    notes: memoriesScreen.app.memories.filteredMemories
    types: memoriesScreen.app.memories.memoryTypes
    activeType: memoriesScreen.app.memories.memoryType
    query: memoriesScreen.app.nav.searchQuery
    cursorIndex: memoriesScreen.app.nav.cursorIndex
    loading: memoriesScreen.app.memories.memoriesLoading
    found: memoriesScreen.app.memories.memoriesFound
    error: memoriesScreen.app.memories.memoriesError
    scrollOnCursor: memoriesScreen.app.nav.scrollOnCursor
    theme: memoriesScreen.theme
    onNoteChosen: function(file) { memoriesScreen.navigator.openMemory(file) }
    onHovered: function(index) { memoriesScreen.navigator.hoverCursor(index) }
    onRevealRequested: function(item) { memoriesScreen.revealRequested(item) }
    onTypeToggled: function(id) { memoriesScreen.app.memories.toggleMemoryType(id) }
  }
}
