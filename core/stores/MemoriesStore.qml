import QtQml
import Quickshell
import Quickshell.Io
import "../domain/memories.js" as Memories

// The project's Claude Code memory notes: the listing (list-memories.py), the
// type filter, the open note with its live text and its editor draft, and the
// save/create/delete operations (memory-op.py, which backs up before every
// change). The project and the navigation values it needs are handed to it by
// App -- it never reaches for another store. Scrolling, focus, the view mode
// and the dirty-draft guards stay in the panel.
Scope {
  id: store

  property string backendDir: ""      // <plugin>/core/backend/
  property var project: null          // set by App from ProjectStore.selectedProject
  property string viewMode: "board"   // set by App from NavigationStore.viewMode
  property string searchQuery: ""     // set by App from NavigationStore.searchQuery

  property var memories: []
  property bool memoriesLoading: false
  property string memoriesError: ""
  property bool memoriesFound: true
  property string memoryDir: ""
  property string selectedMemory: ""
  property string memoryText: ""
  property string memoryReadError: ""
  property bool memoryEditing: false
  property string memoryDraft: ""
  property string memoryEditBase: ""
  property string memoryOpError: ""
  property bool newMemoryOpen: false
  property string newMemoryError: ""
  property bool memoryDeleteOpen: false
  property string memoryDeleteError: ""
  property string pendingMemoryOpen: ""

  // What the operation in flight is for: recorded at launch so a reply that
  // belongs to a project the user has left can be told apart.
  property string op: ""
  property string forRoot: ""
  property string forFile: ""

  // One operation at a time, from its launch until the helper's own exit --
  // even when the user has left the project meanwhile.
  readonly property bool memoryBusy: operator.busy

  readonly property string memoryType: typeFilter.active
  readonly property alias type: typeFilter
  readonly property alias lister: lister
  readonly property alias operator: operator
  readonly property alias memoryFile: memoryFile

  // The type filter changed: the list the panel shows is a different one, so
  // the cursor goes back to the first row and the list scrolls to the top.
  signal typeToggled()
  // A note the panel should open (the one just created, once the refreshed
  // listing knows about it): the navigation bookkeeping is the panel's.
  signal noteOpenRequested(string file)
  // The open note is gone (it was just deleted): the panel puts its list back.
  signal listRestoreRequested()
  // The state behind the focused item changed.
  signal focusRequested()

  readonly property var memoryTypes: Memories.memoryTypeCounts(store.memories)
  readonly property var filteredMemories: Memories.filterMemories(Memories.filterMemoriesByType(store.memories, store.memoryType), store.searchQuery)
  readonly property bool canCreateMemory: store.memoryDir !== ""
  readonly property var selectedMemoryEntry: {
    for (var i = 0; i < store.memories.length; i++)
      if (store.memories[i].file === store.selectedMemory) return store.memories[i]
    return { file: store.selectedMemory, name: store.selectedMemory, description: "", type: "other" }
  }

  // Everything the old project left behind, on a project change. An operation
  // still in flight is deliberately left alone: it belongs to the project the
  // user has left, its reply will be dropped by the operator's guard, and its
  // exit is what releases `memoryBusy`.
  function resetMemories() {
    lister.cancel()
    store.memories = []; store.memoriesError = ""; store.memoriesLoading = false; store.memoriesFound = true
    store.memoryDir = ""; typeFilter.clear(); store.selectedMemory = ""; store.memoryText = ""
    store.memoryReadError = ""; store.memoryEditing = false; store.memoryDraft = ""; store.memoryOpError = ""
    store.newMemoryOpen = false; store.newMemoryError = ""; store.memoryDeleteOpen = false; store.memoryDeleteError = ""
    store.pendingMemoryOpen = ""
  }

  function fetchMemories() {
    if (!store.project) return
    store.memoriesError = ""
    store.memoriesLoading = true
    lister.run([store.project.root_path])
  }

  function applyMemoriesResult(text, exitCode) {
    var result = Memories.parseMemoriesResult(text, exitCode)
    store.memoriesLoading = false
    store.memories = result.notes
    store.memoriesFound = result.found
    if (result.ok) store.memoryDir = result.memoryDir
    store.memoriesError = result.ok ? "" : result.error
    if (store.pendingMemoryOpen !== "") {
      var file = store.pendingMemoryOpen
      store.pendingMemoryOpen = ""
      if (store.viewMode === "memories") store.noteOpenRequested(file)
    }
  }

  function toggleMemoryType(id) {
    typeFilter.toggle(id)
  }

  // Selects a note, and says whether there was one to select: the navigation
  // bookkeeping around it is the panel's.
  function openMemory(file) {
    var known = false
    for (var i = 0; i < store.memories.length; i++) if (store.memories[i].file === file) known = true
    if (!known || !store.project || store.memoryDir === "") return false
    store.selectedMemory = file
    store.memoryText = ""
    store.memoryReadError = ""
    store.memoryEditing = false
    store.memoryDraft = ""
    store.memoryOpError = ""
    return true
  }

  function restoreMemoriesList() {
    store.selectedMemory = ""
    store.memoryText = ""
    store.memoryReadError = ""
    store.memoryEditing = false
    store.memoryDraft = ""
    store.memoryOpError = ""
  }

  function setMemoryText(text) {
    store.memoryText = text
    store.memoryReadError = ""
  }

  function startMemoryEdit() {
    if (store.viewMode !== "memory" || store.memoryEditing || store.memoryBusy || store.memoryText === "") return
    store.memoryEditing = true
    store.memoryDraft = store.memoryText
    store.memoryEditBase = store.memoryText
    store.memoryOpError = ""
    store.focusRequested()
  }

  function cancelMemoryEdit() {
    if (store.memoryBusy) return
    store.memoryEditing = false
    store.memoryDraft = ""
    store.memoryOpError = ""
    store.focusRequested()
  }

  // Escape never throws edits away: a dirty draft stays until Cancel is chosen.
  function memoryEscape() {
    if (!store.memoryEditing) return
    if (store.memoryDraft === store.memoryText) store.cancelMemoryEdit()
    else store.memoryOpError = "You have unsaved changes. Save them, or choose Cancel to discard."
  }

  function runMemoryOp(op, file, content, expected) {
    store.op = op
    store.forRoot = store.project ? store.project.root_path : ""
    store.forFile = file
    var args = [op, store.memoryDir, file]
    if (content !== undefined) args.push(content)
    if (expected !== undefined) args.push(expected)
    operator.run(args)
  }

  // The text the editor was opened with goes along, so memory-op.py can refuse
  // a save that would silently overwrite someone else's change.
  function saveMemory() {
    if (!store.memoryEditing || store.memoryBusy || store.memoryDir === "" || store.memoryDraft === store.memoryText) return
    store.memoryOpError = ""
    store.runMemoryOp("save", store.selectedMemory, store.memoryDraft, store.memoryEditBase)
  }

  function openNewMemory() {
    if (!store.canCreateMemory || store.memoryBusy || store.viewMode !== "memories") return
    store.newMemoryOpen = true
    store.newMemoryError = ""
    store.focusRequested()
  }

  function cancelNewMemory() {
    if (store.memoryBusy) return
    store.newMemoryOpen = false
    store.focusRequested()
  }

  function createMemory(name, type, description, body) {
    if (store.memoryBusy || store.memoryDir === "" || String(name).trim() === "") return
    var file = Memories.newMemoryFile(type, name, store.memories.map(function(n) { return n.file }))
    store.newMemoryError = ""
    store.runMemoryOp("create", file, Memories.composeMemory(name, description, type, body))
  }

  function requestMemoryDelete() {
    if (store.viewMode !== "memory" || store.selectedMemory === "" || store.memoryBusy) return
    store.memoryDeleteOpen = true
    store.memoryDeleteError = ""
    store.focusRequested()
  }

  function cancelMemoryDelete() {
    if (store.memoryBusy) return
    store.memoryDeleteOpen = false
    store.focusRequested()
  }

  function performMemoryDelete() {
    if (!store.memoryDeleteOpen || store.memoryBusy || store.selectedMemory === "" || store.memoryDir === "") return
    store.memoryDeleteError = ""
    store.runMemoryOp("delete", store.selectedMemory)
  }

  function applyMemoryOpResult(text, exitCode) {
    var result = Memories.parseMemoryOpResult(text, exitCode)
    var op = store.op
    var sameProject = store.project && store.project.root_path === store.forRoot
    if (!sameProject) return
    if (op === "save") {
      if (result.ok) {
        store.memoryText = store.memoryDraft
        store.memoryEditing = false
        store.memoryDraft = ""
        store.fetchMemories()
      } else store.memoryOpError = result.error
    } else if (op === "create") {
      if (result.ok) {
        store.newMemoryOpen = false
        store.pendingMemoryOpen = store.forFile
        store.fetchMemories()
      } else store.newMemoryError = result.error
    } else if (op === "delete") {
      if (result.ok) {
        store.memoryDeleteOpen = false
        store.listRestoreRequested()
        store.fetchMemories()
      } else store.memoryDeleteError = result.error
    }
    store.focusRequested()
  }

  FilterState {
    id: typeFilter
    onToggled: store.typeToggled()
  }

  // The guard is the selected project's root: a listing launched for a project
  // the user has since left can never be applied.
  HelperRunner {
    id: lister
    script: store.backendDir + "memories/list-memories.py"
    guard: store.project ? store.project.root_path : ""
    onFinished: function(stdout, exitCode, launchedGuard) { store.applyMemoriesResult(stdout, exitCode) }
  }

  HelperRunner {
    id: operator
    script: store.backendDir + "memories/memory-op.py"
    guard: store.project ? store.project.root_path : ""
    onFinished: function(stdout, exitCode, launchedGuard) { store.applyMemoryOpResult(stdout, exitCode) }
  }

  FileView {
    id: memoryFile
    objectName: "memoryFile"
    path: store.viewMode === "memory" && store.memoryDir !== "" && store.selectedMemory !== ""
      ? Memories.memoryAbsolutePath(store.memoryDir, store.selectedMemory) : ""
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: store.setMemoryText(memoryFile.text())
    onLoadFailed: if (memoryFile.path !== "") store.memoryReadError = "Could not read this memory."
  }
}
