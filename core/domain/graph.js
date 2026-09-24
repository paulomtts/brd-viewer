.pragma library
.import "board.js" as Board
.import "../../vendor/canvas/layout.js" as Layout

var GRAPH_NODE_W = 230
var GRAPH_NODE_H = 78

// Kept as graph.js's own name for the graph model; the counting itself lives
// in board.js, which the card badge uses too -- one implementation, one test.
function openIssueCount(card, issueMap) {
  return Board.openIssueCount(card, issueMap)
}

function openIssueLabel(count) {
  if (!count) return ""
  return count + (count === 1 ? " open issue" : " open issues")
}

// One node per milestone (top-level card), one edge per blocked_by link between
// two milestones (blocker -> blocked; links to sub-cards, issues or unknown ids
// are not milestone dependencies and are skipped). Each node also carries how
// many open issues block it -- only when brd reports it blocked, since the
// count is there to explain that status. Positions come from the canvas's own layered
// layout so the panel can navigate by geometry.
function graphModel(roots, issueMap) {
  var cards = roots || []
  var known = {}
  cards.forEach(function(card) { known[card.id] = true })

  var nodes = cards.map(function(card) {
    var counts = Board.subtreeCounts(card)
    return { id: card.id, title: card.title, status: card.status,
             done: counts.done, total: counts.total,
             openIssues: card.status === "blocked" ? openIssueCount(card, issueMap) : 0,
             w: GRAPH_NODE_W, h: GRAPH_NODE_H }
  })
  var edges = []
  cards.forEach(function(card) {
    ;(card.blocked_by || []).forEach(function(blocker) {
      if (known[blocker] && blocker !== card.id) edges.push({ id: blocker + ">" + card.id, from: blocker, to: card.id })
    })
  })

  var placed = nodes.length > 0 ? Layout.layout(nodes, edges) : {}
  nodes.forEach(function(node) {
    var at = placed[node.id]
    node.x = at ? at.x : 0
    node.y = at ? at.y : 0
  })
  return { nodes: nodes, edges: edges }
}

// ---- Story view -----------------------------------------------------------
// One node per STORY (a milestone's direct child), every milestone's stories at
// once, each milestone's stories boxed together. Same node size as a milestone
// node; the done/total text is dropped in favour of one pip per subtask.
var STORY_NODE_W = 230
var STORY_NODE_H = 78
// How many pips a node shows before the rest collapse into a "+N". Six fit
// across the node beside the "+N" at the sizes above.
var STORY_PIP_CAP = 6
// The padding a group box keeps around its stories, and the strip at the top
// that carries the milestone title.
var GROUP_PAD = 16
var GROUP_HEADER = 30

// The status a subtask's pip is coloured by: the card's own, except that a card
// an OPEN issue blocks reads as blocked (brd already derives that status, and
// this holds even when a board was read before its issues were).
function pipStatus(card, issueMap) {
  if (!card) return "todo"
  if (card.status === "blocked" || openIssueCount(card, issueMap) > 0) return "blocked"
  return card.status
}

// A story's pips: one per direct child, capped. Over the cap, one slot is given
// to the "+N" so the node never grows -- morePips then counts everything the
// visible pips leave out.
function storyPips(story, issueMap) {
  var children = (story && story.children) || []
  var shown = children.length > STORY_PIP_CAP ? STORY_PIP_CAP - 1 : children.length
  var pips = []
  for (var i = 0; i < shown; i++)
    pips.push({ id: children[i].id, status: pipStatus(children[i], issueMap) })
  return { pips: pips, morePips: children.length - shown }
}

// The story graph: {nodes, edges, groups}. `nodes` are the stories of every
// milestone in board order, `edges` their story-to-story blocked_by links
// (a blocker in another milestone simply draws across two boxes), and `groups`
// one labelled box per milestone that HAS stories, enclosing exactly its own.
// Positions come from the canvas layout twice: once inside each box, once over
// the boxes themselves, so no two boxes overlap.
function storyGraphModel(roots, issueMap) {
  var milestones = roots || []
  var nodes = []
  var cards = []
  var groups = []
  var groupOf = {}

  milestones.forEach(function(milestone) {
    var stories = milestone.children || []
    if (stories.length === 0) return
    var group = { id: milestone.id, title: milestone.title, stories: [], x: 0, y: 0, w: 0, h: 0 }
    stories.forEach(function(story) {
      var pips = storyPips(story, issueMap)
      var node = { id: story.id, title: story.title, status: story.status,
                   milestoneId: milestone.id,
                   openIssues: story.status === "blocked" ? openIssueCount(story, issueMap) : 0,
                   pips: pips.pips, morePips: pips.morePips,
                   w: STORY_NODE_W, h: STORY_NODE_H }
      groupOf[story.id] = milestone.id
      group.stories.push(node)
      nodes.push(node)
      cards.push(story)
    })
    groups.push(group)
  })

  // Story links only: a blocker that is a milestone, a subtask, an issue or an
  // unknown id is not a story dependency.
  var edges = []
  cards.forEach(function(card) {
    ;(card.blocked_by || []).forEach(function(blocker) {
      if (groupOf[blocker] && blocker !== card.id)
        edges.push({ id: blocker + ">" + card.id, from: blocker, to: card.id })
    })
  })

  // Inside every box: the stories of that milestone, laid out by the links that
  // stay inside it. The box is the bounding box of the result, padded, with a
  // strip at the top for the label.
  var offsets = {}
  groups.forEach(function(group) {
    var inner = edges.filter(function(edge) {
      return groupOf[edge.from] === group.id && groupOf[edge.to] === group.id
    })
    var placed = Layout.layout(group.stories, inner,
                               { rankGap: 60, nodeGap: 24,
                                 defaultWidth: STORY_NODE_W, defaultHeight: STORY_NODE_H })
    var minX = 0, minY = 0, maxX = 0, maxY = 0
    group.stories.forEach(function(node, index) {
      var at = placed[node.id] || { x: 0, y: 0 }
      if (index === 0) { minX = at.x; minY = at.y; maxX = at.x + node.w; maxY = at.y + node.h }
      minX = Math.min(minX, at.x); minY = Math.min(minY, at.y)
      maxX = Math.max(maxX, at.x + node.w); maxY = Math.max(maxY, at.y + node.h)
      offsets[node.id] = at
    })
    group.stories.forEach(function(node) {
      offsets[node.id] = { x: offsets[node.id].x - minX + GROUP_PAD,
                           y: offsets[node.id].y - minY + GROUP_HEADER }
    })
    group.w = (maxX - minX) + 2 * GROUP_PAD
    group.h = (maxY - minY) + GROUP_HEADER + GROUP_PAD
  })

  // Between the boxes: a link whose ends live in two different milestones ranks
  // those milestones, once per pair.
  var groupEdges = []
  var seenGroupEdge = {}
  edges.forEach(function(edge) {
    var from = groupOf[edge.from]
    var to = groupOf[edge.to]
    if (from === to) return
    var key = from + ">" + to
    if (seenGroupEdge[key]) return
    seenGroupEdge[key] = true
    groupEdges.push({ id: key, from: from, to: to })
  })

  var placedGroups = groups.length > 0
    ? Layout.layout(groups.map(function(group) { return { id: group.id, w: group.w, h: group.h } }),
                    groupEdges, { rankGap: 100, nodeGap: 60 })
    : {}
  groups.forEach(function(group) {
    var at = placedGroups[group.id] || { x: 0, y: 0 }
    group.x = at.x
    group.y = at.y
    group.stories.forEach(function(node) {
      node.x = group.x + offsets[node.id].x
      node.y = group.y + offsets[node.id].y
    })
    delete group.stories
  })

  return { nodes: nodes, edges: edges, groups: groups }
}

// Keyboard selection on the graph: the nearest node whose centre lies in the
// given direction ("left"|"right"|"up"|"down"), preferring nodes in line with
// the current one. Nothing selected (or an unknown id) picks the first node.
function graphMove(nodes, currentId, direction) {
  var list = nodes || []
  if (list.length === 0) return ""
  var current = null
  list.forEach(function(n) { if (n.id === currentId) current = n })
  if (!current) return list[0].id

  function cx(n) { return n.x + (n.w || 0) / 2 }
  function cy(n) { return n.y + (n.h || 0) / 2 }
  var best = null
  var bestScore = Infinity
  list.forEach(function(n) {
    if (n === current) return
    var dx = cx(n) - cx(current)
    var dy = cy(n) - cy(current)
    var along = direction === "right" ? dx : direction === "left" ? -dx : direction === "down" ? dy : -dy
    var across = (direction === "left" || direction === "right") ? dy : dx
    if (along <= 0) return
    var score = along + 2 * Math.abs(across)
    if (score < bestScore) { bestScore = score; best = n }
  })
  return best ? best.id : current.id
}
