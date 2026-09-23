import QtQuick
import QtTest
TestCase {
  id: tc
  name: "Persistence"
  when: windowShown
  width: 400; height: 700
  Component { id: hostC; Item { width: 400; height: 700 } }

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })
  property var pB: ({ root_path: "/home/u/b", name: "beta" })

  function make() {
    var host = createTemporaryObject(hostC, tc)
    var comp = Qt.createComponent("Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var p = comp.createObject(host)
    p.opened = true
    return p
  }
  function proc(p, name) {
    for (var i = 0; i < p.data.length; i++) if (p.data[i] && p.data[i].objectName === name) return p.data[i]
    return null
  }

  function test_the_state_is_requested_at_startup() {
    var p = make(); if (!p) return
    var get = proc(p, "stateGetProc")
    verify(get, "stateGetProc exists")
    compare(get.command[0], "python3")
    verify(String(get.command[1]).endsWith("viewer-state.py"))
    compare(get.command[2], "get")
    compare(get.running, true)
  }

  function test_nothing_is_selected_until_the_state_has_answered() {
    var p = make(); if (!p) return
    p.applyProjectsList([pA, pB])
    compare(p.stateLoaded, false)
    compare(p.selectedProject, null)
    p.applyStoredState('{"last_project": "/home/u/b"}', 0)
    compare(p.stateLoaded, true)
    compare(p.selectedProject.root_path, "/home/u/b")
  }

  function test_the_state_arriving_first_also_works() {
    var p = make(); if (!p) return
    p.applyStoredState('{"last_project": "/home/u/b"}', 0)
    compare(p.selectedProject, null)
    p.applyProjectsList([pA, pB])
    compare(p.selectedProject.root_path, "/home/u/b")
  }

  function test_a_stale_stored_project_falls_back_to_the_first() {
    var p = make(); if (!p) return
    p.applyStoredState('{"last_project": "/home/u/gone"}', 0)
    p.applyProjectsList([pA, pB])
    compare(p.selectedProject.root_path, "/home/u/a")
  }

  function test_a_failed_or_corrupt_state_read_means_the_first_project() {
    var p = make(); if (!p) return
    p.applyStoredState("boom", 1)
    p.applyProjectsList([pA, pB])
    compare(p.selectedProject.root_path, "/home/u/a")
  }

  function test_choosing_a_project_saves_it() {
    var p = make(); if (!p) return
    p.applyStoredState('{"last_project": null}', 0)
    p.applyProjectsList([pA, pB])
    var save = proc(p, "saveStateProc")
    verify(save, "saveStateProc exists")
    p.chooseProject(pB)
    compare(save.command[2], "set-project")
    compare(save.command[3], "/home/u/b")
    compare(save.running, true)
  }

  function test_an_unchanged_selection_is_not_rewritten() {
    var p = make(); if (!p) return
    p.applyStoredState('{"last_project": "/home/u/a"}', 0)
    var save = proc(p, "saveStateProc")
    verify(save, "saveStateProc exists")
    p.applyProjectsList([pA, pB])
    compare(save.command, undefined)
    p.chooseProject(pA)
    compare(save.command, undefined)
  }

  function test_the_fallback_after_a_removal_is_saved() {
    var p = make(); if (!p) return
    p.applyStoredState('{"last_project": "/home/u/b"}', 0)
    p.applyProjectsList([pA, pB])
    p.applyProjectsList([pA])
    var save = proc(p, "saveStateProc")
    verify(save, "saveStateProc exists")
    compare(save.command[3], "/home/u/a")
    compare(p.storedProject, "/home/u/a")
  }

  function test_an_empty_registry_keeps_the_stored_choice() {
    var p = make(); if (!p) return
    p.applyStoredState('{"last_project": "/home/u/b"}', 0)
    p.applyProjectsList([])
    compare(p.selectedProject, null)
    compare(p.storedProject, "/home/u/b")
  }
}
