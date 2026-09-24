import QtQuick
import QtTest
TestCase {
  id: testCase
  name: "BoardFlow"
  when: windowShown
  width: 400; height: 700
  Component { id: hostC; Item { width: 400; height: 700 } }

  function card(id, title, status, children, blockedBy) {
    return { id: id, title: title, status: status, description: "d", blocked_by: blockedBy || [], children: children || [] }
  }
  function ids(list) { return list.map(function(x) { return x.id }).join(",") }

  function test_board_and_detail_flow() {
    var host = createTemporaryObject(hostC, testCase)
    var comp = Qt.createComponent("../../Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return }
    var p = comp.createObject(host)
    p.opened = true
    p.app.projects.stateLoaded = true
    p.app.projects.applyProjectsList([{ root_path: "/x", name: "proj" }])
    var t1 = card("t1", "Task1", "blocked", [], ["x1"])
    var t2 = card("t2", "Task2", "done")
    var s1 = card("s1", "Story", "in_progress", [t1, t2])
    var m1 = card("m1", "Milestone", "todo", [s1])
    var x1 = card("x1", "Ex", "done")
    var b1 = card("b1", "Blk", "blocked")
    p.applyTreeData([m1, x1, b1])
    wait(50)
    compare(ids(p.boardCards), "m1,b1,x1")
    p.moveCursor(1); compare(p.app.nav.cursorIndex, 1)
    p.moveCursor(5); compare(p.app.nav.cursorIndex, 2)
    p.moveCursor(-1)
    p.activateCursor()
    compare(p.app.nav.viewMode, "entry"); compare(p.selectedCardId, "b1")
    p.goBack()
    compare(p.app.nav.viewMode, "board"); compare(p.app.nav.cursorIndex, 1)
    p.app.nav.cursorIndex = 0
    p.activateCursor(); compare(p.selectedCardId, "m1")
    p.activateCursor(); compare(p.selectedCardId, "s1")
    compare(p.detailLinkList.map(function(l) { return l.section }).join(","), "parent,child,child")
    p.moveCursor(1); p.activateCursor(); compare(p.selectedCardId, "t1")
    compare(p.detailLinkList.map(function(l) { return l.section + ":" + l.id }).join(","), "parent:s1,blocker:x1")
    p.applyTreeData([x1])
    compare(p.app.nav.viewMode, "board")
  }
}
