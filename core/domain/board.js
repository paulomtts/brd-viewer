.pragma library
.import "text.js" as Text

// Card shape, as returned by `brd tree`:
// {id, title, description, status, blocked_by, created_at, updated_at, children}
// indexTree() additionally injects `parentId` and `depth` onto every card it visits.

// Walks the forest depth-first, pre-order. Mutates every card in place to
// add parentId (null for a root) and depth (0 for a root), and returns a flat
// id -> card lookup covering every card in the forest.
function indexTree(roots) {
  var cardMap = {}

  function visit(card, parentId, depth) {
    card.parentId = parentId
    card.depth = depth
    cardMap[card.id] = card
    ;(card.children || []).forEach(function(child) {
      visit(child, card.id, depth + 1)
    })
  }

  ;(roots || []).forEach(function(root) { visit(root, null, 0) })
  return { cardMap: cardMap }
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

// True if `card` itself matches, or any descendant does -- so an ancestor
// of a match stays visible even though it doesn't match on its own title.
function subtreeMatches(card, query) {
  if (!card) return false
  if (Text.matchesQuery(card.title, query)) return true
  return (card.children || []).some(function(child) { return subtreeMatches(child, query) })
}

// The shell theme has no green/orange tokens, so these hues are fixed; todo
// (and anything unrecognised) takes the caller's neutral colour so it still
// follows the theme.
function statusColor(status, fallback) {
  if (status === "done") return "#7fb069"
  if (status === "blocked") return "#e8954a"
  if (status === "in_progress") return "#5fa8d3"
  return fallback
}

// Depth in the brd hierarchy: milestone > story > subtask.
function kindLabel(depth) {
  if (typeof depth !== "number" || depth < 0) return "Card"
  if (depth === 0) return "Milestone"
  if (depth === 1) return "Story"
  return "Subtask"
}

// brd derives "blocked" on top of a stored "todo"; the Board has no blocked
// section, so such a card lives in Todo.
function effectiveStatus(card) {
  if (!card || card.status === "blocked") return "todo"
  return card.status
}

// Top-level cards in the order the Board shows them: section by section.
function boardOrder(roots, statuses) {
  var out = []
  statuses.forEach(function(status) {
    ;(roots || []).forEach(function(card) {
      if (effectiveStatus(card) === status) out.push(card)
    })
  })
  return out
}

// The clickable rows of a card's detail view, in display order. Dangling
// blockers (not in cardMap) are not navigable, so they are not listed.
function detailLinks(card, cardMap) {
  if (!card) return []
  var links = []
  if (card.parentId && cardMap[card.parentId]) links.push({ section: "parent", id: card.parentId })
  ;(card.blocked_by || []).forEach(function(id) {
    if (cardMap[id]) links.push({ section: "blocker", id: id })
  })
  ;(card.children || []).forEach(function(child) {
    links.push({ section: "child", id: child.id })
  })
  return links
}
