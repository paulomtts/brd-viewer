import QtQuick
import QtTest
import "../../ui/components"
TestCase {
  id: tc
  name: "GraphView"
  when: windowShown
  visible: true
  width: 600; height: 400

  Component { id: viewC; GraphView { width: 560; height: 360 } }
  property var nodes: [
    { id: "m1", title: "First", status: "done", done: 1, total: 2, x: 0, y: 0, w: 230, h: 78 },
    { id: "m2", title: "Second", status: "todo", done: 0, total: 0, x: 320, y: 0, w: 230, h: 78 }
  ]
  property var edges: [{ id: "m1>m2", from: "m1", to: "m2" }]

  function find(item, name) {
    if (item.objectName === name) return item
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) { var r = find(kids[i], name); if (r) return r }
    var data = item.data || []
    for (var j = 0; j < data.length; j++) { var d = find(data[j], name); if (d) return d }
    return null
  }

  function test_milestone_nodes_are_instantiated_with_title_and_progress() {
    var v = createTemporaryObject(viewC, tc)
    v.nodes = nodes
    v.edges = edges
    wait(100)
    var first = find(v, "graphNodem1")
    verify(first, "node m1 exists")
    verify(first.width > 0 && first.height > 0)
    compare(find(first, "graphNodeTitle").text, "First")
    compare(find(first, "graphNodeProgress").text, "1/2 done")
    compare(find(find(v, "graphNodem2"), "graphNodeProgress").text, "No stories")
  }

  function test_the_current_node_is_marked() {
    var v = createTemporaryObject(viewC, tc)
    v.nodes = nodes
    v.edges = edges
    v.cursorId = "m2"
    wait(100)
    compare(find(v, "graphNodem2").current, true)
    compare(find(v, "graphNodem1").current, false)
  }

  function test_an_empty_graph_says_so() {
    var v = createTemporaryObject(viewC, tc)
    compare(find(v, "graphEmpty").visible, true)
    v.nodes = nodes
    compare(find(v, "graphEmpty").visible, false)
  }

  function test_a_milestone_blocked_by_open_issues_shows_a_marker() {
    var v = createTemporaryObject(viewC, tc)
    var withIssues = nodes.map(function(n) { return Object.assign({}, n) })
    withIssues[0].openIssues = 2
    withIssues[1].openIssues = 0
    v.nodes = withIssues
    v.edges = edges
    wait(100)
    var marker = find(find(v, "graphNodem1"), "graphNodeIssues")
    verify(marker, "the open-issue marker")
    compare(marker.visible, true)
    compare(marker.text, "\uF024 2 open issues")
    compare(find(find(v, "graphNodem1"), "graphNodeProgress").text, "1/2 done")
    compare(find(find(v, "graphNodem2"), "graphNodeIssues").visible, false)
    v.nodes = nodes.map(function(n) { return Object.assign({}, n, { openIssues: n.id === "m1" ? 1 : 0 }) })
    wait(50)
    compare(find(find(v, "graphNodem1"), "graphNodeIssues").text, "\uF024 1 open issue")
  }
}
