import QtQml

// The panel's non-visual state, in one place, plus the wiring between stores:
// a store never reaches for another one, App hands it what it needs. Later
// tasks add the remaining stores beside `nav`.
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
    }
    onCleared: app.nav.viewMode = "board"
    onChosen: app.deleter.lastSnapshot = ""
    onOpened: {
      app.nav.dropdownOpen = false
      app.nav.dropdownQuery = ""
      app.deleter.onPanelOpened()
    }
  }

  readonly property ProjectDeleteStore deleter: ProjectDeleteStore {
    backendDir: app.backendDir
    projects: app.projects
    onRequested: app.nav.dropdownOpen = false
    onDeleted: app.nav.cursorIndex = 0
  }
}
