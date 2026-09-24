.pragma library

// A closed, ordered set of typed ids with a label and (optionally) a fixed
// colour each -- the document categories and the memory types are both one of
// these. Declaration order is display order everywhere.
//
// makeTaxonomy([{ id, label, color? }]) -> { ids, label, color, counts, filter, items }
function makeTaxonomy(items) {
  var list = items || []

  function entry(id) {
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
    return null
  }

  // "" for an id the set does not know.
  function label(id) {
    var found = entry(id)
    return found ? found.label : ""
  }

  // The caller's neutral colour for an unknown id, and for an entry that
  // declares none, so such a badge still follows the theme.
  function color(id, fallback) {
    var found = entry(id)
    return found && found.color !== undefined && found.color !== "" ? found.color : fallback
  }

  // [{ id, label, count }] in declaration order, leaving out the empty ones.
  function counts(rows, key) {
    var source = rows || []
    var out = []
    list.forEach(function(t) {
      var n = 0
      for (var i = 0; i < source.length; i++) if (source[i][key] === t.id) n++
      if (n > 0) out.push({ id: t.id, label: t.label, count: n })
    })
    return out
  }

  // An empty/undefined id means "all", so the list comes back unchanged.
  function filter(rows, key, id) {
    var source = rows || []
    if (!id) return source
    return source.filter(function(row) { return row[key] === id })
  }

  return {
    ids: list.map(function(t) { return t.id }),
    label: label,
    color: color,
    counts: counts,
    filter: filter,
    items: list
  }
}
