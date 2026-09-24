.pragma library
.import "board.js" as Board
.import "../../vendor/canvas/layout.js" as Layout

var GRAPH_NODE_W = 230
var GRAPH_NODE_H = 78

// One node per milestone (top-level card), one edge per blocked_by link between
// two milestones (blocker -> blocked; links to sub-cards or unknown ids are not
// milestone dependencies and are skipped). Positions come from the canvas's
// own layered layout so the panel can navigate by geometry.
function graphModel(roots) {
  var cards = roots || []
  var known = {}
  cards.forEach(function(card) { known[card.id] = true })

  var nodes = cards.map(function(card) {
    var counts = Board.subtreeCounts(card)
    return { id: card.id, title: card.title, status: card.status,
             done: counts.done, total: counts.total,
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
