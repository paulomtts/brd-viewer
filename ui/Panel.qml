import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../core/domain/board.js" as Board
import "../core/domain/documents.js" as Documents
import "../core/stores" as Core
import "components"
import "components" as UI
import "theme" as T

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
  // The one Theme in the plugin: every view and shared component draws with
  // it, so the bar's palette reaches them through a single property.
  T.Theme {
    id: panelTheme
    foreground: root.foreground
    urgent: root.urgent
    fontFamily: root.fontFamily
  }

  // The plugin ROOT, not this file's folder: every helper is addressed as
  // pluginDir + "core/backend/...", and this file lives in <plugin>/ui/, so the
  // "../" is load-bearing (tests/ui/tst_plugin_dir.qml guards it).
  readonly property string pluginDir: Qt.resolvedUrl("../").toString().replace(/^file:\/\//, "")

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
      root.focusForView()
    }
  }

  // A different category means a different list: the cursor reset is App's, the
  // scroll is the panel's.
  Connections {
    target: appStores.docs
    function onCategoryToggled() { Qt.callLater(root.scrollToTop) }
  }

  // The memories store asks for the navigation and focus work it does not do
  // itself: the same list/note bookkeeping the panel does everywhere else.
  Connections {
    target: appStores.memories
    function onTypeToggled() { Qt.callLater(root.scrollToTop) }
    function onNoteOpenRequested(file) { navi.openMemory(file) }
    function onListRestoreRequested() { navi.restoreMemoriesList() }
    function onFocusRequested() { root.focusForView() }
  }

  // The open card left the board (a refetch dropped it): back to the list.
  Connections {
    target: appStores.board
    function onListViewRequested() { navi.restoreListView() }
  }

  Connections {
    target: appStores.deleter
    function onRequested() { root.focusForView() }
    function onClosed() { root.focusForView() }
    function onDeleted() { root.focusForView() }
  }

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

  // Where the panel is and how it gets there. The navigator owns no Items: the
  // Flickable and the four UI-only effects below are all it is given.
  Navigator {
    id: navi
    app: appStores
    flick: panelFlick
    documentsEnabled: root.documentsEnabled
    actions: ({
      focusForView: root.focusForView,
      scrollToTop: root.scrollToTop,
      scrollBy: root.scrollBy,
      centerOnGraphNode: function(id) { if (graphView) graphView.centerOn(id) }
    })
  }
  readonly property var navigator: navi

  readonly property Item focusItem: appStores.deleter.deleteTarget ? deleteModal.focusItem
    : appStores.memories.memoryDeleteOpen ? memoryConfirm.focusItem
    : appStores.memories.newMemoryOpen ? newMemoryDialog.focusItem
    : (appStores.nav.viewMode === "memory" && appStores.memories.memoryEditing) ? memoryNote.editorItem
    : appStores.nav.dropdownOpen ? sidebar.filterItem
    : (appStores.nav.viewMode === "entry" || appStores.nav.viewMode === "document" || appStores.nav.viewMode === "memory" || appStores.nav.viewMode === "graph" || !appStores.projects.selectedProject) ? keyCatcher
    : searchField

  function focusForView() {
    Qt.callLater(function() {
      if (!root.opened) return
      if (root.focusItem) root.focusItem.forceActiveFocus()
    })
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

  function displayPath(path) {
    return String(path || "").replace(/^\/home\/[^\/]+/, "~")
  }

  onOpenedChanged: if (opened) { appStores.projects.onPanelOpened(); root.focusForView() }

  // Shortcuts that work wherever the caret is. Returns true when it handled the
  // key. Ignored while a delete confirmation is open so a stray Ctrl+P cannot
  // move things underneath it.
  function handleGlobalKey(event) {
    if (!(event.modifiers & Qt.ControlModifier) || appStores.deleter.deleteTarget || appStores.memories.memoryDeleteOpen || appStores.memories.newMemoryOpen) return false
    if (event.key === Qt.Key_P) { navi.toggleDropdown(); return true }
    if (event.key === Qt.Key_1) { navi.showSection("board"); return true }
    if (event.key === Qt.Key_2) { navi.showSection("documents"); return true }
    if (event.key === Qt.Key_3) { navi.showSection("graph"); return true }
    if (event.key === Qt.Key_4) { navi.showSection("memories"); return true }
    if (event.key === Qt.Key_N && appStores.nav.viewMode === "memories") { appStores.memories.openNewMemory(); return true }
    if (event.key === Qt.Key_E && appStores.nav.viewMode === "memory") { appStores.memories.startMemoryEdit(); return true }
    return false
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
      onCloseRequested: appStores.deleter.deleteTarget ? appStores.deleter.cancelDelete() : appStores.memories.memoryDeleteOpen ? appStores.memories.cancelMemoryDelete() : appStores.memories.newMemoryOpen ? appStores.memories.cancelNewMemory() : (appStores.nav.dropdownOpen ? navi.closeDropdown() : ((appStores.nav.viewMode === "entry" || appStores.nav.viewMode === "document" || appStores.nav.viewMode === "memory") ? navi.goBack() : root.close()))
      onMoveRequested: function(dx, dy) {
        if (appStores.nav.viewMode === "graph") {
          if (dx !== 0) navi.moveGraph(dx < 0 ? "left" : "right")
          else if (dy !== 0) navi.moveGraph(dy < 0 ? "up" : "down")
          return
        }
        if (dx < 0 && (appStores.nav.viewMode === "entry" || appStores.nav.viewMode === "document" || appStores.nav.viewMode === "memory")) { navi.goBack(); return }
        if (appStores.nav.viewMode !== "entry" && appStores.nav.viewMode !== "document" && appStores.nav.viewMode !== "memory") return
        if (dx > 0) { if (appStores.nav.viewMode === "entry") navi.activateCursor(); return }
        if (dy === 0) return
        // Links are the cursor's targets; a card without any is just text,
        // so the arrows scroll it instead.
        if (appStores.nav.viewMode === "entry" && appStores.board.detailLinkList.length > 0) navi.moveCursor(dy)
        else root.scrollBy(dy * Style.space(56))
      }
      onActivateRequested: {
        if (appStores.nav.viewMode === "entry") navi.activateCursor()
        else if (appStores.nav.viewMode === "graph") navi.activateGraphNode()
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
        theme: panelTheme
        onDropdownToggled: navi.toggleDropdown()
        onProjectChosen: function(project) { navi.chooseProject(project) }
        onQueryEdited: function(text) { appStores.nav.dropdownQuery = text; appStores.nav.dropdownCursor = 0 }
        onSectionChosen: function(name) { navi.showSection(name) }
        onDeleteRequested: appStores.deleter.openDelete(appStores.projects.selectedProject)
        onCursorHovered: function(index) { appStores.nav.dropdownCursor = index }
        onDropdownMove: function(delta) { navi.moveDropdown(delta) }
        onDropdownAccept: navi.acceptDropdown()
        onDropdownCancel: navi.closeDropdown()
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

          UI.ThemedText {
            theme: panelTheme
            visible: appStores.nav.viewMode === "entry" || appStores.nav.viewMode === "document" || appStores.nav.viewMode === "memory"
            text: "‹ Back"
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: navi.goBack() }
          }

          UI.ThemedText {
            objectName: "projectHeading"
            variant: "heading"
            theme: panelTheme
            Layout.fillWidth: true
            text: appStores.projects.selectedProject ? appStores.nav.sectionTitle : "Project Manager"
            font.bold: true
            elide: Text.ElideMiddle
          }

          UI.ThemedText {
            objectName: "newMemoryButton"
            theme: panelTheme
            visible: appStores.nav.viewMode === "memories" && appStores.memories.canCreateMemory
            text: "＋ New"
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: appStores.memories.openNewMemory() }
          }

          UI.ThemedText {
            theme: panelTheme
            visible: appStores.nav.viewMode === "board" || appStores.nav.viewMode === "graph" || appStores.nav.viewMode === "memories"
            text: "⟳"
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: appStores.nav.viewMode === "memories" ? appStores.memories.fetchMemories() : appStores.board.fetchBoard() }
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
              navi.activateCursor(); event.accepted = true; return
            }
            if (event.key === Qt.Key_Down) { navi.moveCursor(1); event.accepted = true; return }
            if (event.key === Qt.Key_Up) { navi.moveCursor(-1); event.accepted = true; return }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              navi.activateCursor(); event.accepted = true; return
            }
            if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
              root.switchPanel((event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab ? -1 : 1)
              event.accepted = true
              return
            }
          }
        }

        UI.ThemedText {
          variant: "caption"
          theme: panelTheme
          visible: appStores.projects.loadError !== ""
          width: parent.width
          text: appStores.projects.loadError
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

          UI.ThemedText {
            variant: "caption"
            theme: panelTheme
            visible: !appStores.deleter.deleteTarget && appStores.deleter.lastSnapshot !== ""
            width: parent.width
            text: "Removed. Snapshot saved to " + root.displayPath(appStores.deleter.lastSnapshot)
            wrapMode: Text.WrapAnywhere
          }

          UI.ThemedText {
            variant: "dim"
            theme: panelTheme
            visible: !appStores.projects.selectedProject && appStores.projects.loadError === ""
            width: parent.width
            text: "No projects registered with brd."
            wrapMode: Text.WordWrap
          }

          Column {
            visible: appStores.nav.viewMode === "board" && !!appStores.projects.selectedProject
            width: parent.width
            spacing: Style.space(10)

            UI.ThemedText {
              variant: "dim"
              theme: panelTheme
              visible: appStores.board.cardRoots.length === 0 && appStores.projects.loadError === ""
              width: parent.width
              text: "This project's board is empty."
              wrapMode: Text.WordWrap
            }

            UI.ThemedText {
              variant: "dim"
              theme: panelTheme
              visible: appStores.board.cardRoots.length > 0 && appStores.board.visibleBoardRoots.length === 0
              width: parent.width
              text: "No cards match “" + appStores.nav.searchQuery + "”."
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
                    onActivated: navi.openCard(modelData.id)
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
            theme: panelTheme
            onNodeClicked: function(id) { appStores.graph.graphCursor = id; navi.openCard(id) }
          }

          MemoriesView {
            visible: appStores.nav.viewMode === "memories" && !!appStores.projects.selectedProject
            width: parent.width
            notes: appStores.memories.filteredMemories
            types: appStores.memories.memoryTypes
            activeType: appStores.memories.memoryType
            query: appStores.nav.searchQuery
            cursorIndex: appStores.nav.cursorIndex
            loading: appStores.memories.memoriesLoading
            found: appStores.memories.memoriesFound
            error: appStores.memories.memoriesError
            scrollOnCursor: appStores.nav.scrollOnCursor
            theme: panelTheme
            onNoteChosen: function(file) { navi.openMemory(file) }
            onHovered: function(index) { navi.hoverCursor(index) }
            onRevealRequested: function(item) { root.scrollItemIntoView(item) }
            onTypeToggled: function(id) { appStores.memories.toggleMemoryType(id) }
          }

          MemoryNoteView {
            id: memoryNote
            visible: appStores.nav.viewMode === "memory" && !!appStores.projects.selectedProject
            width: parent.width
            entry: appStores.memories.selectedMemoryEntry
            text: appStores.memories.memoryText
            readError: appStores.memories.memoryReadError
            editing: appStores.memories.memoryEditing
            draft: appStores.memories.memoryDraft
            busy: appStores.memories.memoryBusy
            error: appStores.memories.memoryOpError
            theme: panelTheme
            onEditRequested: appStores.memories.startMemoryEdit()
            onDeleteRequested: appStores.memories.requestMemoryDelete()
            onSaveRequested: appStores.memories.saveMemory()
            onCancelEditRequested: appStores.memories.cancelMemoryEdit()
            onDraftEdited: function(text) { appStores.memories.memoryDraft = text }
            onEscapePressed: appStores.memories.memoryEscape()
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
            theme: panelTheme
            onCategoryToggled: function(id) { appStores.docs.toggleDocCategory(id) }
            onDocChosen: function(path) { navi.openDoc(path) }
            onHovered: function(index) { navi.hoverCursor(index) }
            onRevealRequested: function(item) { root.scrollItemIntoView(item) }
          }

          Column {
            visible: appStores.nav.viewMode === "document"
            width: parent.width
            spacing: Style.space(10)

            UI.ThemedText {
              variant: "caption"
              theme: panelTheme
              width: parent.width
              text: appStores.docs.selectedDocPath
              elide: Text.ElideMiddle
            }

            TagPicker {
              width: parent.width
              current: appStores.docs.selectedDocCategory
              busy: appStores.docs.docTagBusy
              error: appStores.docs.docTagError
              theme: panelTheme
              onTagChosen: function(id) { appStores.docs.setDocTag(id) }
            }

            UI.ThemedText {
              variant: "dim"
              theme: panelTheme
              visible: appStores.docs.docTooLargeFlag || appStores.docs.docError !== ""
              width: parent.width
              text: appStores.docs.docTooLargeFlag ? "This document is too large to display." : appStores.docs.docError
              wrapMode: Text.WordWrap
            }

            UI.ThemedText {
              variant: "small"
              theme: panelTheme
              visible: !appStores.docs.docTooLargeFlag && appStores.docs.docError === ""
              width: parent.width
              text: appStores.docs.docText !== "" ? appStores.docs.docText : "Loading…"
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
              onActivated: if (resolved.inBoard) navi.openCard(detailCard.card.parentId)
            }

            UI.ThemedText {
              variant: "heading"
              theme: panelTheme
              width: parent.width
              text: detailCard.card ? detailCard.card.title : ""
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

            UI.ThemedText {
              variant: "small"
              theme: panelTheme
              width: parent.width
              text: (detailCard.card && detailCard.card.description) ? detailCard.card.description : "No description."
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
                onActivated: if (resolved.inBoard) navi.openCard(modelData)
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
                onActivated: navi.openCard(modelData.id)
              }
            }
          }
        }
      }

      // Delete confirmation: the shared typed-word modal, driven by the store.
      TypedConfirmDialog {
        id: deleteModal
        objectName: "deleteModal"
        anchors.fill: parent
        backdropObjectName: "deleteBackdrop"
        cardObjectName: "deleteCard"
        fieldObjectName: "confirmField"
        shown: !!appStores.deleter.deleteTarget
        message: "Type delete to permanently remove “" + (appStores.deleter.deleteTarget ? appStores.deleter.deleteTarget.name : "")
          + "” from brd. This can't be undone, but a snapshot of its board is saved first."
        detail: appStores.deleter.deleteTarget ? root.displayPath(appStores.deleter.deleteTarget.root_path) : ""
        confirmLabel: "Confirm delete"
        busyLabel: "Deleting…"
        busy: appStores.deleter.deleting
        error: appStores.deleter.deleteError
        typedText: appStores.deleter.confirmText
        theme: panelTheme
        onTypedEdited: function(text) { appStores.deleter.confirmText = text }
        onConfirmRequested: appStores.deleter.performDelete()
        onCancelRequested: appStores.deleter.cancelDelete()
      }

      TypedConfirmDialog {
        id: memoryConfirm
        anchors.fill: parent
        shown: appStores.memories.memoryDeleteOpen
        message: "Type delete to permanently remove this memory note and its MEMORY.md entry. A backup is saved first."
        detail: appStores.memories.selectedMemory
        busy: appStores.memories.memoryBusy
        error: appStores.memories.memoryDeleteError
        theme: panelTheme
        onConfirmRequested: appStores.memories.performMemoryDelete()
        onCancelRequested: appStores.memories.cancelMemoryDelete()
      }

      NewMemoryDialog {
        id: newMemoryDialog
        anchors.fill: parent
        shown: appStores.memories.newMemoryOpen
        busy: appStores.memories.memoryBusy
        error: appStores.memories.newMemoryError
        theme: panelTheme
        onCreateRequested: function(name, type, description, body) { appStores.memories.createMemory(name, type, description, body) }
        onCancelRequested: appStores.memories.cancelNewMemory()
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

    UI.ThemedText {
      id: badgeLabel
      variant: "caption"
      theme: panelTheme
      anchors.centerIn: parent
      text: badge.text
      color: badge.tone
      font.bold: true
    }
  }

  component DetailLink: UI.ListRow {
    id: detailLink
    property var resolved: ({ title: "", status: "", inBoard: true })
    property alias rowIndex: detailLink.index
    property string prefix: ""

    theme: panelTheme
    cursorIndex: appStores.nav.cursorIndex
    scrollOnCursor: appStores.nav.scrollOnCursor
    contentMargin: Style.space(6)
    hoverCursorShape: detailLink.resolved.inBoard ? Qt.PointingHandCursor : Qt.ArrowCursor
    onHovered: function(index) { navi.hoverCursor(index) }
    onRevealRequested: function(item) { root.scrollItemIntoView(item) }

    RowLayout {
      id: detailLinkLayout
      width: parent.width

      UI.ThemedText {
        variant: "small"
        theme: panelTheme
        Layout.fillWidth: true
        text: detailLink.prefix + detailLink.resolved.title + (detailLink.resolved.inBoard ? "" : " (not in this board)")
        color: detailLink.resolved.inBoard ? root.foreground : root.dim
        elide: Text.ElideRight
      }

      UI.ThemedText {
        variant: "caption"
        theme: panelTheme
        visible: detailLink.resolved.inBoard
        text: "[" + detailLink.resolved.status + "]"
        color: Board.statusColor(detailLink.resolved.status, root.dim)
      }
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

      UI.ThemedText {
        theme: panelTheme
        Layout.fillWidth: true
        text: boardCard.title
        wrapMode: Text.WordWrap
      }

      UI.ThemedText {
        variant: "caption"
        theme: panelTheme
        visible: boardCard.status === "blocked"
        text: "Blocked"
        color: Board.statusColor("blocked", root.dim)
        font.bold: true
      }

      UI.ThemedText {
        variant: "caption"
        theme: panelTheme
        visible: boardCard.progress.total > 0
        text: boardCard.progress.done + "/" + boardCard.progress.total + " done"
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: if (boardCard.cardIndex >= 0) navi.hoverCursor(boardCard.cardIndex)
      onClicked: boardCard.activated()
    }
  }
}
