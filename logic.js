.pragma library

// Card shape, as returned by `brd tree`:
// {id, title, description, status, blocked_by, created_at, updated_at, children}
// indexTree() additionally injects `parentId` onto every card it visits.

// Walks the forest depth-first, pre-order. Mutates every card in place to
// add parentId (null for a root), and returns a flat id -> card lookup
// plus the visiting order (id + depth) so a Tree view can render without
// re-walking the structure itself.
function indexTree(roots) {
  var cardMap = {}
  var rows = []

  function visit(card, parentId, depth) {
    card.parentId = parentId
    cardMap[card.id] = card
    rows.push({ id: card.id, depth: depth })
    ;(card.children || []).forEach(function(child) {
      visit(child, card.id, depth + 1)
    })
  }

  ;(roots || []).forEach(function(root) { visit(root, null, 0) })
  return { cardMap: cardMap, rows: rows }
}

// Descendant-only progress: card's own status never counts, so a "done"
// parent with still-open children doesn't read as complete.
function subtreeCounts(card) {
  var done = 0
  var total = 0

  function visit(node) {
    ;(node.children || []).forEach(function(child) {
      total += 1
      if (child.status === "done") done += 1
      visit(child)
    })
  }

  visit(card)
  return { done: done, total: total }
}
