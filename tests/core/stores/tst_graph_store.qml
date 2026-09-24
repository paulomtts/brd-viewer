// tests/core/stores/tst_graph_store.qml
// The milestone dependency graph: its model, and the keyboard selection that
// walks it. Driven through App so the board -> graph wiring is exercised too.
import QtQuick
import QtTest

TestCase {
  id: tc
  name: "StoresGraphStore"

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
    var comp = Qt.createComponent("../../../core/stores/App.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var app = comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
    app.projects.applyStoredState('{"last_project": null}', 0)
    app.projects.applyProjectsList([pA, pB])
    app.board.applyTreeData(roots())
    app.graph.graphCursor = "m1"
    return app
  }

  function test_the_model_follows_the_board() {
    var app = make(); if (!app) return
    compare(app.graph.graph.nodes.length, 3, "one node per milestone")
    compare(app.graph.graph.edges.length, 2)
    app.board.applyTreeData([card("m1", "todo")])
    compare(app.graph.graph.nodes.length, 1)
    compare(app.graph.graph.edges.length, 0)
    app.board.applyTreeData([])
    compare(app.graph.graph.nodes.length, 0)
  }

  function test_arrow_keys_move_the_selection_along_the_dependency_chain() {
    var app = make(); if (!app) return
    compare(app.graph.moveGraph("right"), "m2")
    compare(app.graph.graphCursor, "m2")
    app.graph.moveGraph("right")
    compare(app.graph.graphCursor, "m3")
    app.graph.moveGraph("right")
    compare(app.graph.graphCursor, "m3")
    app.graph.moveGraph("left")
    compare(app.graph.graphCursor, "m2")
  }

  function test_an_unknown_selection_recovers_to_the_first_milestone() {
    var app = make(); if (!app) return
    app.graph.graphCursor = "gone"
    app.graph.moveGraph("right")
    compare(app.graph.graphCursor, "m1")
  }

  function test_moving_an_empty_graph_selects_nothing() {
    var app = make(); if (!app) return
    app.board.applyTreeData([])
    compare(app.graph.moveGraph("right"), "")
    compare(app.graph.graphCursor, "m1", "an empty graph leaves the selection alone")
  }

  function test_switching_project_clears_the_graph_selection() {
    var app = make(); if (!app) return
    app.graph.moveGraph("right")
    compare(app.graph.graphCursor, "m2")
    app.projects.selectProject(pB)
    compare(app.graph.graphCursor, "")
  }

  function test_activating_a_node_reports_the_selected_card() {
    var app = make(); if (!app) return
    app.graph.moveGraph("right")
    compare(app.graph.activateGraphNode(), "m2")
    app.graph.graphCursor = ""
    compare(app.graph.activateGraphNode(), "")
  }
}
