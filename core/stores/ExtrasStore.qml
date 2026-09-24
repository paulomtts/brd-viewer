import QtQml
import Quickshell
import Quickshell.Io
import "../domain/brd-extras.js" as Extras
import "../domain/board.js" as Board

// The read-only extras `brd export` carries: the issues with their bodies and
// blocks, every entity's comments, and the ref graph. Fetched with the board
// (project select, database change, Refresh), and a failure -- an old brd
// without `export`, a crash, garbage -- is simply no extras: the board, its
// blocker rows and the graph are fed by BoardStore's own `brd issue list` and
// must never be affected. The project, the card/issue maps and the navigation
// values it needs are handed to it by App; it never reaches for another store.
Scope {
  id: extras

  property var project: null          // set by App from ProjectStore.selectedProject
  property var cardMap: ({})          // set by App from BoardStore.cardMap
  property var issueMap: ({})         // set by App from BoardStore.issueMap
  property string viewMode: "board"   // set by App from NavigationStore.viewMode
  property string searchQuery: ""     // set by App from NavigationStore.searchQuery

  property var issues: []
  property var commentsByEntity: ({})
  property var refsByEntity: ({})
  property bool extrasLoading: false
  property string selectedIssueId: ""

  readonly property string issueStatus: issueFilter.active
  readonly property alias issueFilter: issueFilter
  readonly property alias exportProc: exportProc

  // The open issue is gone from the export: the panel puts its list back.
  signal listViewRequested()
  // The status filter changed: a different list, so the cursor goes home.
  signal statusToggled()

  readonly property var filteredIssues:
    Extras.searchIssues(Extras.filterIssues(extras.issues, extras.issueStatus), extras.searchQuery)

  readonly property var statusCounts: Extras.issueStatusCounts(extras.issues)

  readonly property var selectedIssue: {
    for (var i = 0; i < extras.issues.length; i++)
      if (extras.issues[i].id === extras.selectedIssueId) return extras.issues[i]
    return null
  }

  readonly property var detailLinkList: extras.viewMode === "issue"
    ? Extras.issueDetailLinks(extras.selectedIssue, extras.cardMap, extras.issueMap, extras.refsByEntity) : []

  function fetchExtras() {
    if (!extras.project) return
    extras.extrasLoading = true
    exportProc.workingDirectory = extras.project.root_path
    exportProc.running = false
    exportProc.running = true
  }

  // `launchedGuard` is the project root the fetch was launched for: a reply for
  // a project the user has since left is dropped, but the loading flag still
  // clears, or nothing would ever clear it again.
  function applyExportResult(stdout, exitCode, launchedGuard) {
    extras.extrasLoading = false
    var guard = launchedGuard === undefined ? extras.currentGuard() : launchedGuard
    if (guard !== extras.currentGuard()) return
    // The whole export is parsed, cards included: an exported issue carries no
    // `blocks` of its own, the relation is read back off the card tree.
    var parsed = Extras.parseExport(stdout, exitCode)
    extras.issues = parsed.issues
    extras.commentsByEntity = parsed.commentsByEntity
    extras.refsByEntity = parsed.refsByEntity
    if (extras.viewMode === "issue" && !extras.selectedIssue) extras.listViewRequested()
  }

  function currentGuard() {
    return extras.project ? extras.project.root_path : ""
  }

  function toggleIssueStatus(id) {
    issueFilter.toggle(id)
  }

  function commentsFor(entityId) {
    return extras.commentsByEntity[entityId] || []
  }

  // What a link row shows for an id: a card of this board, else a known issue,
  // else the bare id -- the same resolution the card detail uses.
  function resolvedTarget(id) {
    return Board.resolvedCard(id, extras.cardMap, extras.issueMap)
  }

  // Selects an issue, and says whether there was one to select: the navigation
  // bookkeeping around it is the panel's.
  function openIssue(id) {
    if (!id) return false
    for (var i = 0; i < extras.issues.length; i++) {
      if (extras.issues[i].id === id) { extras.selectedIssueId = id; return true }
    }
    return false
  }

  function restoreIssuesList() {
    extras.selectedIssueId = ""
  }

  function issueIndexOf(id) {
    for (var i = 0; i < extras.filteredIssues.length; i++)
      if (extras.filteredIssues[i].id === id) return i
    return -1
  }

  function linkIndex(section, id) {
    for (var i = 0; i < extras.detailLinkList.length; i++)
      if (extras.detailLinkList[i].section === section && extras.detailLinkList[i].id === id) return i
    return -1
  }

  function reset() {
    extras.issues = []
    extras.commentsByEntity = ({})
    extras.refsByEntity = ({})
    extras.selectedIssueId = ""
    extras.extrasLoading = false
    issueFilter.clear()
  }

  FilterState {
    id: issueFilter
    onToggled: extras.statusToggled()
  }

  // A brd CLI call, like treeProc and issueProc: a plain Process with its own
  // exit handling (HelperRunner only ever runs python3 helpers).
  Process {
    id: exportProc
    objectName: "exportProc"
    command: ["brd", "export"]
    property string launchGuard: ""
    onRunningChanged: if (running) launchGuard = extras.currentGuard()
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: extras.applyExportResult(String(text || ""), 0, exportProc.launchGuard)
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) extras.applyExportResult("", exitCode, exportProc.launchGuard)
    }
  }
}
