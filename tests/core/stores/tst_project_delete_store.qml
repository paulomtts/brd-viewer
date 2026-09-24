// tests/core/stores/tst_project_delete_store.qml
// Removing a project: the typed confirmation, the helper call, and what the
// panel shows afterwards. Driven through App so the registry side is wired.
import QtQuick
import QtTest

TestCase {
  id: tc
  name: "StoresProjectDeleteStore"

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })
  property var pB: ({ root_path: "/home/u/b", name: "beta" })

  function make() {
    var comp = Qt.createComponent("../../../core/stores/App.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var app = comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
    app.projects.stateLoaded = true
    app.projects.stateReadOk = true
    app.projects.applyProjectsList([pA, pB])
    return app
  }

  function test_delete_flow() {
    var app = make(); if (!app) return
    var p = app.projects
    var d = app.deleter
    var proc = d.deleteProc
    verify(proc, "deleteProc found")

    d.openDelete(p.projects[1])
    compare(d.deleteTarget.name, "beta")
    d.confirmText = "delet"; d.performDelete(); compare(d.deleting, false)
    d.cancelDelete(); compare(d.deleteTarget, null)

    d.openDelete(p.projects[0])
    d.confirmText = " Delete "
    d.performDelete()
    compare(d.deleting, true)
    var cmd = proc.command
    compare(cmd[0], "python3")
    verify(String(cmd[1]).endsWith("snapshot-and-forget.py"))
    compare(cmd[2], "/home/u/a"); compare(cmd[3], "alpha")

    d.performDelete(); d.cancelDelete()
    compare(d.deleting, true)

    proc.outText = '{"ok": false, "error": "could not snapshot the project, so it was not removed"}'
    proc.exited(1)
    compare(d.deleting, false)
    verify(d.deleteTarget !== null)
    compare(d.deleteError, "could not snapshot the project, so it was not removed")

    d.confirmText = "delete"; d.performDelete()
    proc.outText = '{"ok": true, "snapshot": "/home/u/Snapshots/omarchy-project-manager/alpha-1"}'
    proc.exited(0)
    compare(d.deleting, false); compare(d.deleteTarget, null)
    compare(d.lastSnapshot, "/home/u/Snapshots/omarchy-project-manager/alpha-1")
    p.applyProjectsList([{ root_path: "/home/u/b", name: "beta" }])
    compare(p.selectedProject.root_path, "/home/u/b")
  }

  function test_after_a_delete_the_first_remaining_project_is_shown_and_saved() {
    var app = make(); if (!app) return
    var p = app.projects
    var d = app.deleter
    p.chooseProject(pB)
    d.openDelete(p.selectedProject)
    d.confirmText = "delete"
    d.performDelete()
    var del = d.deleteProc
    del.outText = '{"ok": true, "snapshot": "/home/u/Snapshots/omarchy-project-manager/beta-1"}'
    del.exited(0)
    compare(d.deleteTarget, null)
    compare(d.lastSnapshot, "/home/u/Snapshots/omarchy-project-manager/beta-1")
    p.applyProjectsList([pA])                       // what `brd projects` returns next
    compare(p.selectedProject.root_path, "/home/u/a")
    compare(d.lastSnapshot, "/home/u/Snapshots/omarchy-project-manager/beta-1")   // the note survives the reselection
    compare(p.saveStateProc.command[3], "/home/u/a")
  }

  function test_deleting_the_last_project_shows_the_empty_state() {
    var app = make(); if (!app) return
    var p = app.projects
    var d = app.deleter
    p.applyProjectsList([pA])
    d.openDelete(p.selectedProject)
    d.confirmText = "delete"; d.performDelete()
    var del = d.deleteProc
    del.outText = '{"ok": true, "snapshot": "/s"}'
    del.exited(0)
    p.applyProjectsList([])
    compare(p.selectedProject, null)
    compare(app.nav.viewMode, "board")
  }

  function test_a_successful_delete_refreshes_the_registry_and_resets_the_cursor() {
    var app = make(); if (!app) return
    var p = app.projects
    var d = app.deleter
    app.nav.cursorIndex = 5
    d.openDelete(pA)
    d.confirmText = "delete"; d.performDelete()
    d.deleteProc.outText = '{"ok": true, "snapshot": "/s"}'
    d.deleteProc.exited(0)
    compare(app.nav.cursorIndex, 0)
    compare(p.listProc.running, true, "the registry is re-read")
  }

  function test_opening_the_confirmation_closes_the_dropdown_and_clears_the_last_snapshot() {
    var app = make(); if (!app) return
    var d = app.deleter
    app.nav.toggleDropdown(0)
    compare(app.nav.dropdownOpen, true)
    d.lastSnapshot = "/s"
    d.openDelete(pA)
    compare(app.nav.dropdownOpen, false)
    compare(d.lastSnapshot, "")
    compare(d.confirmText, "")
    compare(d.deleteError, "")
  }

  function test_choosing_a_project_clears_the_delete_note() {
    var app = make(); if (!app) return
    var p = app.projects
    var d = app.deleter
    d.lastSnapshot = "/home/u/Snapshots/x"
    p.chooseProject(pB)
    compare(d.lastSnapshot, "")
  }

  function test_opening_the_panel_drops_a_half_typed_confirmation_but_not_a_running_delete() {
    var app = make(); if (!app) return
    var p = app.projects
    var d = app.deleter
    d.openDelete(pA)
    d.confirmText = "del"
    d.deleteError = "boom"
    p.onPanelOpened()
    compare(d.deleteTarget, null)
    compare(d.confirmText, "")
    compare(d.deleteError, "")

    d.openDelete(pA)
    d.confirmText = "delete"; d.performDelete()
    compare(d.deleting, true)
    p.onPanelOpened()
    verify(d.deleteTarget !== null, "a delete in flight keeps its target")
  }
}
