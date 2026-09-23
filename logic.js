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

function matchesQuery(text, query) {
  var q = String(query || "").trim().toLowerCase()
  return q === "" || String(text || "").toLowerCase().indexOf(q) >= 0
}

// True if `card` itself matches, or any descendant does -- so an ancestor
// of a match stays visible even though it doesn't match on its own title.
function subtreeMatches(card, query) {
  if (!card) return false
  if (matchesQuery(card.title, query)) return true
  return (card.children || []).some(function(child) { return subtreeMatches(child, query) })
}

// A missing blocker (id not in cardMap -- e.g. deleted without --cascade
// cleaning up the reference) is treated as still-blocking: its completion
// can't be verified, so it's conservatively not "done".
function isBlocked(card, cardMap) {
  if (!card) return false
  return (card.blocked_by || []).some(function(id) {
    var blocker = cardMap[id]
    return !blocker || blocker.status !== "done"
  })
}
