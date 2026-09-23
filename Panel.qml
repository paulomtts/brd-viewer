import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "logic.js" as Logic

// Browses brd's local kanban board (`brd projects` / `brd tree`), per
// project: pick a project, then view its cards as a Board.
// Read-only -- nothing here ever calls brd add/update/delete/block.
Panel {
  id: root
  moduleName: "paulomtts.brd-viewer"
  ipcTarget: "paulomtts.brd-viewer"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")

  property string viewMode: "board"   // "board" | "entry" | "documents" | "document"
  property bool dropdownOpen: false
  property string dropdownQuery: ""
  property int dropdownCursor: 0
  property string storedProject: ""
  property bool stateLoaded: false

  readonly property string section: (viewMode === "documents" || viewMode === "document") ? "documents" : "board"
  readonly property string sectionTitle: section === "documents" ? "Documents" : "Board"
  readonly property bool documentsEnabled: false   // Task 11 turns this on
  property var projects: []            // [{ root_path, name }]
  property var selectedProject: null   // { root_path, name } | null
  property string loadError: ""

  property string searchQuery: ""
  property int cursorIndex: 0
  // True only while the keyboard is driving the cursor: rows then scroll
  // themselves into view. Hover must not scroll, or the list would move
  // under a stationary pointer and re-trigger hover.
  property bool scrollOnCursor: false

  // Deleting a project (brd forget). Always gated behind typing "delete", and
  // snapshot-and-forget.py saves a snapshot first and refuses to forget if it
  // cannot.
  property var deleteTarget: null      // { root_path, name } | null
  property string confirmText: ""
  property bool deleting: false
  property string deleteError: ""
  property string lastSnapshot: ""
  property int returnCursor: 0
  property real returnScrollY: 0

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

  readonly property var filteredProjects: Logic.filterProjects(root.projects, root.dropdownQuery)

  function currentList() {
    if (root.viewMode === "board") return root.boardCards
    if (root.viewMode === "entry") return root.detailLinkList
    return []
  }

  readonly property Item focusItem: root.deleteTarget ? confirmField
    : root.dropdownOpen ? sidebar.filterItem
    : (root.viewMode === "entry" || root.viewMode === "document" || !root.selectedProject) ? keyCatcher
    : searchField

  function focusForView() {
    Qt.callLater(function() {
      if (!root.opened) return
      if (root.focusItem) root.focusItem.forceActiveFocus()
    })
  }

  function resetSearch() {
    searchQuery = ""
    cursorIndex = 0
  }

  function moveCursor(delta) {
    var list = root.currentList()
    if (list.length === 0) return
    root.scrollOnCursor = true
    root.cursorIndex = root.clamp(root.cursorIndex + delta, 0, list.length - 1)
    // Headers and the search box live inside the flickable; reaching the
    // first row of a list should reveal them again.
    if (root.cursorIndex === 0 && root.viewMode !== "entry") Qt.callLater(root.scrollToTop)
  }

  function hoverCursor(index) {
    root.scrollOnCursor = false
    root.cursorIndex = index
  }

  function scrollToTop() {
    if (panelFlick) panelFlick.contentY = 0
  }

  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
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
    if (root.cursorIndex < 0 || root.cursorIndex >= list.length) return
    root.openCard(list[root.cursorIndex].id)
  }

  function openDelete(project) {
    if (root.deleting || !project) return
    root.dropdownOpen = false
    root.deleteTarget = project
    root.confirmText = ""
    root.deleteError = ""
    root.lastSnapshot = ""
    root.focusForView()
  }

  function cancelDelete() {
    if (root.deleting) return
    root.deleteTarget = null
    root.confirmText = ""
    root.deleteError = ""
    root.focusForView()
  }

  function performDelete() {
    if (root.deleting || !root.deleteTarget) return
    if (!Logic.isDeleteConfirmed(root.confirmText)) return
    root.deleteError = ""
    root.deleting = true
    deleteProc.command = ["python3", root.pluginDir + "snapshot-and-forget.py",
      root.deleteTarget.root_path, root.deleteTarget.name]
    deleteProc.running = true
  }

  function displayPath(path) {
    return String(path || "").replace(/^\/home\/[^\/]+/, "~")
  }

  function refreshProjects() {
    loadError = ""
    listProc.running = false
    listProc.running = true
  }

  property var cardRoots: []   // top-level cards from the last brd tree fetch
  property var cardMap: ({})   // id -> card, from Logic.indexTree
  readonly property var statuses: ["todo", "in_progress", "done"]

  // The panel was just opened: refresh the registry and drop any half-finished
  // UI state. The project on screen stays selected while it is still registered.
  function onPanelOpened() {
    root.dropdownOpen = false
    root.dropdownQuery = ""
    if (!root.deleting) { root.deleteTarget = null; root.confirmText = ""; root.deleteError = "" }
    root.refreshProjects()
    root.focusForView()
  }
  onOpenedChanged: if (opened) onPanelOpened()

  function applyProjectsList(list) {
    root.projects = list
    root.maybeSelectInitial()
  }

  function maybeSelectInitial() {
    if (!root.stateLoaded) return
    var current = root.selectedProject ? root.selectedProject.root_path : ""
    var chosen = Logic.chooseProject(root.projects, current, root.storedProject)
    if (!chosen) { root.clearSelection(); return }
    if (chosen.root_path !== root.storedProject) root.persistLastProject(chosen.root_path)
    if (chosen.root_path !== current) root.selectProject(chosen)
    else root.selectedProject = chosen
  }

  function clearSelection() {
    root.selectedProject = null
    root.watchedDbPath = ""
    root.applyTreeData([])
    root.viewMode = "board"
  }

  function selectProject(project) {
    selectedProject = project
    resetSearch()
    viewMode = "board"
    root.watchedDbPath = ""
    resolveDbPathProc.command = ["python3", root.pluginDir + "resolve-db-path.py", project.root_path]
    resolveDbPathProc.running = false
    resolveDbPathProc.running = true
    fetchBoard()
    focusForView()
  }

  // The user picked a project in the dropdown.
  function chooseProject(project) {
    root.closeDropdown()
    if (!project) return
    root.lastSnapshot = ""
    var current = root.selectedProject ? root.selectedProject.root_path : ""
    if (project.root_path !== current) {
      root.selectProject(project)
      root.persistLastProject(project.root_path)
    }
    root.focusForView()
  }

  function applyStoredState(text, exitCode) {
    root.storedProject = Logic.parseStateResult(text, exitCode) || ""
    root.stateLoaded = true
    root.maybeSelectInitial()
  }

  function persistLastProject(path) {
    root.storedProject = path
    saveStateProc.command = ["python3", root.pluginDir + "viewer-state.py", "set-project", path]
    saveStateProc.running = false
    saveStateProc.running = true
  }

  function toggleDropdown() {
    if (root.deleteTarget) return
    if (root.dropdownOpen) { root.closeDropdown(); return }
    root.dropdownQuery = ""
    var index = 0
    for (var i = 0; i < root.projects.length; i++)
      if (root.selectedProject && root.projects[i].root_path === root.selectedProject.root_path) index = i
    root.dropdownCursor = index
    root.dropdownOpen = true
    root.focusForView()
  }

  function closeDropdown() {
    if (!root.dropdownOpen) return
    root.dropdownOpen = false
    root.dropdownQuery = ""
    root.focusForView()
  }

  function moveDropdown(delta) {
    var n = root.filteredProjects.length
    if (n === 0) return
    root.dropdownCursor = root.clamp(root.dropdownCursor + delta, 0, n - 1)
  }

  function acceptDropdown() {
    var list = root.filteredProjects
    if (root.dropdownCursor < 0 || root.dropdownCursor >= list.length) return
    root.chooseProject(list[root.dropdownCursor])
  }

  function showSection(name) {
    if (!root.selectedProject || root.deleteTarget) return
    if (name === "documents" && !root.documentsEnabled) return
    if (root.dropdownOpen) root.dropdownOpen = false
    root.resetSearch()
    root.scrollOnCursor = false
    root.viewMode = name === "documents" ? "documents" : "board"
    Qt.callLater(root.scrollToTop)
    root.focusForView()
  }

  function fetchBoard() {
    if (!root.selectedProject) return
    loadError = ""
    treeProc.workingDirectory = root.selectedProject.root_path
    treeProc.running = false
    treeProc.running = true
  }

  function applyTreeData(roots) {
    root.cardRoots = roots
    var indexed = Logic.indexTree(roots)
    root.cardMap = indexed.cardMap
    if (root.viewMode === "entry" && !root.cardMap[root.selectedCardId]) root.restoreListView()
  }

  property string watchedDbPath: ""

  readonly property var visibleBoardRoots: root.cardRoots.filter(function(c) {
    return Logic.subtreeMatches(c, root.searchQuery)
  })

  function boardColumn(status) {
    return root.visibleBoardRoots.filter(function(c) {
      return Logic.effectiveStatus(c) === status
    })
  }

  // All visible Board cards as one list, section by section: the order the
  // keyboard cursor walks them in.
  readonly property var boardCards: Logic.boardOrder(root.visibleBoardRoots, root.statuses)

  // The clickable rows of the card being viewed, in display order.
  readonly property var detailLinkList: root.viewMode === "entry"
    ? Logic.detailLinks(root.cardMap[root.selectedCardId], root.cardMap) : []

  function boardIndexOf(id) {
    for (var i = 0; i < root.boardCards.length; i++)
      if (root.boardCards[i].id === id) return i
    return -1
  }

  function linkIndex(section, id) {
    for (var i = 0; i < root.detailLinkList.length; i++)
      if (root.detailLinkList[i].section === section && root.detailLinkList[i].id === id) return i
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

  property string selectedCardId: ""

  function openCard(id) {
    if (!root.cardMap[id]) return
    if (root.viewMode === "board") {
      root.returnCursor = root.cursorIndex
      root.returnScrollY = panelFlick ? panelFlick.contentY : 0
    }
    selectedCardId = id
    viewMode = "entry"
    root.scrollOnCursor = false
    root.cursorIndex = 0
    Qt.callLater(root.scrollToTop)
    focusForView()
  }

  // Leaving a card puts the Board back exactly as it was: same highlighted
  // card, same scroll position.
  function restoreListView() {
    viewMode = "board"
    root.scrollOnCursor = false
    root.cursorIndex = root.returnCursor
    Qt.callLater(function() { if (panelFlick) root.scrollBy(root.returnScrollY - panelFlick.contentY) })
    focusForView()
  }

  function goBack() {
    if (viewMode === "entry") { restoreListView(); return }
  }

  function resolvedCard(id) {
    var card = root.cardMap[id]
    return card ? { id: id, title: card.title, status: card.status, inBoard: true }
                : { id: id, title: id, status: "", inBoard: false }
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
    function refresh(): string { root.refreshProjects(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "🗂️"
    onPressed: function(buttonCode) { root.toggle() }
  }

  // `brd projects` reads the global registry directly -- no cwd
  // dependency, unlike `brd tree` in Task 5.
  Process {
    id: listProc
    objectName: "listProc"
    command: ["brd", "projects"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text || "{}")
          var list = (parsed.data || []).map(function(p) {
            return { root_path: p.root_path, name: p.name }
          }).sort(function(a, b) { return a.name.localeCompare(b.name) })
          root.applyProjectsList(list)
        } catch (e) {
          root.loadError = "Could not parse brd's project list."
        }
      }
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.projects.length === 0)
        root.loadError = "Could not list brd projects (is brd installed and on PATH?)."
    }
  }

  Process {
    id: stateGetProc
    objectName: "stateGetProc"
    property string outText: ""
    command: ["python3", root.pluginDir + "viewer-state.py", "get"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: stateGetProc.outText = String(text || "")
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      var out = stateGetProc.outText
      stateGetProc.outText = ""
      root.applyStoredState(out, exitCode)
    }
  }

  // A failed save is deliberately silent: it never blocks navigation.
  Process {
    id: saveStateProc
    objectName: "saveStateProc"
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
  }

  Component.onCompleted: stateGetProc.running = true

  Process {
    id: resolveDbPathProc
    objectName: "resolveDbPathProc"
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var path = String(text || "").trim()
        root.watchedDbPath = path
      }
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.watchedDbPath = ""
    }
  }

  FileView {
    id: dbFile
    path: root.watchedDbPath !== "" ? root.watchedDbPath : ""
    watchChanges: true
    printErrors: false
    onFileChanged: root.fetchBoard()
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
          root.loadError = ""
          root.applyTreeData(parsed.data || [])
        } catch (e) {
          root.applyTreeData([])
          root.loadError = "Could not load the board for this project."
        }
      }
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.applyTreeData([])
        root.loadError = "Could not load the board for this project."
      }
    }
  }

  // snapshot-and-forget.py prints one JSON line and exits 0/1; nothing here
  // assumes success until Logic.parseDeleteResult says so.
  Process {
    id: deleteProc
    objectName: "deleteProc"
    property string outText: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: deleteProc.outText = String(text || "")
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      var result = Logic.parseDeleteResult(deleteProc.outText, exitCode)
      deleteProc.outText = ""
      root.deleting = false
      if (result.ok) {
        root.deleteTarget = null
        root.confirmText = ""
        root.lastSnapshot = result.snapshot
        root.cursorIndex = 0
        root.refreshProjects()
        root.focusForView()
      } else {
        root.deleteError = result.error
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: root.focusItem
    // Centered under the bar rather than under the icon, and wide enough for
    // the sidebar.
    centerOnBar: true
    contentWidth: panel.fittedContentWidth(Style.space(840))
    contentHeight: panel.fittedContentHeight(Math.max(column.implicitHeight, sidebar.implicitHeight), Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      objectName: "keyCatcher"
      anchors.fill: parent
      onCloseRequested: root.deleteTarget ? root.cancelDelete() : (root.dropdownOpen ? root.closeDropdown() : ((root.viewMode === "entry" || root.viewMode === "document") ? root.goBack() : root.close()))
      onMoveRequested: function(dx, dy) {
        if (dx < 0 && (root.viewMode === "entry" || root.viewMode === "document")) { root.goBack(); return }
        if (root.viewMode !== "entry") return
        if (dx > 0) { root.activateCursor(); return }
        if (dy === 0) return
        // Links are the cursor's targets; a card without any is just text,
        // so the arrows scroll it instead.
        if (root.detailLinkList.length > 0) root.moveCursor(dy)
        else root.scrollBy(dy * Style.space(56))
      }
      onActivateRequested: if (root.viewMode === "entry") root.activateCursor()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Sidebar {
        id: sidebar
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Style.space(200)
        projects: root.filteredProjects
        selectedProject: root.selectedProject
        section: root.section
        dropdownOpen: root.dropdownOpen
        dropdownQuery: root.dropdownQuery
        dropdownCursor: root.dropdownCursor
        canDelete: !!root.selectedProject && !root.deleting && !root.deleteTarget
        documentsEnabled: root.documentsEnabled
        foreground: root.foreground
        dim: root.dim
        urgent: root.urgent
        fontFamily: root.fontFamily
        onDropdownToggled: root.toggleDropdown()
        onProjectChosen: function(project) { root.chooseProject(project) }
        onQueryEdited: function(text) { root.dropdownQuery = text; root.dropdownCursor = 0 }
        onSectionChosen: function(name) { root.showSection(name) }
        onDeleteRequested: root.openDelete(root.selectedProject)
        onCursorHovered: function(index) { root.dropdownCursor = index }
        onDropdownMove: function(delta) { root.moveDropdown(delta) }
        onDropdownAccept: root.acceptDropdown()
        onDropdownCancel: root.closeDropdown()
      }

      Flickable {
        id: panelFlick
        anchors.left: sidebar.right
        anchors.leftMargin: Style.space(12)
        anchors.top: parent.top
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

          RowLayout {
            width: parent.width
            spacing: Style.spacing.md

            Text {
              visible: root.viewMode === "entry" || root.viewMode === "document"
              text: "‹ Back"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.goBack() }
            }

            Text {
              Layout.fillWidth: true
              text: root.selectedProject ? root.sectionTitle : "brd Viewer"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              elide: Text.ElideMiddle
            }

            Text {
              visible: root.viewMode === "board"
              text: "⟳"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.fetchBoard() }
            }
          }

          TextField {
            id: searchField
            objectName: "searchField"
            visible: !root.deleteTarget && !!root.selectedProject && (root.viewMode === "board" || root.viewMode === "documents")
            width: parent.width
            foreground: root.foreground
            placeholderText: root.viewMode === "documents" ? "Search documents…" : "Search cards…"
            text: root.searchQuery

            onTextChanged: {
              root.searchQuery = text
              root.cursorIndex = 0
            }

            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                if (root.searchQuery !== "") { root.searchQuery = "" }
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
            visible: root.loadError !== ""
            width: parent.width
            text: root.loadError
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Column {
            visible: !!root.deleteTarget
            width: parent.width
            spacing: Style.space(8)

            Text {
              width: parent.width
              text: "Type delete to permanently remove “" + (root.deleteTarget ? root.deleteTarget.name : "")
                + "” from brd. This can't be undone, but a snapshot of its board is saved first."
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: root.deleteTarget ? root.displayPath(root.deleteTarget.root_path) : ""
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
              enabled: !root.deleting
              text: root.confirmText

              onTextChanged: root.confirmText = text

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) { root.cancelDelete(); event.accepted = true; return }
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.performDelete(); event.accepted = true; return
                }
              }
            }

            Text {
              visible: root.deleteError !== ""
              width: parent.width
              text: root.deleteError
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Row {
              spacing: Style.spacing.md

              Button {
                text: "Cancel"
                enabled: !root.deleting
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: root.cancelDelete()
              }

              Button {
                text: root.deleting ? "Deleting…" : "Confirm delete"
                enabled: !root.deleting && Logic.isDeleteConfirmed(root.confirmText)
                opacity: enabled ? 1 : 0.5
                bordered: true
                foreground: root.urgent
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: root.performDelete()
              }
            }
          }

          Text {
            visible: !root.deleteTarget && root.lastSnapshot !== ""
            width: parent.width
            text: "Removed. Snapshot saved to " + root.displayPath(root.lastSnapshot)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WrapAnywhere
          }

          Text {
            visible: !root.selectedProject && root.loadError === ""
            width: parent.width
            text: "No projects registered with brd."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Column {
            visible: root.viewMode === "board" && !!root.selectedProject
            width: parent.width
            spacing: Style.space(10)

            Text {
              visible: root.cardRoots.length === 0 && root.loadError === ""
              width: parent.width
              text: "This project's board is empty."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Text {
              visible: root.cardRoots.length > 0 && root.visibleBoardRoots.length === 0
              width: parent.width
              text: "No cards match “" + root.searchQuery + "”."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: root.statuses

              Column {
                required property string modelData
                width: parent.width
                spacing: Style.space(6)

                PanelSectionHeader {
                  text: root.statusLabel(modelData) + " (" + root.boardColumn(modelData).length + ")"
                  foreground: Logic.statusColor(modelData, root.foreground)
                  fontFamily: root.fontFamily
                }

                Repeater {
                  model: root.boardColumn(modelData)

                  BoardCard {
                    required property var modelData
                    width: parent.width
                    cardIndex: root.boardIndexOf(modelData.id)
                    title: modelData.title
                    status: modelData.status
                    progress: Logic.subtreeCounts(modelData)
                    onActivated: root.openCard(modelData.id)
                  }
                }
              }
            }
          }

          Column {
            id: detailCard
            visible: root.viewMode === "entry" && !!root.cardMap[root.selectedCardId]
            width: parent.width
            spacing: Style.space(10)

            readonly property var card: root.cardMap[root.selectedCardId]

            DetailLink {
              visible: !!(detailCard.card && detailCard.card.parentId)
              width: parent.width
              prefix: "↑ "
              resolved: detailCard.card && detailCard.card.parentId
                ? root.resolvedCard(detailCard.card.parentId) : ({ title: "", status: "", inBoard: false })
              rowIndex: detailCard.card && detailCard.card.parentId ? root.linkIndex("parent", detailCard.card.parentId) : -1
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
                text: detailCard.card ? Logic.kindLabel(detailCard.card.depth) : ""
                tone: root.foreground
              }

              Badge {
                text: detailCard.card ? root.statusText(detailCard.card.status) : ""
                tone: detailCard.card ? Logic.statusColor(detailCard.card.status, root.dim) : root.dim
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
                resolved: root.resolvedCard(modelData)
                rowIndex: root.linkIndex("blocker", modelData)
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
                resolved: root.resolvedCard(modelData.id)
                rowIndex: root.linkIndex("child", modelData.id)
                onActivated: root.openCard(modelData.id)
              }
            }
          }
        }
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

    hasCursor: rowIndex >= 0 && root.cursorIndex === rowIndex
    onHasCursorChanged: if (hasCursor && root.scrollOnCursor) root.scrollItemIntoView(detailLink)
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
        color: Logic.statusColor(detailLink.resolved.status, root.dim)
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

    hasCursor: cardIndex >= 0 && root.cursorIndex === cardIndex
    onHasCursorChanged: if (hasCursor && root.scrollOnCursor) root.scrollItemIntoView(boardCard)
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
      color: Logic.statusColor(boardCard.status, root.dim)
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
        color: Logic.statusColor("blocked", root.dim)
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
