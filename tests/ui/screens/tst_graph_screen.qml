// tests/ui/screens/tst_graph_screen.qml
// ui/screens/GraphScreen.qml on its own: the model it hands the GraphView, the
// cursor it marks, the node click that opens a card through the navigator, the
// centreOn handle Panel drives, and the height it takes from the viewport.
// REAL core/stores App and REAL ui/Navigator.qml -- no bespoke mocks.
import QtQuick
import QtTest

TestCase {
  id: tc
  name: "GraphScreen"
  when: windowShown
  visible: true
  width: 600; height: 700

  Component { id: hostC; Item { width: 600; height: 700 } }
  Component { id: flickC; Flickable { width: 600; height: 300; contentWidth: 600; contentHeight: 2000 } }

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })

  function card(id, title, status, children) {
    return { id: id, title: title, status: status, description: "d", blocked_by: [], children: children || [] }
  }

  function make() {
    var host = createTemporaryObject(hostC, tc)
    var appC = Qt.createComponent("../../../core/stores/App.qml")
    if (appC.status !== Component.Ready) { fail(appC.errorString()); return null }
    var app = appC.createObject(host, { backendDir: "/plugin/core/backend/" })
    var navC = Qt.createComponent("../../../ui/Navigator.qml")
    if (navC.status !== Component.Ready) { fail(navC.errorString()); return null }
    var flick = flickC.createObject(host)
    var nav = navC.createObject(host, { app: app, flick: flick, actions: ({
      focusForView: function() {},
      scrollToTop: function() { flick.contentY = 0 },
      scrollBy: function(px) { flick.contentY = flick.contentY + px },
      centerOnGraphNode: function(id) {}
    }) })
    var sC = Qt.createComponent("../../../ui/screens/GraphScreen.qml")
    if (sC.status !== Component.Ready) { fail(sC.errorString()); return null }
    var s = sC.createObject(host, { app: app, navigator: nav, width: 600, viewportHeight: 500 })
    app.projects.stateLoaded = true
    app.projects.stateReadOk = true
    app.projects.applyProjectsList([pA])
    app.board.applyTreeData([
      card("m1", "First", "done", [card("s1", "Story", "done")]),
      card("m2", "Second", "todo")])
    return s
  }

  function find(item, name) {
    if (item.objectName === name) return item
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) { var r = find(kids[i], name); if (r) return r }
    var data = item.data || []
    for (var j = 0; j < data.length; j++) { var d = find(data[j], name); if (d) return d }
    return null
  }

  function test_the_graph_screen_shows_only_in_the_graph_view_with_a_project() {
    var s = make(); if (!s) return
    compare(s.visible, false)
    s.navigator.showSection("graph")
    compare(s.visible, true)
    s.app.projects.selectedProject = null
    compare(s.visible, false)
  }

  function test_the_graph_view_gets_the_nodes_and_edges_the_graph_store_derives() {
    var s = make(); if (!s) return
    s.navigator.showSection("graph")
    wait(100)
    var gv = find(s, "graphView")
    verify(gv, "the GraphView is inside the screen")
    compare(gv.nodes.length, s.app.graph.graph.nodes.length)
    compare(gv.nodes.length, 2)
    verify(find(s, "graphNodem1"), "a node per milestone")
    compare(find(find(s, "graphNodem1"), "graphNodeTitle").text, "First")
  }

  function test_the_graph_cursor_marks_the_current_node() {
    var s = make(); if (!s) return
    s.navigator.showSection("graph")
    wait(100)
    s.app.graph.graphCursor = "m2"
    wait(50)
    compare(find(s, "graphNodem2").current, true)
    compare(find(s, "graphNodem1").current, false)
  }

  function test_clicking_a_node_moves_the_cursor_and_opens_that_card() {
    var s = make(); if (!s) return
    s.navigator.showSection("graph")
    wait(100)
    find(s, "graphView").nodeClicked("m2")
    compare(s.app.graph.graphCursor, "m2")
    compare(s.app.nav.viewMode, "entry")
    compare(s.app.board.selectedCardId, "m2")
  }

  function test_the_screen_exposes_the_graph_view_so_the_panel_can_centre_on_a_node() {
    var s = make(); if (!s) return
    s.navigator.showSection("graph")
    wait(100)
    verify(s.graphView, "the screen exposes its GraphView")
    compare(s.graphView.objectName, "graphView")
    s.graphView.centerOn("m2")
  }

  function test_the_graph_fills_what_is_left_of_the_viewport_below_it() {
    var s = make(); if (!s) return
    s.navigator.showSection("graph")
    s.y = 40
    s.viewportHeight = 500
    wait(50)
    compare(s.height, 500 - 40 - 12)
    s.viewportHeight = 60
    wait(50)
    compare(s.height, 240, "never smaller than the floor")
    compare(find(s, "graphView").height, s.height)
  }

  function test_open_issues_from_the_board_mark_the_milestone_they_block() {
    var s = make(); if (!s) return
    s.navigator.showSection("graph")
    var m2 = card("m2", "Second", "todo")
    m2.blocked_by = ["i1", "i2"]
    s.app.board.applyTreeData([card("m1", "First", "done", [card("s1", "Story", "done")]), m2])
    s.app.board.issueProc.stdout.text = JSON.stringify({ ok: true, data: [
      { id: "i1", kind: "issue", title: "Broken build", status: "open" },
      { id: "i2", kind: "issue", title: "Old bug", status: "closed" }] })
    s.app.board.issueProc.stdout.streamFinished()
    wait(100)
    var marker = find(find(s, "graphNodem2"), "graphNodeIssues")
    compare(marker.visible, true)
    compare(marker.text, "\uF024 1 open issue")
    compare(find(find(s, "graphNodem1"), "graphNodeIssues").visible, false)
  }
}
