import QtQuick
import QtTest
TestCase {
  id: tc
  name: "GraphFlow"
  when: windowShown
  width: 400; height: 700
  Component { id: hostC; Item { width: 400; height: 700 } }

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })
  property var pB: ({ root_path: "/home/u/b", name: "beta" })

  function card(id, status, children, blockedBy) {
    return { id: id, title: "T " + id, description: "", status: status, blocked_by: blockedBy || [],
             created_at: "", updated_at: "", children: children || [] }
  }
  function roots() {
    return [card("m1", "done", [card("s1", "done")]), card("m2", "todo", [], ["m1"]), card("m3", "todo", [], ["m2"])]
  }
  function make() {
    var host = createTemporaryObject(hostC, tc)
    var comp = Qt.createComponent("../../Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var p = comp.createObject(host)
    p.opened = true
    p.stateLoaded = true
    p.applyProjectsList([pA, pB])
    p.applyTreeData(roots())
    return p
  }
  function named(p, name) {
    for (var i = 0; i < p.data.length; i++) if (p.data[i] && p.data[i].objectName === name) return p.data[i]
    return null
  }
  function find(item, name) {
    if (item.objectName === name) return item
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) { var r = find(kids[i], name); if (r) return r }
    return null
  }

  function test_the_graph_section_shows_and_selects_the_first_milestone() {
    var p = make(); if (!p) return
    p.showSection("graph")
    compare(p.viewMode, "graph")
    compare(p.section, "graph")
    compare(p.sectionTitle, "Graph")
    compare(p.graphCursor, "m1")
    compare(p.graph.nodes.length, 3)
  }

  function test_ctrl_3_shows_the_graph() {
    var p = make(); if (!p) return
    var event = { key: Qt.Key_3, modifiers: Qt.ControlModifier, accepted: false }
    compare(p.handleGlobalKey(event), true)
    compare(p.viewMode, "graph")
  }

  function test_arrow_keys_move_the_selection_along_the_dependency_chain() {
    var p = make(); if (!p) return
    p.showSection("graph")
    p.moveGraph("right")
    compare(p.graphCursor, "m2")
    p.moveGraph("right")
    compare(p.graphCursor, "m3")
    p.moveGraph("right")
    compare(p.graphCursor, "m3")
    p.moveGraph("left")
    compare(p.graphCursor, "m2")
  }

  function test_key_catcher_moves_and_activates_in_the_graph() {
    var p = make(); if (!p) return
    p.showSection("graph")
    var kc = p.focusItem
    compare(kc.objectName, "keyCatcher")
    kc.moveRequested(1, 0)
    compare(p.graphCursor, "m2")
    kc.moveRequested(-1, 0)
    compare(p.graphCursor, "m1")
    kc.activateRequested()
    compare(p.viewMode, "entry")
    compare(p.selectedCardId, "m1")
    compare(p.section, "graph")
  }

  function test_back_from_a_card_returns_to_the_graph_with_the_selection() {
    var p = make(); if (!p) return
    p.showSection("graph")
    p.moveGraph("right")
    p.activateGraphNode()
    compare(p.viewMode, "entry")
    p.goBack()
    compare(p.viewMode, "graph")
    compare(p.graphCursor, "m2")
  }

  function test_back_from_a_board_card_still_returns_to_the_board() {
    var p = make(); if (!p) return
    p.openCard("m2")
    p.goBack()
    compare(p.viewMode, "board")
  }

  function test_the_graph_view_receives_the_model_and_clicks_open_the_card() {
    var p = make(); if (!p) return
    p.showSection("graph")
    var gv = find(p, "graphView")
    verify(gv, "graphView")
    compare(gv.nodes.length, 3)
    compare(gv.edges.length, 2)
    gv.nodeClicked("m2")
    compare(p.graphCursor, "m2")
    compare(p.viewMode, "entry")
    compare(p.selectedCardId, "m2")
  }

  function test_switching_project_clears_the_graph_selection() {
    var p = make(); if (!p) return
    p.showSection("graph")
    p.moveGraph("right")
    p.selectProject(pB)
    compare(p.graphCursor, "")
  }

  function test_an_unknown_selection_recovers_to_the_first_milestone() {
    var p = make(); if (!p) return
    p.showSection("graph")
    p.graphCursor = "gone"
    p.moveGraph("right")
    compare(p.graphCursor, "m1")
  }

  function test_the_popup_is_at_least_eighty_percent_of_the_screen_tall() {
    var p = make(); if (!p) return
    var panel = named(p, "mainPanel")
    verify(panel, "mainPanel")
    verify(panel.contentHeight >= 0.8 * panel.screenH, "height " + panel.contentHeight)
  }

  function test_the_popup_is_about_eighty_percent_of_the_screen_wide() {
    var p = make(); if (!p) return
    var panel = named(p, "mainPanel")
    verify(panel.contentWidth >= 0.8 * panel.screenW - 1, "width " + panel.contentWidth)
  }
}
