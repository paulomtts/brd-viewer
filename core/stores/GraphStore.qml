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

  // The second view: every milestone's stories at once, boxed per milestone.
  readonly property var storyGraph: Graph.storyGraphModel(graphStore.cardRoots, graphStore.issueMap)

  // Which of the two the section is showing. Remembered for the session --
  // nothing resets it, a project switch included -- and never empty: one of the
  // two chips is always the active one.
  property string graphView: "milestone"

  readonly property var currentNodes: graphStore.graphView === "story" ? graphStore.storyGraph.nodes : graphStore.graph.nodes
  readonly property var currentEdges: graphStore.graphView === "story" ? graphStore.storyGraph.edges : graphStore.graph.edges
  // Only the story view groups its nodes; the milestone view has no boxes.
  readonly property var currentGroups: graphStore.graphView === "story" ? graphStore.storyGraph.groups : []

  property string graphCursor: ""

  // Switches view. An unknown name is refused, so the two chips can never end
  // up with neither active. A selection the new view does not have moves to its
  // first node, because the arrow keys and Enter walk THAT model now.
  function setGraphView(name) {
    if (name !== "milestone" && name !== "story") return
    graphStore.graphView = name
    var nodes = graphStore.currentNodes
    var found = false
    nodes.forEach(function(node) { if (node.id === graphStore.graphCursor) found = true })
    if (!found) graphStore.graphCursor = nodes.length > 0 ? nodes[0].id : ""
  }

  // Moves the selection and returns the newly selected id, or "" when there
  // was nothing to move to.
  function moveGraph(direction) {
    var next = Graph.graphMove(graphStore.currentNodes, graphStore.graphCursor, direction)
    if (next === "") return ""
    graphStore.graphCursor = next
    return next
  }

  // The card the selection is on, or "" -- opening it is the screen's job.
  function activateGraphNode() {
    return graphStore.graphCursor
  }
}
