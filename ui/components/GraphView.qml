import QtQuick
import qs.Commons
import "../../vendor/canvas" as Local
import "../../core/domain/board.js" as Board
import "../../core/domain/graph.js" as Graph
import "../components" as UI
import "../theme" as T

// The Graph section: one node per milestone on a pan/zoom canvas. It renders
// and emits only; Panel.qml owns the model (Graph.graphModel) and the cursor.
Item {
  id: view
  objectName: "graphView"

  property var nodes: []
  property var edges: []
  property string cursorId: ""
  // The one input for every colour and font: Panel passes its Theme down,
  // and a standalone instance renders with the shell defaults.
  property var theme: T.Theme {}

  signal nodeClicked(string id)

  function centerOn(id) { canvas.centerOn(id) }
  function fitAll() { canvas.fitAll() }

  Local.Canvas {
    id: canvas
    objectName: "graphCanvas"
    anchors.fill: parent
    nodes: view.nodes
    edges: view.edges
    nodeDelegate: milestoneDelegate
    // Read-only board: the canvas may drag nodes around, but never draws a
    // dependency of its own.
    canConnect: function() { return false }
    onNodeClicked: function(id) { view.nodeClicked(id) }
    onWidthChanged: Qt.callLater(canvas.fitAll)
    Component.onCompleted: Qt.callLater(canvas.fitAll)
  }

  // Live refreshes replace the model every time the board changes; only a
  // different set of milestones (or showing the view again) reframes it, so a
  // pan/zoom survives an unrelated edit.
  readonly property string idKey: nodes.map(function(n) { return n.id }).join("|")
  onIdKeyChanged: Qt.callLater(canvas.fitAll)
  onVisibleChanged: if (visible) Qt.callLater(canvas.fitAll)

  Local.CanvasControls { canvas: canvas; showCulling: false }

  UI.ThemedText {
    objectName: "graphEmpty"
    variant: "dim"
    theme: view.theme
    anchors.centerIn: parent
    visible: view.nodes.length === 0
    text: "No milestones in this project."
  }

  Component {
    id: milestoneDelegate

    Rectangle {
      id: node
      // The canvas's Loader clears modelData while it tears a node down.
      readonly property var entry: modelData ? modelData : ({ id: "", title: "", status: "", done: 0, total: 0 })
      readonly property bool current: entry.id !== "" && view.cursorId === entry.id
      readonly property color tint: Board.statusColor(entry.status, view.theme.dim)
      objectName: "graphNode" + entry.id
      implicitWidth: Graph.GRAPH_NODE_W
      implicitHeight: Graph.GRAPH_NODE_H
      radius: 8
      color: Qt.alpha(view.theme.foreground, current ? 0.14 : 0.06)
      border.width: current ? 2 : 1
      border.color: current ? view.theme.foreground : Qt.alpha(view.theme.foreground, 0.25)

      Rectangle {
        width: 5
        height: parent.height - 2 * node.radius
        anchors.left: parent.left
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        radius: 2
        color: node.tint
      }

      Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 20
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        UI.ThemedText {
          objectName: "graphNodeTitle"
          theme: view.theme
          width: parent.width
          text: node.entry.title
          font.bold: true
          elide: Text.ElideRight
        }

        UI.ThemedText {
          objectName: "graphNodeProgress"
          variant: "caption"
          theme: view.theme
          width: parent.width
          text: node.entry.total > 0 ? node.entry.done + "/" + node.entry.total + " done" : "No stories"
        }
      }
    }
  }
}
