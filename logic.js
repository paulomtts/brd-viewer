.pragma library

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

// The word the user has to type before a project is removed; deliberately the
// same gate the Claude Memory plugin uses for its deletes.
function isDeleteConfirmed(text) {
  return String(text === undefined || text === null ? "" : text).trim().toLowerCase() === "delete"
}

// snapshot-and-forget.py's answer (its last stdout line, a JSON object) plus
// its exit code, as { ok, snapshot, error }. Anything that isn't a clear
// success counts as a failure: a delete is never assumed to have worked.
function parseDeleteResult(stdout, exitCode) {
  var generic = "Could not delete the project."
  var lines = String(stdout || "").split("\n").filter(function(l) { return l.trim() !== "" })
  var payload = null
  if (lines.length > 0) {
    try { payload = JSON.parse(lines[lines.length - 1]) } catch (e) { payload = null }
  }
  if (exitCode === 0 && payload && payload.ok === true)
    return { ok: true, snapshot: String(payload.snapshot || ""), error: "" }
  var message = payload && typeof payload.error === "string" && payload.error !== "" ? payload.error : generic
  return { ok: false, snapshot: "", error: message }
}

function filterProjects(projects, query) {
  return (projects || []).filter(function(p) { return matchesQuery(p.name, query) })
}

// Which project the panel should show: the one already on screen if it is
// still registered, else the one remembered from last time, else the first.
function chooseProject(projects, currentPath, storedPath) {
  var list = projects || []
  if (list.length === 0) return null
  function byPath(path) {
    if (!path) return null
    for (var i = 0; i < list.length; i++) if (list[i].root_path === path) return list[i]
    return null
  }
  return byPath(currentPath) || byPath(storedPath) || list[0]
}

// viewer-state.py get: its last stdout line is {"last_project": path|null}.
function parseStateResult(stdout, exitCode) {
  if (exitCode !== 0) return null
  var lines = String(stdout || "").split("\n").filter(function(l) { return l.trim() !== "" })
  if (lines.length === 0) return null
  try {
    var last = JSON.parse(lines[lines.length - 1]).last_project
    return typeof last === "string" && last !== "" ? last : null
  } catch (e) {
    return null
  }
}
