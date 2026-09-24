import QtQuick
import QtTest
TestCase {
  id: testCase
  name: "DeleteFlow"
  when: windowShown
  visible: true
  width: 400; height: 700
  Component { id: hostC; Item { width: 400; height: 700 } }

  function procByName(p, name) {
    for (var i = 0; i < p.data.length; i++)
      if (p.data[i] && p.data[i].objectName === name) return p.data[i]
    return null
  }

  function test_delete_flow() {
    var host = createTemporaryObject(hostC, testCase)
    var comp = Qt.createComponent("Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return }
    var p = comp.createObject(host)
    p.opened = true
    p.stateLoaded = true
    p.applyProjectsList([{ root_path: "/home/u/a", name: "alpha" }, { root_path: "/home/u/b", name: "beta" }])
    wait(50)
    var proc = procByName(p, "deleteProc")
    verify(proc, "deleteProc found (Task 1 gives it objectName deleteProc)")

    p.openDelete(p.projects[1])
    compare(p.deleteTarget.name, "beta")
    compare(p.displayPath("/home/u/b"), "~/b")
    p.confirmText = "delet"; p.performDelete(); compare(p.deleting, false)
    p.cancelDelete(); compare(p.deleteTarget, null)

    p.openDelete(p.projects[0])
    p.confirmText = " Delete "
    p.performDelete()
    compare(p.deleting, true)
    var cmd = proc.command
    compare(cmd[0], "python3")
    verify(String(cmd[1]).endsWith("snapshot-and-forget.py"))
    compare(cmd[2], "/home/u/a"); compare(cmd[3], "alpha")

    p.performDelete(); p.cancelDelete()
    compare(p.deleting, true)

    proc.outText = '{"ok": false, "error": "could not snapshot the project, so it was not removed"}'
    proc.exited(1)
    compare(p.deleting, false)
    verify(p.deleteTarget !== null)
    compare(p.deleteError, "could not snapshot the project, so it was not removed")

    p.confirmText = "delete"; p.performDelete()
    proc.outText = '{"ok": true, "snapshot": "/home/u/Snapshots/omarchy-project-manager/alpha-1"}'
    proc.exited(0)
    compare(p.deleting, false); compare(p.deleteTarget, null)
    compare(p.lastSnapshot, "/home/u/Snapshots/omarchy-project-manager/alpha-1")
    p.applyProjectsList([{ root_path: "/home/u/b", name: "beta" }])
    compare(p.selectedProject.root_path, "/home/u/b")
  }

  function findIn(item, name) {
    if (item.objectName === name) return item
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) { var r = findIn(kids[i], name); if (r) return r }
    return null
  }
  function inside(item, name) {
    for (var it = item; it; it = it.parent) if (it.objectName === name) return true
    return false
  }
  function makePanel() {
    var host = createTemporaryObject(hostC, testCase)
    var p = Qt.createComponent("Panel.qml").createObject(host)
    p.opened = true
    p.stateLoaded = true
    p.applyProjectsList([{ root_path: "/home/u/a", name: "alpha" }, { root_path: "/home/u/b", name: "beta" }])
    wait(50)
    return { host: host, p: p }
  }

  function test_the_confirmation_is_a_modal_over_a_backdrop() {
    var m = makePanel()
    var modal = findIn(m.host, "deleteModal")
    verify(modal, "deleteModal")
    compare(modal.visible, false)
    m.p.openDelete(m.p.selectedProject)
    compare(modal.visible, true)
    var field = findIn(m.host, "confirmField")
    verify(inside(field, "deleteModal"), "confirm field is inside the modal")
    verify(!inside(field, "panelFlick"), "and not in the scrolling content")
    verify(findIn(modal, "deleteBackdrop"), "backdrop")
    var card = findIn(modal, "deleteCard")
    verify(card.width > 0 && card.width < modal.width, "a card narrower than the popup")
    m.p.cancelDelete()
    compare(modal.visible, false)
  }

  function test_clicking_the_backdrop_cancels_but_not_while_deleting() {
    var m = makePanel()
    var modal = findIn(m.host, "deleteModal")
    m.p.openDelete(m.p.selectedProject)
    var backdrop = findIn(modal, "deleteBackdrop")
    mouseClick(backdrop, 2, 2)
    compare(m.p.deleteTarget, null)
    m.p.openDelete(m.p.selectedProject)
    m.p.deleting = true
    mouseClick(backdrop, 2, 2)
    verify(m.p.deleteTarget !== null)
    m.p.deleting = false
  }

  function test_clicks_on_the_card_do_not_dismiss_it() {
    var m = makePanel()
    var modal = findIn(m.host, "deleteModal")
    m.p.openDelete(m.p.selectedProject)
    var card = findIn(modal, "deleteCard")
    mouseClick(card, 3, 3)
    verify(m.p.deleteTarget !== null)
  }
}
