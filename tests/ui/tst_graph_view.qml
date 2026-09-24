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

  // ---- Story view: a node per story, pips instead of the progress text, and a
  // labelled box per milestone behind them.

  property var storyNodes: [
    { id: "s1", title: "First story", status: "in_progress", milestoneId: "m1", openIssues: 0,
      pips: [{ id: "t1", status: "done" }, { id: "t2", status: "in_progress" }], morePips: 2,
      x: 20, y: 40, w: 230, h: 78 },
    { id: "s2", title: "Second story", status: "blocked", milestoneId: "m2", openIssues: 1,
      pips: [], morePips: 0, x: 420, y: 40, w: 230, h: 78 }
  ]
  property var storyGroups: [
    { id: "m1", title: "Milestone one", x: 0, y: 0, w: 270, h: 140 },
    { id: "m2", title: "Milestone two", x: 400, y: 0, w: 270, h: 140 }
  ]

  function story() {
    var v = createTemporaryObject(viewC, tc)
    v.mode = "story"
    v.nodes = storyNodes
    v.edges = [{ id: "s1>s2", from: "s1", to: "s2" }]
    v.groups = storyGroups
    wait(100)
    return v
  }

  function test_a_story_node_shows_its_title_and_a_pip_per_subtask() {
    var v = story()
    var first = find(v, "graphNodes1")
    verify(first, "a node per story")
    compare(find(first, "graphNodeTitle").text, "First story")
    var pips = find(first, "graphNodePips")
    verify(pips, "the pips")
    compare(pips.model.length, 2)
    compare(pips.more, 2)
    compare(pips.visible, true)
    verify(!find(first, "graphNodeProgress"), "the done/total text gives way to the pips")
    compare(find(find(v, "graphNodes2"), "graphNodePips").visible, false, "a story with no subtasks shows no pips")
  }

  function test_a_story_blocked_by_open_issues_is_flagged_like_a_milestone() {
    var v = story()
    var marker = find(find(v, "graphNodes2"), "graphNodeIssues")
    compare(marker.visible, true)
    compare(marker.text, "\uF024 1 open issue")
    compare(find(find(v, "graphNodes1"), "graphNodeIssues").visible, false)
  }

  function test_every_group_draws_a_labelled_box_around_its_stories() {
    var v = story()
    var box = find(v, "graphGroupm1")
    verify(box, "a box per milestone")
    compare(box.x, 0)
    compare(box.y, 0)
    compare(box.width, 270)
    compare(box.height, 140)
    compare(find(v, "graphGroupLabelm1").text, "Milestone one")
    compare(find(v, "graphGroupLabelm2").text, "Milestone two")
    verify(find(v, "graphGroupLayer").z < 0, "the boxes sit behind the nodes")
  }

  function test_the_milestone_view_draws_no_boxes() {
    var v = createTemporaryObject(viewC, tc)
    v.nodes = nodes
    v.edges = edges
    v.groups = storyGroups
    wait(100)
    compare(find(v, "graphGroupLayer").visible, false)
    verify(find(v, "graphNodem1"), "and keeps the milestone nodes")
  }

  function test_the_boxes_follow_the_canvas_camera() {
    var v = story()
    var layer = find(v, "graphGroupLayer")
    var canvas = find(v, "graphCanvas")
    canvas.panX = 37
    canvas.panY = -12
    canvas.zoom = 2
    wait(50)
    compare(layer.x, 37)
    compare(layer.y, -12)
    compare(layer.scale, 2)
  }

  function test_hiding_the_graph_stops_the_pips_pulsing() {
    var v = story()
    var pips = find(find(v, "graphNodes1"), "graphNodePips")
    compare(pips.pulsing, true, "a subtask is in progress")
    v.visible = false
    wait(60)
    compare(pips.pulsing, false, "a graph nobody is looking at animates nothing")
    v.visible = true
    wait(60)
    compare(pips.pulsing, true)
  }

  function test_the_fit_frames_the_boxes_and_not_only_the_nodes() {
    // A wide, short viewport: the node alone would be framed at a zoom that
    // pushes the box's label strip off the top edge.
    var v = createTemporaryObject(viewC, tc, { width: 600, height: 200 })
    v.mode = "story"
    // One milestone, one story: the box is the node plus its padding and the
    // strip that carries the label, and all of it has to be on screen.
    v.nodes = [{ id: "s1", title: "Only", status: "todo", milestoneId: "m1", openIssues: 0,
                 pips: [], morePips: 0, x: 16, y: 30, w: 230, h: 78 }]
    v.groups = [{ id: "m1", title: "Milestone one", x: 0, y: 0, w: 262, h: 124 }]
    wait(200)
    var box = find(v, "graphGroupm1")
    var topLeft = box.mapToItem(v, 0, 0)
    var bottomRight = box.mapToItem(v, box.width, box.height)
    verify(topLeft.x >= 0 && topLeft.y >= 0,
           "the box's label strip and padding are framed (" + topLeft.x + "," + topLeft.y + ")")
    verify(bottomRight.x <= v.width && bottomRight.y <= v.height,
           "and so is its far corner (" + bottomRight.x + "," + bottomRight.y + ")")
  }

  function test_an_empty_story_graph_says_so() {
    var v = createTemporaryObject(viewC, tc)
    v.mode = "story"
    wait(50)
    compare(find(v, "graphEmpty").visible, true)
    compare(find(v, "graphEmpty").text, "No stories in this project.")
  }
}
