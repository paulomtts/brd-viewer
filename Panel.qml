import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "logic.js" as Logic

// Browses brd's local kanban board (`brd projects` / `brd tree`), per
// project: pick a project, then view its cards as a Board or a Tree.
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

  property string viewMode: "projects" // "projects" | "board" | "tree" | "entry"
  property var projects: []            // [{ root_path, name }]
  property var selectedProject: null   // { root_path, name } | null
  property string loadError: ""

  property string searchQuery: ""
  property int cursorIndex: 0
  // True only while the keyboard is driving the cursor: rows then scroll
  // themselves into view. Hover must not scroll, or the list would move
  // under a stationary pointer and re-trigger hover.
  property bool scrollOnCursor: false
  property int returnCursor: 0
  property real returnScrollY: 0

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

  readonly property var filteredProjects: root.projects.filter(function(p) {
    return Logic.matchesQuery(p.name, root.searchQuery)
  })

  function currentList() {
    if (root.viewMode === "projects") return root.filteredProjects
    if (root.viewMode === "tree") return root.visibleTreeRows
    if (root.viewMode === "board") return root.boardCards
    if (root.viewMode === "entry") return root.detailLinkList
    return []
  }

  function focusForView() {
    Qt.callLater(function() {
      if (!root.opened) return
      if (root.viewMode === "entry") {
        if (keyCatcher) keyCatcher.forceActiveFocus()
      } else if (searchField) {
        searchField.forceActiveFocus()
      }
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

  readonly property var visibleTreeRows: root.treeRows.filter(function(row) {
    return Logic.subtreeMatches(root.cardMap[row.id], root.searchQuery)
  })

  function activateCursor() {
    var list = root.currentList()
    if (root.cursorIndex < 0 || root.cursorIndex >= list.length) return
    if (root.viewMode === "projects") root.selectProject(list[root.cursorIndex])
    else root.openCard(list[root.cursorIndex].id)
  }

  function refreshProjects() {
    loadError = ""
    listProc.running = false
    listProc.running = true
  }

  function openProjects() {
    viewMode = "projects"
    selectedProject = null
    resetSearch()
    refreshProjects()
    focusForView()
  }

  property var cardRoots: []   // top-level cards from the last brd tree fetch
  property var cardMap: ({})   // id -> card, from Logic.indexTree
  property var treeRows: []    // [{id, depth}], from Logic.indexTree
  readonly property var statuses: ["todo", "in_progress", "done"]

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
    root.treeRows = indexed.rows
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
  property string detailReturnView: "board"

  function openCard(id) {
    if (!root.cardMap[id]) return
    if (root.viewMode === "board" || root.viewMode === "tree") {
      root.detailReturnView = root.viewMode
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

  // Leaving a card puts the list back exactly as it was: same view, same
  // highlighted row, same scroll position.
  function restoreListView() {
    viewMode = root.detailReturnView
    root.scrollOnCursor = false
    root.cursorIndex = root.returnCursor
    Qt.callLater(function() { if (panelFlick) root.scrollBy(root.returnScrollY - panelFlick.contentY) })
    focusForView()
  }

  function goBack() {
    if (viewMode === "entry") { restoreListView(); return }
    openProjects()
  }

  function resolvedCard(id) {
    var card = root.cardMap[id]
    return card ? { id: id, title: card.title, status: card.status, inBoard: true }
                : { id: id, title: id, status: "", inBoard: false }
  }

  onOpenedChanged: if (opened) openProjects()

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
    function refresh(): string { root.openProjects(); return "ok" }
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
    command: ["brd", "projects"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text || "{}")
          root.projects = (parsed.data || []).map(function(p) {
            return { root_path: p.root_path, name: p.name }
          }).sort(function(a, b) { return a.name.localeCompare(b.name) })
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
    id: resolveDbPathProc
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

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: root.viewMode === "entry" ? keyCatcher : searchField
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.viewMode === "projects" ? root.close() : root.goBack()
      onMoveRequested: function(dx, dy) {
        if (dx < 0 && root.viewMode !== "projects") { root.goBack(); return }
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

      Flickable {
        id: panelFlick
        anchors.fill: parent
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
              visible: root.viewMode !== "projects"
              text: "‹ Back"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.goBack() }
            }

            Text {
              Layout.fillWidth: true
              text: root.viewMode === "projects" ? "brd Viewer"
                : root.selectedProject ? root.selectedProject.name : "brd Viewer"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              elide: Text.ElideMiddle
            }

            Text {
              visible: root.viewMode === "board" || root.viewMode === "tree"
              text: "⟳"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.fetchBoard() }
            }

            Button {
              visible: root.viewMode === "board" || root.viewMode === "tree"
              text: root.viewMode === "board" ? "Tree ›" : "‹ Board"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: {
                root.viewMode = (root.viewMode === "board" ? "tree" : "board")
                root.cursorIndex = 0
              }
            }
          }

          TextField {
            id: searchField
            visible: root.viewMode === "projects" || root.viewMode === "board" || root.viewMode === "tree"
            width: parent.width
            foreground: root.foreground
            placeholderText: root.viewMode === "projects" ? "Search projects…" : "Search cards…"
            text: root.searchQuery

            onTextChanged: {
              root.searchQuery = text
              root.cursorIndex = 0
            }

            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                if (root.searchQuery !== "") { root.searchQuery = "" }
                else if (root.viewMode === "projects") root.close()
                else root.goBack()
                event.accepted = true
                return
              }
              if (event.key === Qt.Key_Left && searchField.cursorPosition === 0 && root.viewMode !== "projects") {
                root.goBack(); event.accepted = true; return
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
            visible: root.viewMode === "projects"
            width: parent.width
            spacing: Style.space(6)

            Text {
              visible: root.projects.length === 0 && root.loadError === ""
              width: parent.width
              text: "No projects registered with brd."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Text {
              visible: root.projects.length > 0 && root.filteredProjects.length === 0
              width: parent.width
              text: "No projects match “" + root.searchQuery + "”."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Repeater {
              id: projectsRepeater
              model: root.filteredProjects

              ProjectRow {
                required property var modelData
                required property int index
                width: parent.width
                rowIndex: index
                label: modelData.name
                onActivated: root.selectProject(modelData)
              }
            }
          }

          Column {
            visible: root.viewMode === "board"
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
            visible: root.viewMode === "tree"
            width: parent.width
            spacing: Style.space(2)

            Text {
              visible: root.treeRows.length === 0 && root.loadError === ""
              width: parent.width
              text: "This project's board is empty."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Text {
              visible: root.treeRows.length > 0 && root.visibleTreeRows.length === 0
              width: parent.width
              text: "No cards match “" + root.searchQuery + "”."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Repeater {
              id: treeRepeater
              model: root.visibleTreeRows

              TreeRow {
                required property var modelData
                required property int index
                width: parent.width
                rowIndex: index
                depth: modelData.depth
                card: root.cardMap[modelData.id]
                blocked: Logic.isBlocked(root.cardMap[modelData.id], root.cardMap)
                onActivated: root.openCard(modelData.id)
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

  component ProjectRow: CursorSurface {
    id: projectRow
    property int rowIndex: 0
    property string label: ""
    signal activated()

    hasCursor: root.cursorIndex === rowIndex
    onHasCursorChanged: if (hasCursor && root.scrollOnCursor) root.scrollItemIntoView(projectRow)
    foreground: root.foreground
    implicitHeight: projectRowLayout.implicitHeight + Style.spacing.rowPaddingX

    RowLayout {
      id: projectRowLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)

      Text {
        Layout.fillWidth: true
        text: projectRow.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideMiddle
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.hoverCursor(projectRow.rowIndex)
      onClicked: projectRow.activated()
    }
  }

  component TreeRow: CursorSurface {
    id: treeRow
    property int rowIndex: 0
    property int depth: 0
    property var card: null
    property bool blocked: false
    signal activated()

    hasCursor: root.cursorIndex === rowIndex
    onHasCursorChanged: if (hasCursor && root.scrollOnCursor) root.scrollItemIntoView(treeRow)
    foreground: root.foreground
    implicitHeight: treeRowLayout.implicitHeight + Style.spacing.rowPaddingX

    RowLayout {
      id: treeRowLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10) + treeRow.depth * Style.space(16)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(6)

      Text {
        visible: treeRow.blocked
        text: "⛔"
        font.pixelSize: Style.font.body
      }

      Text {
        Layout.fillWidth: true
        text: treeRow.card ? treeRow.card.title : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        text: treeRow.card ? "[" + treeRow.card.status + "]" : ""
        color: treeRow.card ? Logic.statusColor(treeRow.card.status, root.dim) : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.hoverCursor(treeRow.rowIndex)
      onClicked: treeRow.activated()
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
