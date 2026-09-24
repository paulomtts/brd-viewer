import QtQuick

// The ui-side navigation controller: where the panel is, what the cursor is on,
// and the return-stack bookkeeping around an open card, document or memory note.
// The stores hold the state; this file combines them with the scroll position
// and the focus. Everything that needs an Item is handed in -- `flick` (the
// Flickable, null in tests that do not need it) and `actions`
// (`focusForView()`, `scrollToTop()`, `scrollBy(px)`, `centerOnGraphNode(id)`)
// -- so the navigator never reaches back into Panel.qml.
QtObject {
  id: navi

  property var app: null
  property Item flick: null
  property var actions: null
  property bool documentsEnabled: true

  function currentList() {
    if (navi.app.nav.viewMode === "board") return navi.app.board.boardCards
    if (navi.app.nav.viewMode === "entry") return navi.app.board.detailLinkList
    if (navi.app.nav.viewMode === "documents") return navi.app.docs.filteredDocs
    if (navi.app.nav.viewMode === "memories") return navi.app.memories.filteredMemories
    return []
  }

  function resetSearch() {
    navi.app.nav.resetSearch()
  }

  function moveGraph(direction) {
    var next = navi.app.graph.moveGraph(direction)
    if (next === "") return
    navi.actions.centerOnGraphNode(next)
  }

  function moveCursor(delta) {
    var list = navi.currentList()
    if (list.length === 0) return
    navi.app.nav.moveCursor(delta, list.length)
    // Reaching the first row of a list shows whatever sits above it in the
    // scrolling content (e.g. the Documents type badges).
    if (navi.app.nav.cursorIndex === 0 && navi.app.nav.viewMode !== "entry") Qt.callLater(navi.actions.scrollToTop)
  }

  function hoverCursor(index) {
    navi.app.nav.hoverCursor(index)
  }

  function activateCursor() {
    var list = navi.currentList()
    if (navi.app.nav.cursorIndex < 0 || navi.app.nav.cursorIndex >= list.length) return
    if (navi.app.nav.viewMode === "documents") navi.openDoc(list[navi.app.nav.cursorIndex].path)
    else if (navi.app.nav.viewMode === "memories") navi.openMemory(list[navi.app.nav.cursorIndex].file)
    else navi.openCard(list[navi.app.nav.cursorIndex].id)
  }

  function activateGraphNode() {
    var id = navi.app.graph.activateGraphNode()
    if (id !== "") navi.openCard(id)
  }

  // The user picked a project in the dropdown. A dirty memory draft blocks the
  // switch.
  function chooseProject(project) {
    if (navi.app.memories.memoryEditing && navi.app.memories.memoryDraft !== navi.app.memories.memoryText) {
      navi.closeDropdown()
      navi.app.memories.memoryOpError = "You have unsaved changes. Save them, or choose Cancel to discard, before switching project."
      return
    }
    navi.closeDropdown()
    if (!project) return
    navi.app.projects.chooseProject(project)
    navi.actions.focusForView()
  }

  function toggleDropdown() {
    if (navi.app.deleter.deleteTarget) return
    if (navi.app.nav.dropdownOpen) { navi.closeDropdown(); return }
    var index = 0
    for (var i = 0; i < navi.app.projects.projects.length; i++)
      if (navi.app.projects.selectedProject && navi.app.projects.projects[i].root_path === navi.app.projects.selectedProject.root_path) index = i
    navi.app.nav.toggleDropdown(index)
    navi.actions.focusForView()
  }

  function closeDropdown() {
    if (!navi.app.nav.dropdownOpen) return
    navi.app.nav.closeDropdown()
    navi.actions.focusForView()
  }

  function moveDropdown(delta) {
    navi.app.nav.moveDropdown(delta, navi.app.projects.filteredProjects.length)
  }

  function acceptDropdown() {
    var list = navi.app.projects.filteredProjects
    if (navi.app.nav.dropdownCursor < 0 || navi.app.nav.dropdownCursor >= list.length) return
    navi.chooseProject(list[navi.app.nav.dropdownCursor])
  }

  function showSection(name) {
    if (!navi.app.projects.selectedProject || navi.app.deleter.deleteTarget || navi.app.memories.memoryDeleteOpen || navi.app.memories.newMemoryOpen) return
    if (navi.app.memories.memoryEditing && navi.app.memories.memoryDraft !== navi.app.memories.memoryText) return
    if (name === "documents" && !navi.documentsEnabled) return
    if (navi.app.nav.dropdownOpen) navi.app.nav.dropdownOpen = false
    navi.resetSearch()
    navi.app.nav.scrollOnCursor = false
    navi.app.nav.viewMode = name === "documents" ? "documents" : name === "graph" ? "graph" : name === "memories" ? "memories" : "board"
    navi.app.memories.memoryEditing = false
    if (name === "documents") navi.app.docs.fetchDocs()
    if (name === "memories") navi.app.memories.fetchMemories()
    if (name === "graph" && navi.app.graph.graphCursor === "" && navi.app.graph.graph.nodes.length > 0) navi.app.graph.graphCursor = navi.app.graph.graph.nodes[0].id
    Qt.callLater(navi.actions.scrollToTop)
    navi.actions.focusForView()
  }

  function openCard(id) {
    var from = navi.app.nav.viewMode
    if (!navi.app.board.openCard(id)) return
    if (from === "board" || from === "graph")
      navi.app.nav.pushReturn(navi.flick ? navi.flick.contentY : 0, from)
    navi.app.nav.viewMode = "entry"
    navi.app.nav.scrollOnCursor = false
    navi.app.nav.cursorIndex = 0
    Qt.callLater(navi.actions.scrollToTop)
    navi.actions.focusForView()
  }

  // Leaving a card puts the Board back exactly as it was: same highlighted
  // card, same scroll position.
  function restoreListView() {
    var back = navi.app.nav.popReturn()
    navi.app.nav.viewMode = back.mode
    navi.app.nav.scrollOnCursor = false
    navi.app.nav.cursorIndex = back.cursor
    Qt.callLater(function() { if (navi.flick) navi.actions.scrollBy(back.scrollY - navi.flick.contentY) })
    navi.actions.focusForView()
  }

  function openDoc(path) {
    if (!navi.app.docs.openDoc(path)) return
    navi.app.nav.pushReturn(navi.flick ? navi.flick.contentY : 0)
    navi.app.nav.viewMode = "document"
    navi.app.nav.scrollOnCursor = false
    navi.app.nav.cursorIndex = 0
    Qt.callLater(navi.actions.scrollToTop)
    navi.actions.focusForView()
  }

  function restoreDocumentsList() {
    navi.app.docs.restoreDocumentsList()
    var back = navi.app.nav.popReturn()
    navi.app.nav.viewMode = "documents"
    navi.app.nav.scrollOnCursor = false
    navi.app.nav.cursorIndex = back.cursor
    Qt.callLater(function() { if (navi.flick) navi.actions.scrollBy(back.scrollY - navi.flick.contentY) })
    navi.actions.focusForView()
  }

  // ---- Memories: the notes themselves live in MemoriesStore; what stays here
  // is the navigation and focus work around them.
  function openMemory(file) {
    if (!navi.app.memories.openMemory(file)) return
    if (navi.app.nav.viewMode === "memories")
      navi.app.nav.pushReturn(navi.flick ? navi.flick.contentY : 0)
    navi.app.nav.viewMode = "memory"
    navi.app.nav.scrollOnCursor = false
    navi.app.nav.cursorIndex = 0
    Qt.callLater(navi.actions.scrollToTop)
    navi.actions.focusForView()
  }

  function restoreMemoriesList() {
    navi.app.memories.restoreMemoriesList()
    var back = navi.app.nav.popReturn()
    navi.app.nav.viewMode = "memories"
    navi.app.nav.scrollOnCursor = false
    navi.app.nav.cursorIndex = back.cursor
    Qt.callLater(function() { if (navi.flick) navi.actions.scrollBy(back.scrollY - navi.flick.contentY) })
    navi.actions.focusForView()
  }

  function goBack() {
    if (navi.app.nav.viewMode === "memory") { if (navi.app.memories.memoryEditing) navi.app.memories.memoryEscape(); else navi.restoreMemoriesList(); return }
    if (navi.app.nav.viewMode === "entry") { navi.restoreListView(); return }
    if (navi.app.nav.viewMode === "document") { navi.restoreDocumentsList(); return }
  }
}
