import QtQuick
import QtTest
TestCase {
  id: testCase
  name: "DeleteFlow"
  when: windowShown
  visible: true
  width: 400; height: 700
  Component { id: hostC; Item { width: 400; height: 700 } }

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
    var p = Qt.createComponent("../../Panel.qml").createObject(host)
    p.opened = true
    p.app.projects.stateLoaded = true
    p.app.projects.applyProjectsList([{ root_path: "/home/u/a", name: "alpha" }, { root_path: "/home/u/b", name: "beta" }])
    wait(50)
    return { host: host, p: p }
  }

  function test_the_confirmation_is_a_modal_over_a_backdrop() {
    var m = makePanel()
    var modal = findIn(m.host, "deleteModal")
    verify(modal, "deleteModal")
    compare(modal.visible, false)
    m.p.app.deleter.openDelete(m.p.app.projects.selectedProject)
    compare(modal.visible, true)
    compare(m.p.displayPath("/home/u/b"), "~/b")
    var field = findIn(m.host, "confirmField")
    verify(inside(field, "deleteModal"), "confirm field is inside the modal")
    verify(!inside(field, "panelFlick"), "and not in the scrolling content")
    verify(findIn(modal, "deleteBackdrop"), "backdrop")
    var card = findIn(modal, "deleteCard")
    verify(card.width > 0 && card.width < modal.width, "a card narrower than the popup")
    m.p.app.deleter.cancelDelete()
    compare(modal.visible, false)
  }

  function test_clicking_the_backdrop_cancels_but_not_while_deleting() {
    var m = makePanel()
    var modal = findIn(m.host, "deleteModal")
    m.p.app.deleter.openDelete(m.p.app.projects.selectedProject)
    var backdrop = findIn(modal, "deleteBackdrop")
    mouseClick(backdrop, 2, 2)
    compare(m.p.app.deleter.deleteTarget, null)
    m.p.app.deleter.openDelete(m.p.app.projects.selectedProject)
    m.p.app.deleter.deleting = true
    mouseClick(backdrop, 2, 2)
    verify(m.p.app.deleter.deleteTarget !== null)
    m.p.app.deleter.deleting = false
  }

  function test_clicks_on_the_card_do_not_dismiss_it() {
    var m = makePanel()
    var modal = findIn(m.host, "deleteModal")
    m.p.app.deleter.openDelete(m.p.app.projects.selectedProject)
    var card = findIn(modal, "deleteCard")
    mouseClick(card, 3, 3)
    verify(m.p.app.deleter.deleteTarget !== null)
  }
}
