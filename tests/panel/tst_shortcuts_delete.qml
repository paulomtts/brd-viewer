import QtQuick
import QtTest
TestCase {
  id: tc
  name: "ShortcutsAndDelete"
  when: windowShown
  width: 400; height: 700
  Component { id: hostC; Item { width: 400; height: 700 } }

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })
  property var pB: ({ root_path: "/home/u/b", name: "beta" })
  function ctrl(key) { return { modifiers: Qt.ControlModifier, key: key, accepted: false } }
  function plain(key) { return { modifiers: Qt.NoModifier, key: key, accepted: false } }

  function make() {
    var host = createTemporaryObject(hostC, tc)
    var comp = Qt.createComponent("Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var p = comp.createObject(host)
    p.opened = true
    p.stateLoaded = true
    p.stateReadOk = true
    p.applyProjectsList([pA, pB])
    return p
  }
  function find(item, name) {
    if (item.objectName === name) return item
    for (var i = 0; i < item.children.length; i++) { var r = find(item.children[i], name); if (r) return r }
    return null
  }
  function proc(p, name) {
    for (var i = 0; i < p.data.length; i++) if (p.data[i] && p.data[i].objectName === name) return p.data[i]
    return null
  }

  function test_ctrl_p_toggles_the_dropdown() {
    var p = make(); if (!p) return
    compare(p.handleGlobalKey(ctrl(Qt.Key_P)), true)
    compare(p.dropdownOpen, true)
    compare(p.handleGlobalKey(ctrl(Qt.Key_P)), true)
    compare(p.dropdownOpen, false)
  }

  function test_ctrl_digits_switch_sections() {
    var p = make(); if (!p) return
    p.chooseProject(pB)
    compare(p.handleGlobalKey(ctrl(Qt.Key_1)), true)
    compare(p.viewMode, "board")
    compare(p.handleGlobalKey(ctrl(Qt.Key_2)), true)
    compare(p.viewMode, "documents")
    compare(p.handleGlobalKey(ctrl(Qt.Key_1)), true)
    compare(p.viewMode, "board")
  }

  function test_other_keys_are_not_handled() {
    var p = make(); if (!p) return
    compare(p.handleGlobalKey(plain(Qt.Key_P)), false)
    compare(p.handleGlobalKey(ctrl(Qt.Key_X)), false)
    compare(p.handleGlobalKey(plain(Qt.Key_1)), false)
    compare(p.dropdownOpen, false)
  }

  function test_shortcuts_are_ignored_while_confirming_a_delete() {
    var p = make(); if (!p) return
    p.openDelete(p.selectedProject)
    compare(p.handleGlobalKey(ctrl(Qt.Key_P)), false)
    compare(p.handleGlobalKey(ctrl(Qt.Key_1)), false)
    compare(p.dropdownOpen, false)
  }

  function test_escape_with_the_dropdown_open_closes_only_the_dropdown() {
    var p = make(); if (!p) return
    p.toggleDropdown()
    var sb = find(p, "sidebar")
    verify(sb, "sidebar found")
    sb.dropdownCancel()
    compare(p.dropdownOpen, false)
    compare(p.opened, true)
  }

  function test_the_sidebar_delete_button_starts_the_confirmation_for_the_selected_project() {
    var p = make(); if (!p) return
    p.chooseProject(pB)
    var sb = find(p, "sidebar")
    compare(sb.canDelete, true)
    sb.deleteRequested()
    compare(p.deleteTarget.root_path, "/home/u/b")
  }

  function test_delete_is_disabled_without_a_project_or_while_busy() {
    var p = make(); if (!p) return
    var sb = find(p, "sidebar")
    p.openDelete(p.selectedProject)
    compare(sb.canDelete, false)
    p.cancelDelete()
    compare(sb.canDelete, true)
    p.applyProjectsList([])
    compare(sb.canDelete, false)
  }

  function test_after_a_delete_the_first_remaining_project_is_shown_and_saved() {
    var p = make(); if (!p) return
    p.chooseProject(pB)
    p.openDelete(p.selectedProject)
    p.confirmText = "delete"
    p.performDelete()
    var del = proc(p, "deleteProc")
    del.outText = '{"ok": true, "snapshot": "/home/u/Snapshots/brd-viewer/beta-1"}'
    del.exited(0)
    compare(p.deleteTarget, null)
    compare(p.lastSnapshot, "/home/u/Snapshots/brd-viewer/beta-1")
    p.applyProjectsList([pA])                       // what `brd projects` returns next
    compare(p.selectedProject.root_path, "/home/u/a")
    compare(p.lastSnapshot, "/home/u/Snapshots/brd-viewer/beta-1")   // the note survives the reselection
    compare(proc(p, "saveStateProc").command[3], "/home/u/a")
  }

  function test_deleting_the_last_project_shows_the_empty_state() {
    var p = make(); if (!p) return
    p.applyProjectsList([pA])
    p.openDelete(p.selectedProject)
    p.confirmText = "delete"; p.performDelete()
    var del = proc(p, "deleteProc")
    del.outText = '{"ok": true, "snapshot": "/s"}'
    del.exited(0)
    p.applyProjectsList([])
    compare(p.selectedProject, null)
    compare(p.viewMode, "board")
  }
}
