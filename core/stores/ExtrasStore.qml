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

  // Latest run wins, like HelperRunner: every fetch takes the next sequence
  // number and its own Process carrying it, so a late reply from a run that has
  // since been superseded -- the same project fetched twice in a row -- can
  // never be mistaken for the current one.
  property int seq: 0
  property var exportProc: null   // the newest run's Process

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
    if (extras.exportProc) extras.exportProc.running = false
    extras.seq += 1
    extras.extrasLoading = true
    var proc = procC.createObject(extras, { launchSeq: extras.seq, launchGuard: extras.currentGuard() })
    proc.workingDirectory = extras.project.root_path
    extras.exportProc = proc
    proc.running = true
  }

  // `launchedSeq` and `launchedGuard` are the run's own: a reply a newer run has
  // already superseded changes nothing at all (that newer run still holds the
  // loading flag), and a reply for a project the user has since left is dropped
  // -- but the newest run still clears the flag, or nothing ever would again.
  function applyExportResult(stdout, exitCode, launchedGuard, launchedSeq) {
    if ((launchedSeq === undefined ? extras.seq : launchedSeq) !== extras.seq) return
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
  // exit handling (HelperRunner only ever runs python3 helpers), one per run.
  // The collector only stashes what it read; the exit is what decides, so a
  // perfectly good line from a run that then failed is read with its real exit
  // code and comes out as no extras -- never as extras with a faked 0.
  Component {
    id: procC

    Process {
      id: p
      objectName: "exportProc"
      command: ["brd", "export"]
      property int launchSeq: 0
      property string launchGuard: ""
      property string outText: ""
      stdout: StdioCollector { waitForEnd: true; onStreamFinished: p.outText = String(text || "") }
      stderr: StdioCollector { waitForEnd: true }
      onExited: function(exitCode) {
        extras.applyExportResult(p.outText, exitCode, p.launchGuard, p.launchSeq)
        // The newest run stays reachable as `exportProc`; an older one is done.
        if (extras.exportProc !== p) p.destroy()
      }
    }
  }
}
