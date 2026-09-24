import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "core/domain/board.js" as Board
import "core/domain/documents.js" as Documents
import "core/domain/memories.js" as Memories
import "core/domain/projects.js" as Projects
import "core/stores" as Core

// Browses brd's local kanban board (`brd projects` / `brd tree`), per
// project: pick a project, then view its cards as a Board.
// Read-only -- nothing here ever calls brd add/update/delete/block.
Panel {
  id: root
  moduleName: "paulomtts.omarchy-project-manager"
  ipcTarget: "paulomtts.omarchy-project-manager"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")

  // All non-visual state lives in the stores; `app` is how the tests reach it.
  Core.App { id: appStores; backendDir: root.pluginDir + "core/backend/" }
  readonly property var app: appStores

  readonly property bool documentsEnabled: true

  // The stores announce what the panel still has to do itself: reload the
  // sections a project change invalidates, and put the focus where the new
  // state belongs.
  Connections {
    target: appStores.projects
    function onSelected(project) {
      root.resetMemories()
      root.focusForView()
    }
    function onCleared() {
      root.resetMemories()
    }
  }

  // A different category means a different list: the cursor reset is App's, the
  // scroll is the panel's.
  Connections {
    target: appStores.docs
    function onCategoryToggled() { Qt.callLater(root.scrollToTop) }
  }

  // The open card left the board (a refetch dropped it): back to the list.
  Connections {
    target: appStores.board
    function onListViewRequested() { root.restoreListView() }
  }

  Connections {
    target: appStores.deleter
    function onRequested() { root.focusForView() }
    function onClosed() { root.focusForView() }
    function onDeleted() { root.focusForView() }
  }

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

  function currentList() {
    if (appStores.nav.viewMode === "board") return appStores.board.boardCards
    if (appStores.nav.viewMode === "entry") return appStores.board.detailLinkList
    if (appStores.nav.viewMode === "documents") return appStores.docs.filteredDocs
    if (appStores.nav.viewMode === "memories") return root.filteredMemories
    return []
  }

  readonly property Item focusItem: appStores.deleter.deleteTarget ? confirmField
    : root.memoryDeleteOpen ? memoryConfirm.focusItem
    : root.newMemoryOpen ? newMemoryDialog.focusItem
    : (appStores.nav.viewMode === "memory" && root.memoryEditing) ? memoryNote.editorItem
    : appStores.nav.dropdownOpen ? sidebar.filterItem
    : (appStores.nav.viewMode === "entry" || appStores.nav.viewMode === "document" || appStores.nav.viewMode === "memory" || appStores.nav.viewMode === "graph" || !appStores.projects.selectedProject) ? keyCatcher
    : searchField

  function focusForView() {
    Qt.callLater(function() {
      if (!root.opened) return
      if (root.focusItem) root.focusItem.forceActiveFocus()
    })
  }

  function resetSearch() {
    appStores.nav.resetSearch()
  }

  function moveGraph(direction) {
    var next = appStores.graph.moveGraph(direction)
    if (next === "") return
    if (graphView) graphView.centerOn(next)
  }

  function moveCursor(delta) {
    var list = root.currentList()
    if (list.length === 0) return
    appStores.nav.moveCursor(delta, list.length)
    // Reaching the first row of a list shows whatever sits above it in the
    // scrolling content (e.g. the Documents type badges).
    if (appStores.nav.cursorIndex === 0 && appStores.nav.viewMode !== "entry") Qt.callLater(root.scrollToTop)
  }

  function hoverCursor(index) {
    appStores.nav.hoverCursor(index)
  }

  function scrollToTop() {
    if (panelFlick) panelFlick.contentY = 0
  }

  property var revealTarget: null

  // Held arrow keys queue many reveals before the first runs; only the newest
  // row matters, and running the stale ones scrolls to rows the cursor left.
  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    var pending = root.revealTarget !== null
    root.revealTarget = item
    if (pending) return
    Qt.callLater(function() {
      var target = root.revealTarget
      root.revealTarget = null
      if (!target || !panelFlick) return
      var margin = Style.space(6)
      var point = target.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + target.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function scrollBy(pixels) {
    if (!panelFlick) return
    panelFlick.contentY = root.clamp(panelFlick.contentY + pixels, 0, Math.max(0, panelFlick.contentHeight - panelFlick.height))
  }

  function activateCursor() {
    var list = root.currentList()
    if (appStores.nav.cursorIndex < 0 || appStores.nav.cursorIndex >= list.length) return
    if (appStores.nav.viewMode === "documents") root.openDoc(list[appStores.nav.cursorIndex].path)
    else if (appStores.nav.viewMode === "memories") root.openMemory(list[appStores.nav.cursorIndex].file)
    else root.openCard(list[appStores.nav.cursorIndex].id)
  }

  function activateGraphNode() {
    var id = appStores.graph.activateGraphNode()
    if (id !== "") root.openCard(id)
  }

  function displayPath(path) {
    return String(path || "").replace(/^\/home\/[^\/]+/, "~")
  }

  onOpenedChanged: if (opened) { appStores.projects.onPanelOpened(); root.focusForView() }

  // The user picked a project in the dropdown. A dirty memory draft blocks the
  // switch (memory state still lives here).
  function chooseProject(project) {
    if (root.memoryEditing && root.memoryDraft !== root.memoryText) {
      root.closeDropdown()
      root.memoryOpError = "You have unsaved changes. Save them, or choose Cancel to discard, before switching project."
      return
    }
    root.closeDropdown()
    if (!project) return
    appStores.projects.chooseProject(project)
    root.focusForView()
  }

  function toggleDropdown() {
    if (appStores.deleter.deleteTarget) return
    if (appStores.nav.dropdownOpen) { root.closeDropdown(); return }
    var index = 0
    for (var i = 0; i < appStores.projects.projects.length; i++)
      if (appStores.projects.selectedProject && appStores.projects.projects[i].root_path === appStores.projects.selectedProject.root_path) index = i
    appStores.nav.toggleDropdown(index)
    root.focusForView()
  }

  function closeDropdown() {
    if (!appStores.nav.dropdownOpen) return
    appStores.nav.closeDropdown()
    root.focusForView()
  }

  function moveDropdown(delta) {
    appStores.nav.moveDropdown(delta, appStores.projects.filteredProjects.length)
  }

  function acceptDropdown() {
    var list = appStores.projects.filteredProjects
    if (appStores.nav.dropdownCursor < 0 || appStores.nav.dropdownCursor >= list.length) return
    root.chooseProject(list[appStores.nav.dropdownCursor])
  }

  // Shortcuts that work wherever the caret is. Returns true when it handled the
  // key. Ignored while a delete confirmation is open so a stray Ctrl+P cannot
  // move things underneath it.
  function handleGlobalKey(event) {
    if (!(event.modifiers & Qt.ControlModifier) || appStores.deleter.deleteTarget || root.memoryDeleteOpen || root.newMemoryOpen) return false
    if (event.key === Qt.Key_P) { root.toggleDropdown(); return true }
    if (event.key === Qt.Key_1) { root.showSection("board"); return true }
    if (event.key === Qt.Key_2) { root.showSection("documents"); return true }
    if (event.key === Qt.Key_3) { root.showSection("graph"); return true }
    if (event.key === Qt.Key_4) { root.showSection("memories"); return true }
    if (event.key === Qt.Key_N && appStores.nav.viewMode === "memories") { root.openNewMemory(); return true }
    if (event.key === Qt.Key_E && appStores.nav.viewMode === "memory") { root.startMemoryEdit(); return true }
    return false
  }

  function showSection(name) {
    if (!appStores.projects.selectedProject || appStores.deleter.deleteTarget || root.memoryDeleteOpen || root.newMemoryOpen) return
    if (root.memoryEditing && root.memoryDraft !== root.memoryText) return
    if (name === "documents" && !root.documentsEnabled) return
    if (appStores.nav.dropdownOpen) appStores.nav.dropdownOpen = false
    root.resetSearch()
    appStores.nav.scrollOnCursor = false
    appStores.nav.viewMode = name === "documents" ? "documents" : name === "graph" ? "graph" : name === "memories" ? "memories" : "board"
    root.memoryEditing = false
    if (name === "documents") appStores.docs.fetchDocs()
    if (name === "memories") root.fetchMemories()
    if (name === "graph" && appStores.graph.graphCursor === "" && appStores.graph.graph.nodes.length > 0) appStores.graph.graphCursor = appStores.graph.graph.nodes[0].id
    Qt.callLater(root.scrollToTop)
    root.focusForView()
  }

  function openCard(id) {
    var from = appStores.nav.viewMode
    if (!appStores.board.openCard(id)) return
    if (from === "board" || from === "graph")
      appStores.nav.pushReturn(panelFlick ? panelFlick.contentY : 0, from)
    appStores.nav.viewMode = "entry"
    appStores.nav.scrollOnCursor = false
    appStores.nav.cursorIndex = 0
    Qt.callLater(root.scrollToTop)
    focusForView()
  }

  // Leaving a card puts the Board back exactly as it was: same highlighted
  // card, same scroll position.
  function restoreListView() {
    var back = appStores.nav.popReturn()
    appStores.nav.viewMode = back.mode
    appStores.nav.scrollOnCursor = false
    appStores.nav.cursorIndex = back.cursor
    Qt.callLater(function() { if (panelFlick) root.scrollBy(back.scrollY - panelFlick.contentY) })
    focusForView()
  }

  function openDoc(path) {
    if (!appStores.docs.openDoc(path)) return
    appStores.nav.pushReturn(panelFlick ? panelFlick.contentY : 0)
    appStores.nav.viewMode = "document"
    appStores.nav.scrollOnCursor = false
    appStores.nav.cursorIndex = 0
    Qt.callLater(root.scrollToTop)
    root.focusForView()
  }

  function restoreDocumentsList() {
    appStores.docs.restoreDocumentsList()
    var back = appStores.nav.popReturn()
    appStores.nav.viewMode = "documents"
    appStores.nav.scrollOnCursor = false
    appStores.nav.cursorIndex = back.cursor
    Qt.callLater(function() { if (panelFlick) root.scrollBy(back.scrollY - panelFlick.contentY) })
    root.focusForView()
  }

  // ---- Memories: the project's Claude Code memory notes, read and managed via
  // list-memories.py / memory-op.py (which back up before every change).
  property var memories: []
  property bool memoriesLoading: false
  property string memoriesError: ""
  property bool memoriesFound: true
  property string memoryDir: ""
  property string memoryType: ""
  property string selectedMemory: ""
  property string memoryText: ""
  property string memoryReadError: ""
  property bool memoryEditing: false
  property string memoryDraft: ""
  property string memoryEditBase: ""
  property bool memoryBusy: false
  property string memoryOpError: ""
  property bool newMemoryOpen: false
  property string newMemoryError: ""
  property bool memoryDeleteOpen: false
  property string memoryDeleteError: ""
  property string pendingMemoryOpen: ""
  property int memoriesSeq: 0
  property var memoriesProc: null

  readonly property var memoryTypes: Memories.memoryTypeCounts(root.memories)
  readonly property var filteredMemories: Memories.filterMemories(Memories.filterMemoriesByType(root.memories, root.memoryType), appStores.nav.searchQuery)
  readonly property bool canCreateMemory: root.memoryDir !== ""
  readonly property var selectedMemoryEntry: {
    for (var i = 0; i < root.memories.length; i++)
      if (root.memories[i].file === root.selectedMemory) return root.memories[i]
    return { file: root.selectedMemory, name: root.selectedMemory, description: "", type: "other" }
  }

  function resetMemories() {
    root.memoriesSeq += 1
    root.memories = []; root.memoriesError = ""; root.memoriesLoading = false; root.memoriesFound = true
    root.memoryDir = ""; root.memoryType = ""; root.selectedMemory = ""; root.memoryText = ""
    root.memoryReadError = ""; root.memoryEditing = false; root.memoryDraft = ""; root.memoryOpError = ""
    root.newMemoryOpen = false; root.newMemoryError = ""; root.memoryDeleteOpen = false; root.memoryDeleteError = ""
    root.pendingMemoryOpen = ""
  }

  function fetchMemories() {
    if (!appStores.projects.selectedProject) return
    var old = root.memoriesProc
    if (old) old.running = false
    root.memoriesError = ""
    root.memoriesLoading = true
    root.memoriesSeq += 1
    var rootPath = appStores.projects.selectedProject.root_path
    var proc = memoriesProcC.createObject(root, { forRoot: rootPath, seq: root.memoriesSeq })
    proc.command = ["python3", root.pluginDir + "core/backend/memories/list-memories.py", rootPath]
    root.memoriesProc = proc
    proc.running = true
  }

  function applyMemoriesResult(text, exitCode) {
    var result = Memories.parseMemoriesResult(text, exitCode)
    root.memoriesLoading = false
    root.memories = result.notes
    root.memoriesFound = result.found
    if (result.ok) root.memoryDir = result.memoryDir
    root.memoriesError = result.ok ? "" : result.error
    if (root.pendingMemoryOpen !== "") {
      var file = root.pendingMemoryOpen
      root.pendingMemoryOpen = ""
      if (appStores.nav.viewMode === "memories") root.openMemory(file)
    }
  }

  function toggleMemoryType(id) {
    root.memoryType = root.memoryType === id ? "" : id
    appStores.nav.cursorIndex = 0
    appStores.nav.scrollOnCursor = false
    Qt.callLater(root.scrollToTop)
  }

  function openMemory(file) {
    var known = false
    for (var i = 0; i < root.memories.length; i++) if (root.memories[i].file === file) known = true
    if (!known || !appStores.projects.selectedProject || root.memoryDir === "") return
    if (appStores.nav.viewMode === "memories")
      appStores.nav.pushReturn(panelFlick ? panelFlick.contentY : 0)
    root.selectedMemory = file
    root.memoryText = ""
    root.memoryReadError = ""
    root.memoryEditing = false
    root.memoryDraft = ""
    root.memoryOpError = ""
    appStores.nav.viewMode = "memory"
    appStores.nav.scrollOnCursor = false
    appStores.nav.cursorIndex = 0
    Qt.callLater(root.scrollToTop)
    root.focusForView()
  }

  function restoreMemoriesList() {
    root.selectedMemory = ""
    root.memoryText = ""
    root.memoryReadError = ""
    root.memoryEditing = false
    root.memoryDraft = ""
    root.memoryOpError = ""
    var back = appStores.nav.popReturn()
    appStores.nav.viewMode = "memories"
    appStores.nav.scrollOnCursor = false
    appStores.nav.cursorIndex = back.cursor
    Qt.callLater(function() { if (panelFlick) root.scrollBy(back.scrollY - panelFlick.contentY) })
    root.focusForView()
  }

  function setMemoryText(text) {
    root.memoryText = text
    root.memoryReadError = ""
  }

  function startMemoryEdit() {
    if (appStores.nav.viewMode !== "memory" || root.memoryEditing || root.memoryBusy || root.memoryText === "") return
    root.memoryEditing = true
    root.memoryDraft = root.memoryText
    root.memoryEditBase = root.memoryText
    root.memoryOpError = ""
    root.focusForView()
  }

  function cancelMemoryEdit() {
    if (root.memoryBusy) return
    root.memoryEditing = false
    root.memoryDraft = ""
    root.memoryOpError = ""
    root.focusForView()
  }

  // Escape never throws edits away: a dirty draft stays until Cancel is chosen.
  function memoryEscape() {
    if (!root.memoryEditing) return
    if (root.memoryDraft === root.memoryText) root.cancelMemoryEdit()
    else root.memoryOpError = "You have unsaved changes. Save them, or choose Cancel to discard."
  }

  function runMemoryOp(op, file, content, expected) {
    memoryOpProc.op = op
    memoryOpProc.forRoot = appStores.projects.selectedProject ? appStores.projects.selectedProject.root_path : ""
    memoryOpProc.forFile = file
    var command = ["python3", root.pluginDir + "core/backend/memories/memory-op.py", op, root.memoryDir, file]
    if (content !== undefined) command.push(content)
    if (expected !== undefined) command.push(expected)
    memoryOpProc.command = command
    root.memoryBusy = true
    memoryOpProc.running = true
  }

  function saveMemory() {
    if (!root.memoryEditing || root.memoryBusy || root.memoryDir === "" || root.memoryDraft === root.memoryText) return
    root.memoryOpError = ""
    root.runMemoryOp("save", root.selectedMemory, root.memoryDraft, root.memoryEditBase)
  }

  function openNewMemory() {
    if (!root.canCreateMemory || root.memoryBusy || appStores.nav.viewMode !== "memories") return
    root.newMemoryOpen = true
    root.newMemoryError = ""
    root.focusForView()
  }

  function cancelNewMemory() {
    if (root.memoryBusy) return
    root.newMemoryOpen = false
    root.focusForView()
  }

  function createMemory(name, type, description, body) {
    if (root.memoryBusy || root.memoryDir === "" || String(name).trim() === "") return
    var file = Memories.newMemoryFile(type, name, root.memories.map(function(n) { return n.file }))
    root.newMemoryError = ""
    root.runMemoryOp("create", file, Memories.composeMemory(name, description, type, body))
  }

  function requestMemoryDelete() {
    if (appStores.nav.viewMode !== "memory" || root.selectedMemory === "" || root.memoryBusy) return
    root.memoryDeleteOpen = true
    root.memoryDeleteError = ""
    root.focusForView()
  }

  function cancelMemoryDelete() {
    if (root.memoryBusy) return
    root.memoryDeleteOpen = false
    root.focusForView()
  }

  function performMemoryDelete() {
    if (!root.memoryDeleteOpen || root.memoryBusy || root.selectedMemory === "" || root.memoryDir === "") return
    root.memoryDeleteError = ""
    root.runMemoryOp("delete", root.selectedMemory)
  }

  function applyMemoryOpResult(text, exitCode) {
    var result = Memories.parseMemoryOpResult(text, exitCode)
    var op = memoryOpProc.op
    var sameProject = appStores.projects.selectedProject && appStores.projects.selectedProject.root_path === memoryOpProc.forRoot
    root.memoryBusy = false
    if (!sameProject) return
    if (op === "save") {
      if (result.ok) {
        root.memoryText = root.memoryDraft
        root.memoryEditing = false
        root.memoryDraft = ""
        root.fetchMemories()
      } else root.memoryOpError = result.error
    } else if (op === "create") {
      if (result.ok) {
        root.newMemoryOpen = false
        root.pendingMemoryOpen = memoryOpProc.forFile
        root.fetchMemories()
      } else root.newMemoryError = result.error
    } else if (op === "delete") {
      if (result.ok) {
        root.memoryDeleteOpen = false
        root.restoreMemoriesList()
        root.fetchMemories()
      } else root.memoryDeleteError = result.error
    }
    root.focusForView()
  }

  function goBack() {
    if (appStores.nav.viewMode === "memory") { if (root.memoryEditing) root.memoryEscape(); else root.restoreMemoriesList(); return }
    if (appStores.nav.viewMode === "entry") { restoreListView(); return }
    if (appStores.nav.viewMode === "document") { restoreDocumentsList(); return }
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { appStores.projects.refreshProjects(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "🗂️"
    onPressed: function(buttonCode) { root.toggle() }
  }

  Component {
    id: memoriesProcC
    Process {
      id: mp
      objectName: "listMemoriesProc"
      property string outText: ""
      property string forRoot: ""
      property int seq: 0
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: mp.outText = String(text || "")
      }
      stderr: StdioCollector { waitForEnd: true }
      onExited: function(exitCode) {
        var current = appStores.projects.selectedProject ? appStores.projects.selectedProject.root_path : ""
        if (mp.seq === root.memoriesSeq && mp.forRoot === current) root.applyMemoriesResult(mp.outText, exitCode)
        mp.destroy()
      }
    }
  }

  Process {
    id: memoryOpProc
    objectName: "memoryOpProc"
    property string op: ""
    property string forRoot: ""
    property string forFile: ""
    property string outText: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: memoryOpProc.outText = String(text || "")
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      var out = memoryOpProc.outText
      memoryOpProc.outText = ""
      root.applyMemoryOpResult(out, exitCode)
    }
  }

  FileView {
    id: memoryFile
    objectName: "memoryFile"
    path: appStores.nav.viewMode === "memory" && root.memoryDir !== "" && root.selectedMemory !== ""
      ? Memories.memoryAbsolutePath(root.memoryDir, root.selectedMemory) : ""
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.setMemoryText(memoryFile.text())
    onLoadFailed: if (memoryFile.path !== "") root.memoryReadError = "Could not read this memory."
  }

  KeyboardPanel {
    id: panel
    objectName: "mainPanel"
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: root.focusItem
    // Centered under the bar rather than under the icon, and wide enough for
    // the sidebar.
    centerOnBar: true
    contentWidth: panel.fittedContentWidth(Math.max(Style.space(840), 0.8 * panel.screenW))
    // At least 80% of the screen tall, whatever the section holds, so the
    // popup does not jump in size between sections; long content still scrolls.
    readonly property real minContentHeight: 0.8 * panel.screenH - panel.verticalContentInset
    contentHeight: panel.fittedContentHeight(Math.max(toolbar.implicitHeight + Style.space(12) + column.implicitHeight, sidebar.implicitHeight, minContentHeight),
      Math.max(Style.space(620), 0.8 * panel.screenH))

    Item {
      id: globalKeys
      Keys.onPressed: function(event) { if (root.handleGlobalKey(event)) event.accepted = true }
    }

    PanelKeyCatcher {
      id: keyCatcher
      objectName: "keyCatcher"
      Keys.forwardTo: [globalKeys]
      anchors.fill: parent
      onCloseRequested: appStores.deleter.deleteTarget ? appStores.deleter.cancelDelete() : root.memoryDeleteOpen ? root.cancelMemoryDelete() : root.newMemoryOpen ? root.cancelNewMemory() : (appStores.nav.dropdownOpen ? root.closeDropdown() : ((appStores.nav.viewMode === "entry" || appStores.nav.viewMode === "document" || appStores.nav.viewMode === "memory") ? root.goBack() : root.close()))
      onMoveRequested: function(dx, dy) {
        if (appStores.nav.viewMode === "graph") {
          if (dx !== 0) root.moveGraph(dx < 0 ? "left" : "right")
          else if (dy !== 0) root.moveGraph(dy < 0 ? "up" : "down")
          return
        }
        if (dx < 0 && (appStores.nav.viewMode === "entry" || appStores.nav.viewMode === "document" || appStores.nav.viewMode === "memory")) { root.goBack(); return }
        if (appStores.nav.viewMode !== "entry" && appStores.nav.viewMode !== "document" && appStores.nav.viewMode !== "memory") return
        if (dx > 0) { if (appStores.nav.viewMode === "entry") root.activateCursor(); return }
        if (dy === 0) return
        // Links are the cursor's targets; a card without any is just text,
        // so the arrows scroll it instead.
        if (appStores.nav.viewMode === "entry" && appStores.board.detailLinkList.length > 0) root.moveCursor(dy)
        else root.scrollBy(dy * Style.space(56))
      }
      onActivateRequested: {
        if (appStores.nav.viewMode === "entry") root.activateCursor()
        else if (appStores.nav.viewMode === "graph") root.activateGraphNode()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Sidebar {
        id: sidebar
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Style.space(200)
        projects: appStores.projects.filteredProjects
        selectedProject: appStores.projects.selectedProject
        section: appStores.nav.section
        dropdownOpen: appStores.nav.dropdownOpen
        dropdownQuery: appStores.nav.dropdownQuery
        dropdownCursor: appStores.nav.dropdownCursor
        canDelete: !!appStores.projects.selectedProject && !appStores.deleter.deleting && !appStores.deleter.deleteTarget
        documentsEnabled: root.documentsEnabled
        foreground: root.foreground
        dim: root.dim
        urgent: root.urgent
        fontFamily: root.fontFamily
        onDropdownToggled: root.toggleDropdown()
        onProjectChosen: function(project) { root.chooseProject(project) }
        onQueryEdited: function(text) { appStores.nav.dropdownQuery = text; appStores.nav.dropdownCursor = 0 }
        onSectionChosen: function(name) { root.showSection(name) }
        onDeleteRequested: appStores.deleter.openDelete(appStores.projects.selectedProject)
        onCursorHovered: function(index) { appStores.nav.dropdownCursor = index }
        onDropdownMove: function(delta) { root.moveDropdown(delta) }
        onDropdownAccept: root.acceptDropdown()
        onDropdownCancel: root.closeDropdown()
        onFilterKey: function(event) { if (root.handleGlobalKey(event)) event.accepted = true }
      }

      // Column 2 of the layout: a toolbar that never scrolls (heading, refresh,
      // search) above the content, which scrolls on its own.
      Column {
        id: toolbar
        objectName: "panelToolbar"
        anchors.left: sidebar.right
        anchors.leftMargin: Style.space(12)
        anchors.top: parent.top
        anchors.right: parent.right
        spacing: Style.space(12)

        RowLayout {
          width: parent.width
          spacing: Style.spacing.md

          Text {
            visible: appStores.nav.viewMode === "entry" || appStores.nav.viewMode === "document" || appStores.nav.viewMode === "memory"
            text: "‹ Back"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.goBack() }
          }

          Text {
            objectName: "projectHeading"
            Layout.fillWidth: true
            text: appStores.projects.selectedProject ? appStores.nav.sectionTitle : "Project Manager"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
            elide: Text.ElideMiddle
          }

          Text {
            objectName: "newMemoryButton"
            visible: appStores.nav.viewMode === "memories" && root.canCreateMemory
            text: "＋ New"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openNewMemory() }
          }

          Text {
            visible: appStores.nav.viewMode === "board" || appStores.nav.viewMode === "graph" || appStores.nav.viewMode === "memories"
            text: "⟳"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: appStores.nav.viewMode === "memories" ? root.fetchMemories() : appStores.board.fetchBoard() }
          }
        }

        TextField {
          id: searchField
          objectName: "searchField"
          visible: !!appStores.projects.selectedProject && (appStores.nav.viewMode === "board" || appStores.nav.viewMode === "documents" || appStores.nav.viewMode === "memories")
          width: parent.width
          foreground: root.foreground
          placeholderText: appStores.nav.viewMode === "documents" ? "Search documents…" : appStores.nav.viewMode === "memories" ? "Search memories…" : "Search cards…"
          text: appStores.nav.searchQuery
          Keys.forwardTo: [globalKeys]

          onTextChanged: {
            appStores.nav.searchQuery = text
            appStores.nav.cursorIndex = 0
          }

          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              if (appStores.nav.searchQuery !== "") { appStores.nav.searchQuery = "" }
              else root.close()
              event.accepted = true
              return
            }
            if (event.key === Qt.Key_Right && searchField.cursorPosition === searchField.text.length) {
              root.activateCursor(); event.accepted = true; return
            }
            if (event.key === Qt.Key_Down) { root.moveCursor(1); event.accepted = true; return }
            if (event.key === Qt.Key_Up) { root.moveCursor(-1); event.accepted = true; return }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.activateCursor(); event.accepted = true; return
            }
            if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
              root.switchPanel((event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab ? -1 : 1)
              event.accepted = true
              return
            }
          }
        }

        Text {
          visible: appStores.projects.loadError !== ""
          width: parent.width
          text: appStores.projects.loadError
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }

      Flickable {
        id: panelFlick
        objectName: "panelFlick"
        anchors.left: sidebar.right
        anchors.leftMargin: Style.space(12)
        anchors.top: toolbar.bottom
        anchors.topMargin: toolbar.height > 0 ? Style.space(12) : 0
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Text {
            visible: !appStores.deleter.deleteTarget && appStores.deleter.lastSnapshot !== ""
            width: parent.width
            text: "Removed. Snapshot saved to " + root.displayPath(appStores.deleter.lastSnapshot)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WrapAnywhere
          }

          Text {
            visible: !appStores.projects.selectedProject && appStores.projects.loadError === ""
            width: parent.width
            text: "No projects registered with brd."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Column {
            visible: appStores.nav.viewMode === "board" && !!appStores.projects.selectedProject
            width: parent.width
            spacing: Style.space(10)

            Text {
              visible: appStores.board.cardRoots.length === 0 && appStores.projects.loadError === ""
              width: parent.width
              text: "This project's board is empty."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Text {
              visible: appStores.board.cardRoots.length > 0 && appStores.board.visibleBoardRoots.length === 0
              width: parent.width
              text: "No cards match “" + appStores.nav.searchQuery + "”."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: appStores.board.statuses

              Column {
                required property string modelData
                width: parent.width
                spacing: Style.space(6)

                PanelSectionHeader {
                  text: appStores.board.statusLabel(modelData) + " (" + appStores.board.boardColumn(modelData).length + ")"
                  foreground: Board.statusColor(modelData, root.foreground)
                  fontFamily: root.fontFamily
                }

                Repeater {
                  model: appStores.board.boardColumn(modelData)

                  BoardCard {
                    required property var modelData
                    width: parent.width
                    cardIndex: appStores.board.boardIndexOf(modelData.id)
                    title: modelData.title
                    status: modelData.status
                    progress: Board.subtreeCounts(modelData)
                    onActivated: root.openCard(modelData.id)
                  }
                }
              }
            }
          }

          GraphView {
            id: graphView
            visible: appStores.nav.viewMode === "graph" && !!appStores.projects.selectedProject
            width: parent.width
            height: Math.max(Style.space(240), panelFlick.height - y - Style.space(12))
            nodes: appStores.graph.graph.nodes
            edges: appStores.graph.graph.edges
            cursorId: appStores.graph.graphCursor
            foreground: root.foreground
            dim: root.dim
            fontFamily: root.fontFamily
            onNodeClicked: function(id) { appStores.graph.graphCursor = id; root.openCard(id) }
          }

          MemoriesView {
            visible: appStores.nav.viewMode === "memories" && !!appStores.projects.selectedProject
            width: parent.width
            notes: root.filteredMemories
            types: root.memoryTypes
            activeType: root.memoryType
            query: appStores.nav.searchQuery
            cursorIndex: appStores.nav.cursorIndex
            loading: root.memoriesLoading
            found: root.memoriesFound
            error: root.memoriesError
            scrollOnCursor: appStores.nav.scrollOnCursor
            foreground: root.foreground
            dim: root.dim
            fontFamily: root.fontFamily
            onNoteChosen: function(file) { root.openMemory(file) }
            onHovered: function(index) { root.hoverCursor(index) }
            onRevealRequested: function(item) { root.scrollItemIntoView(item) }
            onTypeToggled: function(id) { root.toggleMemoryType(id) }
          }

          MemoryNoteView {
            id: memoryNote
            visible: appStores.nav.viewMode === "memory" && !!appStores.projects.selectedProject
            width: parent.width
            entry: root.selectedMemoryEntry
            text: root.memoryText
            readError: root.memoryReadError
            editing: root.memoryEditing
            draft: root.memoryDraft
            busy: root.memoryBusy
            error: root.memoryOpError
            foreground: root.foreground
            urgent: root.urgent
            dim: root.dim
            fontFamily: root.fontFamily
            onEditRequested: root.startMemoryEdit()
            onDeleteRequested: root.requestMemoryDelete()
            onSaveRequested: root.saveMemory()
            onCancelEditRequested: root.cancelMemoryEdit()
            onDraftEdited: function(text) { root.memoryDraft = text }
            onEscapePressed: root.memoryEscape()
          }

          DocumentsView {
            visible: appStores.nav.viewMode === "documents" && !!appStores.projects.selectedProject
            width: parent.width
            docs: appStores.docs.filteredDocs
            query: appStores.nav.searchQuery
            categories: Documents.docCategoryCounts(appStores.docs.docs)
            activeCategory: appStores.docs.docCategory
            cursorIndex: appStores.nav.cursorIndex
            loading: appStores.docs.docsLoading
            error: appStores.docs.docsError
            truncated: appStores.docs.docsTruncated
            scrollOnCursor: appStores.nav.scrollOnCursor
            foreground: root.foreground
            dim: root.dim
            fontFamily: root.fontFamily
            onCategoryToggled: function(id) { appStores.docs.toggleDocCategory(id) }
            onDocChosen: function(path) { root.openDoc(path) }
            onHovered: function(index) { root.hoverCursor(index) }
            onRevealRequested: function(item) { root.scrollItemIntoView(item) }
          }

          Column {
            visible: appStores.nav.viewMode === "document"
            width: parent.width
            spacing: Style.space(10)

            Text {
              width: parent.width
              text: appStores.docs.selectedDocPath
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideMiddle
            }

            TagPicker {
              width: parent.width
              current: appStores.docs.selectedDocCategory
              busy: appStores.docs.docTagBusy
              error: appStores.docs.docTagError
              foreground: root.foreground
              dim: root.dim
              fontFamily: root.fontFamily
              onTagChosen: function(id) { appStores.docs.setDocTag(id) }
            }

            Text {
              visible: appStores.docs.docTooLargeFlag || appStores.docs.docError !== ""
              width: parent.width
              text: appStores.docs.docTooLargeFlag ? "This document is too large to display." : appStores.docs.docError
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Text {
              visible: !appStores.docs.docTooLargeFlag && appStores.docs.docError === ""
              width: parent.width
              text: appStores.docs.docText !== "" ? appStores.docs.docText : "Loading…"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              textFormat: Text.MarkdownText
            }
          }

          Column {
            id: detailCard
            visible: appStores.nav.viewMode === "entry" && !!appStores.board.cardMap[appStores.board.selectedCardId]
            width: parent.width
            spacing: Style.space(10)

            readonly property var card: appStores.board.cardMap[appStores.board.selectedCardId]

            DetailLink {
              visible: !!(detailCard.card && detailCard.card.parentId)
              width: parent.width
              prefix: "↑ "
              resolved: detailCard.card && detailCard.card.parentId
                ? appStores.board.resolvedCard(detailCard.card.parentId) : ({ title: "", status: "", inBoard: false })
              rowIndex: detailCard.card && detailCard.card.parentId ? appStores.board.linkIndex("parent", detailCard.card.parentId) : -1
              onActivated: if (resolved.inBoard) root.openCard(detailCard.card.parentId)
            }

            Text {
              width: parent.width
              text: detailCard.card ? detailCard.card.title : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              wrapMode: Text.WordWrap
            }

            Row {
              spacing: Style.space(6)

              Badge {
                text: detailCard.card ? Board.kindLabel(detailCard.card.depth) : ""
                tone: root.foreground
              }

              Badge {
                text: detailCard.card ? appStores.board.statusText(detailCard.card.status) : ""
                tone: detailCard.card ? Board.statusColor(detailCard.card.status, root.dim) : root.dim
              }
            }

            PanelSeparator { foreground: root.foreground }

            Text {
              width: parent.width
              text: (detailCard.card && detailCard.card.description) ? detailCard.card.description : "No description."
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              textFormat: Text.MarkdownText
            }

            PanelSectionHeader {
              visible: !!(detailCard.card && detailCard.card.blocked_by && detailCard.card.blocked_by.length > 0)
              text: "BLOCKED BY"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: (detailCard.card && detailCard.card.blocked_by) ? detailCard.card.blocked_by : []

              DetailLink {
                required property string modelData
                width: parent.width
                resolved: appStores.board.resolvedCard(modelData)
                rowIndex: appStores.board.linkIndex("blocker", modelData)
                onActivated: if (resolved.inBoard) root.openCard(modelData)
              }
            }

            PanelSectionHeader {
              visible: !!(detailCard.card && detailCard.card.children && detailCard.card.children.length > 0)
              text: "CHILDREN"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: (detailCard.card && detailCard.card.children) ? detailCard.card.children : []

              DetailLink {
                required property var modelData
                width: parent.width
                resolved: appStores.board.resolvedCard(modelData.id)
                rowIndex: appStores.board.linkIndex("child", modelData.id)
                onActivated: root.openCard(modelData.id)
              }
            }
          }
        }
      }

      // Delete confirmation: a modal card over a dimmed backdrop, above everything.
      Item {
        id: deleteModal
        objectName: "deleteModal"
        anchors.fill: parent
        z: 100
        visible: !!appStores.deleter.deleteTarget

        Rectangle {
          objectName: "deleteBackdrop"
          anchors.fill: parent
          color: Qt.rgba(0, 0, 0, 0.55)

          MouseArea {
            anchors.fill: parent
            onClicked: appStores.deleter.cancelDelete()
          }
        }

        Rectangle {
          id: deleteCard
          objectName: "deleteCard"
          anchors.centerIn: parent
          width: Math.min(Style.space(440), parent.width - Style.space(48))
          height: deleteColumn.implicitHeight + Style.space(36)
          radius: Style.space(10)
          color: Color.popups.background
          border.width: 1
          border.color: Color.popups.border

          MouseArea { anchors.fill: parent }

          Column {
            id: deleteColumn
            anchors.fill: parent
            anchors.margins: Style.space(18)
            spacing: Style.space(8)
            Text {
              width: parent.width
              text: "Type delete to permanently remove “" + (appStores.deleter.deleteTarget ? appStores.deleter.deleteTarget.name : "")
                + "” from brd. This can't be undone, but a snapshot of its board is saved first."
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: appStores.deleter.deleteTarget ? root.displayPath(appStores.deleter.deleteTarget.root_path) : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideMiddle
            }

            TextField {
              id: confirmField
              objectName: "confirmField"
              width: parent.width
              foreground: root.foreground
              placeholderText: "delete"
              enabled: !appStores.deleter.deleting
              text: appStores.deleter.confirmText

              onTextChanged: appStores.deleter.confirmText = text

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) { appStores.deleter.cancelDelete(); event.accepted = true; return }
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  appStores.deleter.performDelete(); event.accepted = true; return
                }
              }
            }

            Text {
              visible: appStores.deleter.deleteError !== ""
              width: parent.width
              text: appStores.deleter.deleteError
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Row {
              spacing: Style.spacing.md

              Button {
                text: "Cancel"
                enabled: !appStores.deleter.deleting
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: appStores.deleter.cancelDelete()
              }

              Button {
                text: appStores.deleter.deleting ? "Deleting…" : "Confirm delete"
                enabled: !appStores.deleter.deleting && Projects.isDeleteConfirmed(appStores.deleter.confirmText)
                opacity: enabled ? 1 : 0.5
                bordered: true
                foreground: root.urgent
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: appStores.deleter.performDelete()
              }
            }
          }
        }
      }

      TypedConfirmDialog {
        id: memoryConfirm
        anchors.fill: parent
        shown: root.memoryDeleteOpen
        message: "Type delete to permanently remove this memory note and its MEMORY.md entry. A backup is saved first."
        detail: root.selectedMemory
        busy: root.memoryBusy
        error: root.memoryDeleteError
        foreground: root.foreground
        urgent: root.urgent
        fontFamily: root.fontFamily
        onConfirmRequested: root.performMemoryDelete()
        onCancelRequested: root.cancelMemoryDelete()
      }

      NewMemoryDialog {
        id: newMemoryDialog
        anchors.fill: parent
        shown: root.newMemoryOpen
        busy: root.memoryBusy
        error: root.newMemoryError
        foreground: root.foreground
        urgent: root.urgent
        fontFamily: root.fontFamily
        onCreateRequested: function(name, type, description, body) { root.createMemory(name, type, description, body) }
        onCancelRequested: root.cancelNewMemory()
      }
    }
  }

  component Badge: Rectangle {
    id: badge
    property string text: ""
    property color tone: root.foreground

    visible: text !== ""
    width: implicitWidth
    height: implicitHeight
    implicitWidth: badgeLabel.implicitWidth + Style.space(14)
    implicitHeight: badgeLabel.implicitHeight + Style.space(4)
    radius: height / 2
    color: Qt.rgba(tone.r, tone.g, tone.b, 0.16)
    border.color: tone
    border.width: 1

    Text {
      id: badgeLabel
      anchors.centerIn: parent
      text: badge.text
      color: badge.tone
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  component DetailLink: CursorSurface {
    id: detailLink
    property var resolved: ({ title: "", status: "", inBoard: true })
    property int rowIndex: -1
    property string prefix: ""
    signal activated()

    hasCursor: rowIndex >= 0 && appStores.nav.cursorIndex === rowIndex
    onHasCursorChanged: if (hasCursor && appStores.nav.scrollOnCursor) root.scrollItemIntoView(detailLink)
    foreground: root.foreground
    implicitHeight: detailLinkLayout.implicitHeight + Style.spacing.rowPaddingX

    RowLayout {
      id: detailLinkLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)

      Text {
        Layout.fillWidth: true
        text: detailLink.prefix + detailLink.resolved.title + (detailLink.resolved.inBoard ? "" : " (not in this board)")
        color: detailLink.resolved.inBoard ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }

      Text {
        visible: detailLink.resolved.inBoard
        text: "[" + detailLink.resolved.status + "]"
        color: Board.statusColor(detailLink.resolved.status, root.dim)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: detailLink.resolved.inBoard ? Qt.PointingHandCursor : Qt.ArrowCursor
      onEntered: if (detailLink.rowIndex >= 0) root.hoverCursor(detailLink.rowIndex)
      onClicked: detailLink.activated()
    }
  }

  component BoardCard: CursorSurface {
    id: boardCard
    property int cardIndex: -1
    property string title: ""
    property string status: "todo"
    property var progress: ({ done: 0, total: 0 })
    signal activated()

    hasCursor: cardIndex >= 0 && appStores.nav.cursorIndex === cardIndex
    onHasCursorChanged: if (hasCursor && appStores.nav.scrollOnCursor) root.scrollItemIntoView(boardCard)
    foreground: root.foreground
    bordered: true
    implicitHeight: cardLayout.implicitHeight + Style.space(16)

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.margins: Style.space(4)
      width: Style.space(3)
      radius: width / 2
      color: Board.statusColor(boardCard.status, root.dim)
    }

    ColumnLayout {
      id: cardLayout
      anchors.fill: parent
      anchors.margins: Style.space(8)
      anchors.leftMargin: Style.space(14)
      spacing: Style.space(4)

      Text {
        Layout.fillWidth: true
        text: boardCard.title
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
      }

      Text {
        visible: boardCard.status === "blocked"
        text: "Blocked"
        color: Board.statusColor("blocked", root.dim)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      Text {
        visible: boardCard.progress.total > 0
        text: boardCard.progress.done + "/" + boardCard.progress.total + " done"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: if (boardCard.cardIndex >= 0) root.hoverCursor(boardCard.cardIndex)
      onClicked: boardCard.activated()
    }
  }
}
