.pragma library

// Depth-first search for an item by objectName through visual children, data
// and Flickable content. Returns null when absent.
function find(item, name) {
  if (!item) return null
  if (item.objectName === name) return item
  var lists = [item.children, item.data, item.contentItem ? [item.contentItem] : null]
  for (var l = 0; l < lists.length; l++) {
    var kids = lists[l] || []
    for (var i = 0; i < kids.length; i++) {
      var found = find(kids[i], name)
      if (found) return found
    }
  }
  return null
}
