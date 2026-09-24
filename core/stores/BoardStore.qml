import QtQml
import Quickshell
import Quickshell.Io
import "../domain/board.js" as Board

// The kanban board: the card tree from `brd tree`, what is visible once the
// search has been applied, and which card is open. The project, the watched
// database and the navigation values it needs are handed to it by App -- it
// never reaches for another store. Scrolling and focus stay in the panel.
Scope {
  id: board

  property var project: null          // set by App from ProjectStore.selectedProject
  property string dbPath: ""          // set by App from ProjectStore.watchedDbPath
  property string viewMode: "board"   // set by App from NavigationStore.viewMode
  property string searchQuery: ""     // set by App from NavigationStore.searchQuery

  property var cardRoots: []   // top-level cards from the last brd tree fetch
  property var cardMap: ({})   // id -> card, from Board.indexTree
  readonly property var statuses: ["todo", "in_progress", "done"]
  property string selectedCardId: ""

  readonly property alias treeProc: treeProc
  readonly property alias dbFile: dbFile

  // The board could not be read, or was read again: the message the panel
  // shows lives on the project store, which App keeps in step.
  signal errored(string message)
  // The open card is gone from the tree: the panel puts its list back.
  signal listViewRequested()

  function fetchBoard() {
    if (!board.project) return
    board.errored("")
    treeProc.workingDirectory = board.project.root_path
    treeProc.running = false
    treeProc.running = true
  }

  function applyTreeData(roots) {
    board.cardRoots = roots
    var indexed = Board.indexTree(roots)
    board.cardMap = indexed.cardMap
    if (board.viewMode === "entry" && !board.cardMap[board.selectedCardId]) board.listViewRequested()
  }

  readonly property var visibleBoardRoots: board.cardRoots.filter(function(c) {
    return Board.subtreeMatches(c, board.searchQuery)
  })

  function boardColumn(status) {
    return board.visibleBoardRoots.filter(function(c) {
      return Board.effectiveStatus(c) === status
    })
  }

  // All visible Board cards as one list, section by section: the order the
  // keyboard cursor walks them in.
  readonly property var boardCards: Board.boardOrder(board.visibleBoardRoots, board.statuses)

  // The clickable rows of the card being viewed, in display order.
  readonly property var detailLinkList: board.viewMode === "entry"
    ? Board.detailLinks(board.cardMap[board.selectedCardId], board.cardMap) : []

  function boardIndexOf(id) {
    for (var i = 0; i < board.boardCards.length; i++)
      if (board.boardCards[i].id === id) return i
    return -1
  }

  function linkIndex(section, id) {
    for (var i = 0; i < board.detailLinkList.length; i++)
      if (board.detailLinkList[i].section === section && board.detailLinkList[i].id === id) return i
    return -1
  }

  function statusText(status) {
    if (status === "todo") return "Todo"
    if (status === "in_progress") return "In progress"
    if (status === "done") return "Done"
    if (status === "blocked") return "Blocked"
    return String(status || "")
  }

  function statusLabel(status) {
    if (status === "todo") return "Todo"
    if (status === "in_progress") return "In Progress"
    return "Done"
  }

  // Selects a card, and says whether there was one to select: the navigation
  // bookkeeping around it is the panel's.
  function openCard(id) {
    if (!board.cardMap[id]) return false
    board.selectedCardId = id
    return true
  }

  function resolvedCard(id) {
    var card = board.cardMap[id]
    return card ? { id: id, title: card.title, status: card.status, inBoard: true }
                : { id: id, title: id, status: "", inBoard: false }
  }

  FileView {
    id: dbFile
    objectName: "dbFile"
    path: board.dbPath !== "" ? board.dbPath : ""
    watchChanges: true
    printErrors: false
    onFileChanged: board.fetchBoard()
  }

  Process {
    id: treeProc
    objectName: "treeProc"
    command: ["brd", "tree"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text || "{}")
          board.errored("")
          board.applyTreeData(parsed.data || [])
        } catch (e) {
          board.applyTreeData([])
          board.errored("Could not load the board for this project.")
        }
      }
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        board.applyTreeData([])
        board.errored("Could not load the board for this project.")
      }
    }
  }
}
