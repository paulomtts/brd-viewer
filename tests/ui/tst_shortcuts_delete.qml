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
    var comp = Qt.createComponent("../../ui/Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var p = comp.createObject(host)
    p.opened = true
    p.app.projects.stateLoaded = true
    p.app.projects.stateReadOk = true
    p.app.projects.applyProjectsList([pA, pB])
    return p
  }
  function find(item, name) {
    if (item.objectName === name) return item
    for (var i = 0; i < item.children.length; i++) { var r = find(item.children[i], name); if (r) return r }
    return null
  }
  function test_ctrl_p_toggles_the_dropdown() {
    var p = make(); if (!p) return
    compare(p.handleGlobalKey(ctrl(Qt.Key_P)), true)
    compare(p.app.nav.dropdownOpen, true)
    compare(p.handleGlobalKey(ctrl(Qt.Key_P)), true)
    compare(p.app.nav.dropdownOpen, false)
  }

  function test_ctrl_digits_switch_sections() {
    var p = make(); if (!p) return
    p.chooseProject(pB)
    compare(p.handleGlobalKey(ctrl(Qt.Key_1)), true)
    compare(p.app.nav.viewMode, "board")
    compare(p.handleGlobalKey(ctrl(Qt.Key_2)), true)
    compare(p.app.nav.viewMode, "documents")
    compare(p.handleGlobalKey(ctrl(Qt.Key_1)), true)
    compare(p.app.nav.viewMode, "board")
  }

  function test_other_keys_are_not_handled() {
    var p = make(); if (!p) return
    compare(p.handleGlobalKey(plain(Qt.Key_P)), false)
    compare(p.handleGlobalKey(ctrl(Qt.Key_X)), false)
    compare(p.handleGlobalKey(plain(Qt.Key_1)), false)
    compare(p.app.nav.dropdownOpen, false)
  }

  function test_shortcuts_are_ignored_while_confirming_a_delete() {
    var p = make(); if (!p) return
    p.app.deleter.openDelete(p.app.projects.selectedProject)
    compare(p.handleGlobalKey(ctrl(Qt.Key_P)), false)
    compare(p.handleGlobalKey(ctrl(Qt.Key_1)), false)
    compare(p.app.nav.dropdownOpen, false)
  }

  function test_escape_with_the_dropdown_open_closes_only_the_dropdown() {
    var p = make(); if (!p) return
    p.toggleDropdown()
    var sb = find(p, "sidebar")
    verify(sb, "sidebar found")
    sb.dropdownCancel()
    compare(p.app.nav.dropdownOpen, false)
    compare(p.opened, true)
  }

  function test_the_sidebar_delete_button_starts_the_confirmation_for_the_selected_project() {
    var p = make(); if (!p) return
    p.chooseProject(pB)
    var sb = find(p, "sidebar")
    compare(sb.canDelete, true)
    sb.deleteRequested()
    compare(p.app.deleter.deleteTarget.root_path, "/home/u/b")
  }

  function test_delete_is_disabled_without_a_project_or_while_busy() {
    var p = make(); if (!p) return
    var sb = find(p, "sidebar")
    p.app.deleter.openDelete(p.app.projects.selectedProject)
    compare(sb.canDelete, false)
    p.app.deleter.cancelDelete()
    compare(sb.canDelete, true)
    p.app.projects.applyProjectsList([])
    compare(sb.canDelete, false)
  }

}
