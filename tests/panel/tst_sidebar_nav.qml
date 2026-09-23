import QtQuick
import QtTest
TestCase {
  id: tc
  name: "SidebarNav"
  when: windowShown
  width: 400; height: 700
  Component { id: hostC; Item { width: 400; height: 700 } }

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })
  property var pB: ({ root_path: "/home/u/b", name: "beta" })
  property var pC: ({ root_path: "/home/u/c", name: "gamma" })

  function make() {
    var host = createTemporaryObject(hostC, tc)
    var comp = Qt.createComponent("Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var p = comp.createObject(host)
    p.opened = true
    return p
  }
  function names(list) { return list.map(function(x) { return x.name }).join(",") }

  function test_first_project_is_selected_when_the_list_arrives() {
    var p = make(); if (!p) return
    compare(p.viewMode, "board")
    compare(p.selectedProject, null)
    p.applyProjectsList([pA, pB, pC])
    compare(p.selectedProject.root_path, "/home/u/a")
    compare(p.viewMode, "board")
  }

  function test_stored_project_wins_over_the_first() {
    var p = make(); if (!p) return
    p.storedProject = "/home/u/c"
    p.applyProjectsList([pA, pB, pC])
    compare(p.selectedProject.root_path, "/home/u/c")
  }

  function test_current_project_is_kept_when_the_list_refreshes() {
    var p = make(); if (!p) return
    p.applyProjectsList([pA, pB, pC])
    p.chooseProject(pB)
    p.applyProjectsList([pA, pB, pC])
    compare(p.selectedProject.root_path, "/home/u/b")
  }

  function test_vanished_current_project_falls_back() {
    var p = make(); if (!p) return
    p.applyProjectsList([pA, pB, pC])
    p.chooseProject(pB)
    p.applyProjectsList([pA, pC])
    compare(p.selectedProject.root_path, "/home/u/a")
  }

  function test_empty_registry_clears_the_selection() {
    var p = make(); if (!p) return
    p.applyProjectsList([pA, pB])
    p.applyTreeData([{ id: "x", title: "X", status: "todo", blocked_by: [], children: [] }])
    p.applyProjectsList([])
    compare(p.selectedProject, null)
    compare(p.cardRoots.length, 0)
    compare(p.viewMode, "board")
    p.showSection("board")
    compare(p.viewMode, "board")
  }

  function test_choose_project_switches_persists_and_closes_the_dropdown() {
    var p = make(); if (!p) return
    p.applyProjectsList([pA, pB, pC])
    p.toggleDropdown()
    compare(p.dropdownOpen, true)
    p.chooseProject(pC)
    compare(p.dropdownOpen, false)
    compare(p.selectedProject.root_path, "/home/u/c")
    compare(p.storedProject, "/home/u/c")
    compare(p.viewMode, "board")
  }

  function test_dropdown_keyboard() {
    var p = make(); if (!p) return
    p.applyProjectsList([pA, pB, pC])
    p.toggleDropdown()
    compare(p.dropdownCursor, 0)              // starts on the current project
    p.moveDropdown(1); compare(p.dropdownCursor, 1)
    p.moveDropdown(9); compare(p.dropdownCursor, 2)
    p.moveDropdown(-9); compare(p.dropdownCursor, 0)
    p.dropdownQuery = "gam"
    compare(names(p.filteredProjects), "gamma")
    p.dropdownCursor = 0
    p.acceptDropdown()
    compare(p.selectedProject.root_path, "/home/u/c")
    compare(p.dropdownOpen, false)
    compare(p.dropdownQuery, "")
  }

  function test_dropdown_opens_on_the_current_project_and_toggles_closed() {
    var p = make(); if (!p) return
    p.applyProjectsList([pA, pB, pC])
    p.chooseProject(pB)
    p.toggleDropdown()
    compare(p.dropdownCursor, 1)
    p.toggleDropdown()
    compare(p.dropdownOpen, false)
  }

  function test_dropdown_cannot_open_during_delete_confirmation() {
    var p = make(); if (!p) return
    p.applyProjectsList([pA, pB])
    p.openDelete(p.selectedProject)
    p.toggleDropdown()
    compare(p.dropdownOpen, false)
  }

  function test_documents_section_is_unavailable_in_phase_a() {
    var p = make(); if (!p) return
    p.applyProjectsList([pA])
    compare(p.documentsEnabled, false)
    p.showSection("documents")
    compare(p.viewMode, "board")
    compare(p.section, "board")
  }

  function test_back_from_the_board_does_nothing_and_from_a_card_returns_to_the_board() {
    var p = make(); if (!p) return
    p.applyProjectsList([pA])
    p.applyTreeData([{ id: "m", title: "M", status: "todo", blocked_by: [], children: [] }])
    p.goBack()
    compare(p.viewMode, "board")
    p.cursorIndex = 0; p.activateCursor()
    compare(p.viewMode, "entry")
    p.goBack()
    compare(p.viewMode, "board")
  }

  function test_opening_the_panel_resets_transient_state() {
    var p = make(); if (!p) return
    p.applyProjectsList([pA, pB])
    p.toggleDropdown(); p.dropdownQuery = "x"
    p.opened = false; p.opened = true
    compare(p.dropdownOpen, false); compare(p.dropdownQuery, "")
  }
}
