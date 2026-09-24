// tests/core/stores/tst_project_store.qml
// The project registry, the initial choice and the persisted "last project",
// driven through App so the cross-store wiring (nav) is exercised too.
import QtQuick
import QtTest

TestCase {
  id: tc
  name: "StoresProjectStore"

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })
  property var pB: ({ root_path: "/home/u/b", name: "beta" })

  function make() {
    var comp = Qt.createComponent("../../../core/stores/App.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    return comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
  }

  function test_the_state_is_requested_at_startup() {
    var app = make(); if (!app) return
    var get = app.projects.stateRunner.current
    verify(get, "the state helper is running")
    compare(get.command[0], "python3")
    verify(String(get.command[1]).endsWith("viewer-state.py"))
    compare(get.command[2], "get")
    compare(get.running, true)
  }

  function test_nothing_is_selected_until_the_state_has_answered() {
    var app = make(); if (!app) return
    var p = app.projects
    p.applyProjectsList([pA, pB])
    compare(p.stateLoaded, false)
    compare(p.selectedProject, null)
    p.applyStoredState('{"last_project": "/home/u/b"}', 0)
    compare(p.stateLoaded, true)
    compare(p.selectedProject.root_path, "/home/u/b")
  }

  function test_the_state_arriving_first_also_works() {
    var app = make(); if (!app) return
    var p = app.projects
    p.applyStoredState('{"last_project": "/home/u/b"}', 0)
    compare(p.selectedProject, null)
    p.applyProjectsList([pA, pB])
    compare(p.selectedProject.root_path, "/home/u/b")
  }

  function test_a_stale_stored_project_falls_back_to_the_first() {
    var app = make(); if (!app) return
    var p = app.projects
    p.applyStoredState('{"last_project": "/home/u/gone"}', 0)
    p.applyProjectsList([pA, pB])
    compare(p.selectedProject.root_path, "/home/u/a")
  }

  function test_a_failed_or_corrupt_state_read_means_the_first_project() {
    var app = make(); if (!app) return
    var p = app.projects
    p.applyStoredState("boom", 1)
    p.applyProjectsList([pA, pB])
    compare(p.selectedProject.root_path, "/home/u/a")
  }

  function test_choosing_a_project_saves_it() {
    var app = make(); if (!app) return
    var p = app.projects
    p.applyStoredState('{"last_project": null}', 0)
    p.applyProjectsList([pA, pB])
    var save = p.saveStateProc
    verify(save, "saveStateProc exists")
    p.chooseProject(pB)
    compare(save.command[2], "set-project")
    compare(save.command[3], "/home/u/b")
    compare(save.running, true)
  }

  function test_an_unchanged_selection_is_not_rewritten() {
    var app = make(); if (!app) return
    var p = app.projects
    p.applyStoredState('{"last_project": "/home/u/a"}', 0)
    var save = p.saveStateProc
    verify(save, "saveStateProc exists")
    p.applyProjectsList([pA, pB])
    compare(save.command, undefined)
    p.chooseProject(pA)
    compare(save.command, undefined)
  }

  function test_the_fallback_after_a_removal_is_saved() {
    var app = make(); if (!app) return
    var p = app.projects
    p.applyStoredState('{"last_project": "/home/u/b"}', 0)
    p.applyProjectsList([pA, pB])
    p.applyProjectsList([pA])
    var save = p.saveStateProc
    verify(save, "saveStateProc exists")
    compare(save.command[3], "/home/u/a")
    compare(p.storedProject, "/home/u/a")
  }

  function test_an_empty_registry_keeps_the_stored_choice() {
    var app = make(); if (!app) return
    var p = app.projects
    p.applyStoredState('{"last_project": "/home/u/b"}', 0)
    p.applyProjectsList([])
    compare(p.selectedProject, null)
    compare(p.storedProject, "/home/u/b")
  }

  function test_a_failed_read_does_not_overwrite_the_stored_state() {
    var app = make(); if (!app) return
    var p = app.projects
    var save = p.saveStateProc
    verify(save, "saveStateProc exists")
    p.applyStoredState("boom", 1)
    p.applyProjectsList([pA, pB])
    compare(p.selectedProject.root_path, "/home/u/a")
    compare(save.command, undefined)
  }

  function test_an_empty_read_does_not_overwrite_the_stored_state() {
    var app = make(); if (!app) return
    var p = app.projects
    var save = p.saveStateProc
    verify(save, "saveStateProc exists")
    p.applyStoredState("", 0)
    p.applyProjectsList([pA, pB])
    compare(p.selectedProject.root_path, "/home/u/a")
    compare(save.command, undefined)
  }

  function test_an_explicit_choice_after_a_failed_read_is_saved() {
    var app = make(); if (!app) return
    var p = app.projects
    var save = p.saveStateProc
    verify(save, "saveStateProc exists")
    p.applyStoredState("boom", 1)
    p.applyProjectsList([pA, pB])
    p.chooseProject(pB)
    compare(save.command[3], "/home/u/b")
  }

  function test_a_good_null_read_saves_the_first_project() {
    var app = make(); if (!app) return
    var p = app.projects
    var save = p.saveStateProc
    verify(save, "saveStateProc exists")
    p.applyStoredState('{"last_project": null}', 0)
    p.applyProjectsList([pA, pB])
    compare(save.command[3], "/home/u/a")
  }

  function test_the_watchdog_selects_the_first_project_when_the_state_never_answers() {
    var app = make(); if (!app) return
    var p = app.projects
    var save = p.saveStateProc
    var dog = p.stateWatchdog
    verify(dog, "stateWatchdog exists")
    compare(dog.interval, 2000)
    p.applyProjectsList([pA, pB])
    compare(p.selectedProject, null)
    dog.triggered()
    compare(p.stateLoaded, true)
    compare(p.selectedProject.root_path, "/home/u/a")
    compare(save.command, undefined)
  }

  function test_the_watchdog_does_nothing_once_the_state_has_answered() {
    var app = make(); if (!app) return
    var p = app.projects
    var dog = p.stateWatchdog
    verify(dog, "stateWatchdog exists")
    p.applyStoredState('{"last_project": "/home/u/b"}', 0)
    p.applyProjectsList([pA, pB])
    dog.triggered()
    compare(p.selectedProject.root_path, "/home/u/b")
    compare(p.storedProject, "/home/u/b")
    compare(p.stateReadOk, true)
  }

  function test_a_late_state_reply_after_the_watchdog_changes_nothing() {
    var app = make(); if (!app) return
    var p = app.projects
    var dog = p.stateWatchdog
    verify(dog, "stateWatchdog exists")
    p.applyProjectsList([pA, pB])
    dog.triggered()
    p.applyStoredState('{"last_project": "/home/u/b"}', 0)
    compare(p.selectedProject.root_path, "/home/u/a")
    compare(p.storedProject, "")
    compare(p.stateReadOk, false)
  }

  // ---- the parts the panel used to own

  function test_the_state_helpers_answer_is_applied_through_the_runner() {
    var app = make(); if (!app) return
    var p = app.projects
    var get = p.stateRunner.current
    get.outText = '{"last_project": "/home/u/b"}'
    get.exited(0)
    compare(p.stateLoaded, true)
    compare(p.stateReadOk, true)
    compare(p.storedProject, "/home/u/b")
  }

  function test_the_registry_is_parsed_sorted_and_applied() {
    var app = make(); if (!app) return
    var p = app.projects
    p.applyStoredState('{"last_project": null}', 0)
    p.refreshProjects()
    compare(p.listProc.command[0], "brd")
    compare(p.listProc.command[1], "projects")
    compare(p.listProc.running, true)
    p.listProc.stdout.text = '{"data": [{"root_path": "/home/u/b", "name": "beta"}, {"root_path": "/home/u/a", "name": "alpha"}]}'
    p.listProc.stdout.streamFinished()
    compare(p.projects.length, 2)
    compare(p.projects[0].name, "alpha")
    compare(p.selectedProject.root_path, "/home/u/a")
    compare(p.loadError, "")
  }

  function test_an_unreadable_registry_reports_a_load_error() {
    var app = make(); if (!app) return
    var p = app.projects
    p.refreshProjects()
    p.listProc.stdout.text = "not json"
    p.listProc.stdout.streamFinished()
    compare(p.loadError, "Could not parse brd's project list.")
    p.loadError = ""
    p.listProc.exited(1)
    compare(p.loadError, "Could not list brd projects (is brd installed and on PATH?).")
  }

  function test_selecting_a_project_resolves_its_database_path() {
    var app = make(); if (!app) return
    var p = app.projects
    p.applyStoredState('{"last_project": null}', 0)
    p.applyProjectsList([pA, pB])
    var resolve = p.resolveDbPathProc
    verify(String(resolve.command[1]).endsWith("resolve-db-path.py"))
    compare(resolve.command[2], "/home/u/a")
    compare(resolve.running, true)
    resolve.stdout.text = "/home/u/a/.brd/brd.db\n"
    resolve.stdout.streamFinished()
    compare(p.watchedDbPath, "/home/u/a/.brd/brd.db")
    p.chooseProject(pB)
    compare(p.watchedDbPath, "", "the old project's database is dropped at once")
    resolve.exited(1)
    compare(p.watchedDbPath, "")
  }

  function test_a_project_change_resets_the_navigation() {
    var app = make(); if (!app) return
    var p = app.projects
    p.applyStoredState('{"last_project": null}', 0)
    p.applyProjectsList([pA, pB])
    app.nav.viewMode = "documents"
    app.nav.searchQuery = "spec"
    app.nav.cursorIndex = 3
    p.chooseProject(pB)
    compare(app.nav.viewMode, "board")
    compare(app.nav.searchQuery, "")
    compare(app.nav.cursorIndex, 0)
  }

  function test_the_filtered_list_follows_the_dropdown_query() {
    var app = make(); if (!app) return
    var p = app.projects
    p.applyStoredState('{"last_project": null}', 0)
    p.applyProjectsList([pA, pB])
    compare(p.filteredProjects.length, 2)
    app.nav.dropdownQuery = "bet"
    compare(p.filteredProjects.length, 1)
    compare(p.filteredProjects[0].name, "beta")
  }

  function test_opening_the_panel_refreshes_the_registry_and_clears_the_dropdown() {
    var app = make(); if (!app) return
    var p = app.projects
    app.nav.dropdownOpen = true
    app.nav.dropdownQuery = "x"
    p.onPanelOpened()
    compare(app.nav.dropdownOpen, false)
    compare(app.nav.dropdownQuery, "")
    compare(p.listProc.running, true)
  }
}
