import QtQml
import Quickshell
import Quickshell.Io
import "../domain/documents.js" as Documents
import "../domain/brd-extras.js" as Extras

// The project's documents: the listing (list-docs.py), the category filter, the
// open document with its live text, and its type tag (set-doc-tag.py). The
// project and the navigation values it needs are handed to it by App -- it never
// reaches for another store. Scrolling, focus and the view mode stay in the panel.
Scope {
  id: store

  property string backendDir: ""      // <plugin>/core/backend/
  property var project: null          // set by App from ProjectStore.selectedProject
  property string viewMode: "board"   // set by App from NavigationStore.viewMode
  property string searchQuery: ""     // set by App from NavigationStore.searchQuery

  property var docs: []
  property bool docsLoading: false
  property string docsError: ""
  property bool docsTruncated: false
  property string selectedDocPath: ""
  property string docText: ""
  property string docError: ""
  property bool docTooLargeFlag: false
  property bool docTagBusy: false
  property string docTagError: ""
  // What `brd doc list` last said, and whether the open document is one of
  // brd's registrations with no file on disk.
  property var registeredDocs: []
  property bool selectedDocMissing: false

  readonly property string docCategory: category.active
  readonly property alias category: category
  readonly property alias lister: lister
  readonly property alias tagger: tagger
  readonly property alias docFile: docFile
  readonly property alias brdDocsProc: brdDocsProc

  // Latest run wins, like the extras export: every fetch takes the next
  // sequence number, so a reply a newer run has already superseded is dropped.
  property int brdDocsSeq: 0

  // The category filter changed: the list the panel shows is a different one,
  // so the cursor goes back to the first row and the list scrolls to the top.
  signal categoryToggled()

  readonly property string selectedDocCategory: {
    for (var i = 0; i < store.docs.length; i++)
      if (store.docs[i].path === store.selectedDocPath) return store.docs[i].category || ""
    return ""
  }

  // The listing plus brd's registrations: what the section actually shows.
  readonly property var mergedDocs: Documents.mergeRegistered(store.docs, store.registeredDocs)

  readonly property var selectedDocBrd: {
    for (var i = 0; i < store.mergedDocs.length; i++)
      if (store.mergedDocs[i].path === store.selectedDocPath) return store.mergedDocs[i].brd
    return null
  }

  readonly property var filteredDocs: Documents.filterDocs(
    Documents.filterDocsByCategory(store.mergedDocs, store.docCategory), store.searchQuery)

  function toggleDocCategory(id) {
    category.toggle(id)
  }

  function fetchDocs() {
    if (!store.project) return
    store.docs = []
    store.docsError = ""
    store.docsTruncated = false
    store.docsLoading = true
    lister.run([store.project.root_path])
  }

  function applyDocsResult(text, exitCode) {
    var result = Documents.parseDocsResult(text, exitCode)
    store.docsLoading = false
    store.docs = result.docs
    store.docsTruncated = result.truncated
    store.docsError = result.ok ? "" : result.error
  }

  // `brd doc list` SYNCS EVERY BACKUP as a side effect -- it writes. So it runs
  // only when the Documents section is opened, never from fetchDocs(), never
  // from the database watch, never after a type change.
  function fetchRegisteredDocs() {
    if (!store.project) return
    store.brdDocsSeq += 1
    brdDocsProc.launchSeq = store.brdDocsSeq
    brdDocsProc.launchGuard = store.project.root_path
    brdDocsProc.outText = ""
    brdDocsProc.workingDirectory = store.project.root_path
    brdDocsProc.running = false
    brdDocsProc.running = true
  }

  // `launchedSeq` and `launchedGuard` are the run's own: a superseded run and a
  // run launched for a project the user has since left both change nothing.
  // A failure is no answer at all -- brd's documents are extra, so what it last
  // said stands and the documents listing is never touched by it.
  function applyRegisteredResult(stdout, exitCode, launchedGuard, launchedSeq) {
    if ((launchedSeq === undefined ? store.brdDocsSeq : launchedSeq) !== store.brdDocsSeq) return
    var guard = launchedGuard === undefined ? store.currentGuard() : launchedGuard
    if (guard !== store.currentGuard()) return
    var result = Extras.parseDocList(stdout, exitCode)
    if (result.ok) store.registeredDocs = result.registered
  }

  function currentGuard() {
    return store.project ? store.project.root_path : ""
  }

  // Selects a document, and says whether there was one to select: the
  // navigation bookkeeping around it is the panel's.
  function openDoc(path) {
    var entry = null
    for (var i = 0; i < store.mergedDocs.length; i++) if (store.mergedDocs[i].path === path) entry = store.mergedDocs[i]
    if (!entry || !store.project) return false
    store.selectedDocPath = path
    store.selectedDocMissing = entry.missing === true
    store.docTagError = ""
    store.docText = ""
    store.docError = ""
    store.docTooLargeFlag = Documents.docTooLarge(entry.size)
    return true
  }

  function restoreDocumentsList() {
    store.docTagError = ""
    store.selectedDocPath = ""
    store.selectedDocMissing = false
    store.docText = ""
    store.docError = ""
    store.docTooLargeFlag = false
  }

  // Writes the `tag:` line of the open document (set-doc-tag.py, which checks
  // the path and replaces the file atomically); the list is re-read afterwards
  // so badges and filters follow.
  function setDocTag(id) {
    if (store.viewMode !== "document" || !store.project || store.docTagBusy) return
    if (["architecture", "specs", "standards", "audits", "default"].indexOf(id) < 0) return
    store.docTagError = ""
    store.docTagBusy = true
    tagger.run([store.project.root_path, store.selectedDocPath, id])
  }

  function applyDocTagResult(text, exitCode) {
    var result = Documents.parseTagResult(text, exitCode)
    store.docTagBusy = false
    if (result.ok) store.fetchDocs()
    else store.docTagError = result.error
  }

  // Everything the old project left behind, on a project change. A type change
  // still in flight belongs to the project the user has left: its reply will be
  // dropped by the tagger's guard, so the lock is released here -- nothing else
  // would ever clear it again.
  function reset() {
    store.docs = []
    store.registeredDocs = []
    store.selectedDocMissing = false
    category.clear()
    store.docTagBusy = false
    store.docTagError = ""
    store.docsError = ""
    store.docsLoading = false
    store.selectedDocPath = ""
    store.docText = ""
    store.docError = ""
    store.docTooLargeFlag = false
  }

  FilterState {
    id: category
    onToggled: store.categoryToggled()
  }

  // The guard is the selected project's root: a listing launched for a project
  // the user has since left can never be applied.
  HelperRunner {
    id: lister
    script: store.backendDir + "documents/list-docs.py"
    guard: store.project ? store.project.root_path : ""
    onFinished: function(stdout, exitCode, launchedGuard) { store.applyDocsResult(stdout, exitCode) }
  }

  HelperRunner {
    id: tagger
    script: store.backendDir + "documents/set-doc-tag.py"
    guard: store.project ? store.project.root_path : ""
    onFinished: function(stdout, exitCode, launchedGuard) { store.applyDocTagResult(stdout, exitCode) }
  }

  // A brd CLI call, like treeProc and issueProc: a plain Process with its own
  // exit handling (HelperRunner only ever runs python3 helpers). The collector
  // only stashes what it read; the exit code is what decides, so a good line
  // from a run that then failed never comes out as registrations with a faked 0.
  Process {
    id: brdDocsProc
    objectName: "brdDocsProc"
    command: ["brd", "doc", "list"]
    property int launchSeq: 0
    property string launchGuard: ""
    property string outText: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: brdDocsProc.outText = String(text || "") }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      store.applyRegisteredResult(brdDocsProc.outText, exitCode, brdDocsProc.launchGuard, brdDocsProc.launchSeq)
    }
  }

  FileView {
    id: docFile
    objectName: "docFile"
    path: store.viewMode === "document" && !store.docTooLargeFlag && !store.selectedDocMissing
      && store.project && store.selectedDocPath !== ""
      ? Documents.docAbsolutePath(store.project.root_path, store.selectedDocPath) : ""
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { store.docError = ""; store.docText = Documents.stripFrontmatter(docFile.text()) }
    onLoadFailed: {
      if (docFile.path === "" || !store.project || store.selectedDocPath === "") return
      if (docFile.path === Documents.docAbsolutePath(store.project.root_path, store.selectedDocPath))
        store.docError = "Could not read this document."
    }
  }
}
