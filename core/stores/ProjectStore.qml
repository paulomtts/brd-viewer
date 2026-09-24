import QtQml
import Quickshell
import Quickshell.Io
import "../domain/projects.js" as Projects

// The project registry (`brd projects`), which project is selected, and the
// "last project" remembered across sessions (viewer-state.py). Everything the
// selection sets off outside this store -- navigation, the board, the document
// and memory sections -- is announced with `selected`/`cleared` and wired up by
// App.qml and the panel.
Scope {
  id: store

  property string backendDir: ""        // <plugin>/core/backend/
  property string dropdownQuery: ""     // set by App from nav.dropdownQuery

  property var projects: []            // [{ root_path, name }]
  property var selectedProject: null   // { root_path, name } | null
  property string loadError: ""
  property string storedProject: ""
  property bool stateLoaded: false
  property bool stateReadOk: false
  property string watchedDbPath: ""

  readonly property var filteredProjects: Projects.filterProjects(store.projects, store.dropdownQuery)

  readonly property alias listProc: listProc
  readonly property alias stateRunner: stateRunner
  readonly property alias saveStateProc: saveStateProc
  readonly property alias resolveDbPathProc: resolveDbPathProc
  readonly property alias stateWatchdog: stateWatchdog

  // A project became current: the navigation resets (App) and the sections
  // reload (panel).
  signal selected(var project)
  // Nothing is selected any more (the registry is empty).
  signal cleared()
  // The user picked a project in the dropdown, whether or not it changed.
  signal chosen()
  // The panel was opened: transient state elsewhere is dropped.
  signal opened()

  function refreshProjects() {
    loadError = ""
    listProc.running = false
    listProc.running = true
  }

  // The panel was just opened: refresh the registry and drop any half-finished
  // UI state. The project on screen stays selected while it is still registered.
  function onPanelOpened() {
    store.opened()
    store.refreshProjects()
  }

  function applyProjectsList(list) {
    store.projects = list
    store.maybeSelectInitial()
  }

  function maybeSelectInitial() {
    if (!store.stateLoaded) return
    var current = store.selectedProject ? store.selectedProject.root_path : ""
    var chosen = Projects.chooseProject(store.projects, current, store.storedProject)
    if (!chosen) { store.clearSelection(); return }
    if (store.stateReadOk && chosen.root_path !== store.storedProject) store.persistLastProject(chosen.root_path)
    if (chosen.root_path !== current) store.selectProject(chosen)
    else store.selectedProject = chosen
  }

  function clearSelection() {
    store.selectedProject = null
    store.watchedDbPath = ""
    store.cleared()
  }

  function selectProject(project) {
    store.selectedProject = project
    store.watchedDbPath = ""
    resolveDbPathProc.command = ["python3", store.backendDir + "projects/resolve-db-path.py", project.root_path]
    resolveDbPathProc.running = false
    resolveDbPathProc.running = true
    store.selected(project)
  }

  // The user picked a project in the dropdown.
  function chooseProject(project) {
    if (!project) return
    store.chosen()
    var current = store.selectedProject ? store.selectedProject.root_path : ""
    if (project.root_path !== current) {
      store.selectProject(project)
      store.persistLastProject(project.root_path)
    }
  }

  function applyStoredState(text, exitCode) {
    if (store.stateLoaded) return
    store.storedProject = Projects.parseStateResult(text, exitCode) || ""
    store.stateReadOk = (exitCode === 0 && String(text || "").trim() !== "")
    store.stateLoaded = true
    store.maybeSelectInitial()
  }

  function persistLastProject(path) {
    store.storedProject = path
    saveStateProc.command = ["python3", store.backendDir + "projects/viewer-state.py", "set-project", path]
    saveStateProc.running = false
    saveStateProc.running = true
  }

  // `brd projects` reads the global registry directly -- no cwd dependency,
  // unlike `brd tree`.
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
          store.applyProjectsList(list)
        } catch (e) {
          store.loadError = "Could not parse brd's project list."
        }
      }
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0 && store.projects.length === 0)
        store.loadError = "Could not list brd projects (is brd installed and on PATH?)."
    }
  }

  HelperRunner {
    id: stateRunner
    objectName: "stateRunner"
    script: store.backendDir + "projects/viewer-state.py"
    onFinished: function(stdout, exitCode, launchedGuard) { store.applyStoredState(stdout, exitCode) }
  }

  // A failed save is deliberately silent: it never blocks navigation.
  Process {
    id: saveStateProc
    objectName: "saveStateProc"
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
  }

  // If the state helper never answers (python3 missing, spawn failure) the
  // project list must not stay blocked: treat it as a failed read.
  Timer {
    id: stateWatchdog
    objectName: "stateWatchdog"
    interval: 2000
    running: true
    onTriggered: if (!store.stateLoaded) store.applyStoredState("", 1)
  }

  Process {
    id: resolveDbPathProc
    objectName: "resolveDbPathProc"
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var path = String(text || "").trim()
        store.watchedDbPath = path
      }
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) store.watchedDbPath = ""
    }
  }

  Component.onCompleted: stateRunner.run(["get"])
}
