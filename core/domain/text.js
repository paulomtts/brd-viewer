.pragma library

// The one search predicate every section's filter is built from: a trimmed,
// case-insensitive substring test where an empty query matches everything.
function matchesQuery(text, query) {
  var q = String(query || "").trim().toLowerCase()
  return q === "" || String(text || "").toLowerCase().indexOf(q) >= 0
}
