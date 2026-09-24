import QtQml
import "../domain/graph.js" as Graph

// The milestone dependency graph and the keyboard selection that walks it.
// The model follows the board's card roots and issues, which App hands over. Centring the
// view on the selection needs an Item, so that stays in the UI.
QtObject {
  id: graphStore

  property var cardRoots: []   // set by App from BoardStore.cardRoots
  property var issueMap: ({})  // set by App from BoardStore.issueMap

  readonly property var graph: Graph.graphModel(graphStore.cardRoots, graphStore.issueMap)

  property string graphCursor: ""

  // Moves the selection and returns the newly selected id, or "" when there
  // was nothing to move to.
  function moveGraph(direction) {
    var next = Graph.graphMove(graphStore.graph.nodes, graphStore.graphCursor, direction)
    if (next === "") return ""
    graphStore.graphCursor = next
    return next
  }

  // The card the selection is on, or "" -- opening it is the screen's job.
  function activateGraphNode() {
    return graphStore.graphCursor
  }
}
