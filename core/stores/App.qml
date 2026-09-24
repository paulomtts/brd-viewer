import QtQml

// The panel's non-visual state, in one place, plus the wiring between stores:
// a store never reaches for another one, App composes them and hands each
// what it needs through properties and signals.
QtObject {
  id: app

  property string backendDir: ""

  readonly property NavigationStore nav: NavigationStore {}

  readonly property ProjectStore projects: ProjectStore {
    backendDir: app.backendDir
    dropdownQuery: app.nav.dropdownQuery
    onSelected: function(project) {
      app.nav.viewMode = "board"
      app.nav.resetSearch()
      app.graph.graphCursor = ""
      app.board.fetchBoard()
      app.docs.reset()
      app.memories.resetMemories()
    }
    onCleared: {
      app.nav.viewMode = "board"
      app.board.applyTreeData([])
      app.graph.graphCursor = ""
      app.docs.reset()
      app.memories.resetMemories()
    }
    onChosen: app.deleter.lastSnapshot = ""
    onOpened: {
      app.nav.dropdownOpen = false
      app.nav.dropdownQuery = ""
      app.deleter.onPanelOpened()
    }
  }

  readonly property BoardStore board: BoardStore {
    project: app.projects.selectedProject
    dbPath: app.projects.watchedDbPath
    viewMode: app.nav.viewMode
    searchQuery: app.nav.searchQuery
    onErrored: function(message) { app.projects.loadError = message }
  }

  readonly property DocumentsStore docs: DocumentsStore {
    backendDir: app.backendDir
    project: app.projects.selectedProject
    viewMode: app.nav.viewMode
    searchQuery: app.nav.searchQuery
    onCategoryToggled: {
      app.nav.cursorIndex = 0
      app.nav.scrollOnCursor = false
    }
  }

  readonly property MemoriesStore memories: MemoriesStore {
    backendDir: app.backendDir
    project: app.projects.selectedProject
    viewMode: app.nav.viewMode
    searchQuery: app.nav.searchQuery
    onTypeToggled: {
      app.nav.cursorIndex = 0
      app.nav.scrollOnCursor = false
    }
  }

  readonly property GraphStore graph: GraphStore {
    cardRoots: app.board.cardRoots
  }

  readonly property ProjectDeleteStore deleter: ProjectDeleteStore {
    backendDir: app.backendDir
    projects: app.projects
    onRequested: app.nav.dropdownOpen = false
    onDeleted: app.nav.cursorIndex = 0
  }
}
