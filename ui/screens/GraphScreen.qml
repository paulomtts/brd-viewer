import QtQuick
import qs.Commons
import "../components" as UI
import "../theme" as T

// The Graph section: the shared GraphView, fed from the graph store. The
// wrapper exists so the panel can keep reaching the view (it centres the
// canvas on the keyboard cursor) without reaching into the screen's markup.
Item {
  id: graphScreen

  property var app
  property var navigator
  property var theme: T.Theme {}

  // The height of the panel's Flickable: the graph takes whatever is left of it
  // below its own y, exactly as the view did when it sat in the panel directly.
  property real viewportHeight: 0

  // Panel's `centerOnGraphNode` action drives the canvas through this.
  readonly property var graphView: view

  visible: graphScreen.app.nav.viewMode === "graph" && !!graphScreen.app.projects.selectedProject
  height: Math.max(Style.space(240), graphScreen.viewportHeight - graphScreen.y - Style.space(12))

  UI.GraphView {
    id: view
    anchors.fill: parent
    nodes: graphScreen.app.graph.currentNodes
    edges: graphScreen.app.graph.currentEdges
    groups: graphScreen.app.graph.currentGroups
    groupEdges: graphScreen.app.graph.currentGroupEdges
    mode: graphScreen.app.graph.graphView
    cursorId: graphScreen.app.graph.graphCursor
    theme: graphScreen.theme
    onNodeClicked: function(id) { graphScreen.app.graph.graphCursor = id; graphScreen.navigator.openCard(id) }
  }
}
