import QtQuick
import "../components" as UI
import "../theme" as T

// One open memory note, fed from the memories store. The wrapper is a Column so
// the note keeps sizing itself, and it re-exposes the note's editor item: Panel
// focuses that while an edit is in progress.
Column {
  id: noteScreen

  property var app
  property var navigator
  property var theme: T.Theme {}

  // Panel's focusItem chain points here while a note is being edited.
  readonly property Item editorItem: memoryNote.editorItem

  visible: noteScreen.app.nav.viewMode === "memory" && !!noteScreen.app.projects.selectedProject

  UI.MemoryNoteView {
    id: memoryNote
    width: parent.width
    entry: noteScreen.app.memories.selectedMemoryEntry
    text: noteScreen.app.memories.memoryText
    readError: noteScreen.app.memories.memoryReadError
    editing: noteScreen.app.memories.memoryEditing
    draft: noteScreen.app.memories.memoryDraft
    busy: noteScreen.app.memories.memoryBusy
    error: noteScreen.app.memories.memoryOpError
    theme: noteScreen.theme
    onEditRequested: noteScreen.app.memories.startMemoryEdit()
    onDeleteRequested: noteScreen.app.memories.requestMemoryDelete()
    onSaveRequested: noteScreen.app.memories.saveMemory()
    onCancelEditRequested: noteScreen.app.memories.cancelMemoryEdit()
    onDraftEdited: function(text) { noteScreen.app.memories.memoryDraft = text }
    onEscapePressed: noteScreen.app.memories.memoryEscape()
  }
}
