// tests/core/domain/tst_graph.qml
import QtQuick
import QtTest
import "../../../core/domain/graph.js" as Graph

TestCase {
  name: "DomainGraph"

  function makeCard(id, status, children, blockedBy) {
    return {
      id: id, title: id, description: "", status: status,
      blocked_by: blockedBy || [], created_at: "", updated_at: "",
      children: children || []
    }
  }

  function graphRoots() {
    return [
      makeCard("m1", "done", [makeCard("s1", "done", []), makeCard("s2", "todo", [])]),
      makeCard("m2", "todo", [makeCard("s3", "todo", [])], ["m1"]),
      makeCard("m3", "blocked", [], ["m2", "ghost"]),
      makeCard("m4", "in_progress", [])
    ]
  }

  function test_graph_model_has_a_node_per_milestone_with_progress() {
    var g = Graph.graphModel(graphRoots())
    compare(g.nodes.map(function(n) { return n.id }).join(","), "m1,m2,m3,m4")
    compare(g.nodes[0].title, "m1")
    compare(g.nodes[0].status, "done")
    compare(g.nodes[0].done, 1)
    compare(g.nodes[0].total, 2)
    compare(g.nodes[2].status, "blocked")
    compare(g.nodes[3].total, 0)
  }

  function test_graph_edges_run_from_blocker_to_blocked_and_skip_unknown_ids() {
    var g = Graph.graphModel(graphRoots())
    compare(g.edges.map(function(e) { return e.from + ">" + e.to }).join(","), "m1>m2,m2>m3")
    compare(g.edges[0].id, "m1>m2")
  }

  function test_graph_nodes_are_positioned_and_sized_by_the_layout() {
    var g = Graph.graphModel(graphRoots())
    for (var i = 0; i < g.nodes.length; i++) {
      verify(isFinite(g.nodes[i].x) && isFinite(g.nodes[i].y), "node " + i)
      compare(g.nodes[i].w, Graph.GRAPH_NODE_W)
      compare(g.nodes[i].h, Graph.GRAPH_NODE_H)
    }
    verify(g.nodes[1].x > g.nodes[0].x, "blocked milestone sits to the right of its blocker")
    verify(g.nodes[2].x > g.nodes[1].x)
  }

  function test_graph_model_of_nothing_is_empty() {
    compare(Graph.graphModel([]).nodes.length, 0)
    compare(Graph.graphModel(undefined).edges.length, 0)
  }

  function test_graph_move_picks_the_nearest_node_in_the_direction() {
    var nodes = [
      { id: "a", x: 0, y: 0, w: 100, h: 50 },
      { id: "b", x: 300, y: 0, w: 100, h: 50 },
      { id: "c", x: 300, y: 200, w: 100, h: 50 },
      { id: "d", x: 600, y: 10, w: 100, h: 50 }
    ]
    compare(Graph.graphMove(nodes, "a", "right"), "b")
    compare(Graph.graphMove(nodes, "b", "right"), "d")
    compare(Graph.graphMove(nodes, "b", "left"), "a")
    compare(Graph.graphMove(nodes, "b", "down"), "c")
    compare(Graph.graphMove(nodes, "c", "up"), "b")
    compare(Graph.graphMove(nodes, "a", "left"), "a")
    compare(Graph.graphMove(nodes, "d", "down"), "c")
  }

  function test_graph_move_starts_at_the_first_node_when_nothing_is_selected() {
    var nodes = [{ id: "a", x: 0, y: 0 }, { id: "b", x: 300, y: 0 }]
    compare(Graph.graphMove(nodes, "", "right"), "a")
    compare(Graph.graphMove(nodes, "gone", "left"), "a")
    compare(Graph.graphMove([], "", "right"), "")
  }

  function test_open_issue_count_counts_only_open_issue_blockers() {
    var issues = { i1: { id: "i1", title: "A", status: "open" },
                   i2: { id: "i2", title: "B", status: "closed" },
                   i3: { id: "i3", title: "C", status: "open" } }
    compare(Graph.openIssueCount(makeCard("m", "todo", [], ["i1", "i2", "i3", "m9", "ghost"]), issues), 2)
    compare(Graph.openIssueCount(makeCard("m", "todo", [], ["i2"]), issues), 0, "a closed issue adds nothing")
    compare(Graph.openIssueCount(makeCard("m", "todo", [], ["i1", "i1"]), issues), 1, "an id counts once")
    compare(Graph.openIssueCount(makeCard("m", "todo", []), issues), 0)
    compare(Graph.openIssueCount(makeCard("m", "todo", [], ["i1"]), undefined), 0)
    compare(Graph.openIssueCount(undefined, issues), 0)
  }

  function test_open_issue_label_says_how_many_open_issues_block_a_milestone() {
    compare(Graph.openIssueLabel(0), "")
    compare(Graph.openIssueLabel(1), "1 open issue")
    compare(Graph.openIssueLabel(2), "2 open issues")
  }

  function test_graph_nodes_carry_their_open_issue_count_and_issues_draw_no_edges() {
    var issues = { i1: { id: "i1", title: "A", status: "open" },
                   i2: { id: "i2", title: "B", status: "closed" } }
    var roots = graphRoots()
    roots[2].blocked_by = ["m2", "ghost", "i1", "i2"]
    var g = Graph.graphModel(roots, issues)
    compare(g.nodes.map(function(n) { return n.openIssues }).join(","), "0,0,1,0")
    compare(g.edges.map(function(e) { return e.from + ">" + e.to }).join(","), "m1>m2,m2>m3")
    compare(Graph.graphModel(graphRoots()).nodes[0].openIssues, 0, "no issue map: nothing open")
  }

  function test_open_issues_mark_only_a_milestone_brd_reports_as_blocked() {
    var issues = { i1: { id: "i1", title: "A", status: "open" } }
    var roots = [makeCard("m1", "in_progress", [], ["i1"]), makeCard("m2", "done", [], ["i1"]),
                 makeCard("m3", "todo", [], ["i1"]), makeCard("m4", "blocked", [], ["i1"])]
    var g = Graph.graphModel(roots, issues)
    compare(g.nodes.map(function(n) { return n.openIssues }).join(","), "0,0,0,1")
  }
}
