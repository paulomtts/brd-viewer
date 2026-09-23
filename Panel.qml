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

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

  readonly property var filteredProjects: root.projects.filter(function(p) {
    return Logic.matchesQuery(p.name, root.searchQuery)
  })

  function currentList() {
    if (root.viewMode === "projects") return root.filteredProjects
    return []
  }

  function focusForView() {
    Qt.callLater(function() {
      if (!root.opened) return
      if (searchField) searchField.forceActiveFocus()
    })
  }

  function resetSearch() {
    searchQuery = ""
    cursorIndex = 0
  }

  function moveCursor(delta) {
    var list = root.currentList()
    if (list.length === 0) return
    root.cursorIndex = root.clamp(root.cursorIndex + delta, 0, list.length - 1)
  }

  function hoverCursor(index) {
    root.cursorIndex = index
  }

  function activateCursor() {
    var list = root.currentList()
    if (root.cursorIndex < 0 || root.cursorIndex >= list.length) return
    if (root.viewMode === "projects") root.selectProject(list[root.cursorIndex])
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
  }

  readonly property var visibleBoardRoots: root.cardRoots.filter(function(c) {
    return Logic.subtreeMatches(c, root.searchQuery)
  })

  function boardColumn(status) {
    return root.visibleBoardRoots.filter(function(c) { return c.status === status })
  }

  function statusLabel(status) {
    if (status === "todo") return "Todo"
    if (status === "in_progress") return "In Progress"
    return "Done"
  }

  function openCard(id) {
    // Task 7 implements card detail; this is the single entry point every
    // Board/Tree row calls, so Task 7 only has to fill this function in.
  }

  function goBack() {
    openProjects()
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
    id: treeProc
    command: ["brd", "tree"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text || "{}")
          root.applyTreeData(parsed.data || [])
        } catch (e) {
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
    focusTarget: searchField
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
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

            Button {
              visible: root.viewMode === "board" || root.viewMode === "tree"
              text: root.viewMode === "board" ? "Tree ›" : "‹ Board"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.viewMode = (root.viewMode === "board" ? "tree" : "board")
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
                else root.close()
                event.accepted = true
                return
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

            Repeater {
              model: root.statuses

              Column {
                required property string modelData
                width: parent.width
                spacing: Style.space(6)

                PanelSectionHeader {
                  text: root.statusLabel(modelData) + " (" + root.boardColumn(modelData).length + ")"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                Repeater {
                  model: root.boardColumn(modelData)

                  BoardCard {
                    required property var modelData
                    width: parent.width
                    title: modelData.title
                    progress: Logic.subtreeCounts(modelData)
                    onActivated: root.openCard(modelData.id)
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  component ProjectRow: CursorSurface {
    id: projectRow
    property int rowIndex: 0
    property string label: ""
    signal activated()

    hasCursor: root.cursorIndex === rowIndex
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

  component BoardCard: Rectangle {
    id: boardCard
    property string title: ""
    property var progress: ({ done: 0, total: 0 })
    signal activated()

    color: "transparent"
    border.color: Qt.darker(root.foreground, 2.0)
    border.width: 1
    radius: Style.space(4)
    implicitHeight: cardLayout.implicitHeight + Style.space(16)

    ColumnLayout {
      id: cardLayout
      anchors.fill: parent
      anchors.margins: Style.space(8)
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
        visible: boardCard.progress.total > 0
        text: boardCard.progress.done + "/" + boardCard.progress.total + " done"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: boardCard.activated()
    }
  }
}
