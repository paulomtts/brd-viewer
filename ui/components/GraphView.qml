import QtQuick
import qs.Commons
import "../../vendor/canvas" as Local
import "../../core/domain/board.js" as Board
import "../../core/domain/graph.js" as Graph
import "../components" as UI
import "../theme" as T

// The Graph section on a pan/zoom canvas, in either of its two views: one node
// per milestone, or one per story with a labelled box around each milestone's
// own. It renders and emits only; the store owns the model and the cursor.
Item {
  id: view
  objectName: "graphView"

  property var nodes: []
  property var edges: []
  // "milestone" or "story": which delegate the nodes take, and whether the
  // boxes below are drawn at all.
  property string mode: "milestone"
  // [{ id, title, x, y, w, h }] -- the story view's milestone boxes, in world
  // coordinates, empty in the milestone view.
  property var groups: []
  property string cursorId: ""
  // The one input for every colour and font: Panel passes its Theme down,
  // and a standalone instance renders with the shell defaults.
  property var theme: T.Theme {}

  signal nodeClicked(string id)

  function centerOn(id) { canvas.centerOn(id) }

  // Frame the whole graph. The canvas only knows its nodes, so in the story
  // view the boxes -- which reach past their stories by their padding and their
  // label strip -- are added here and the union is what gets framed.
  function fitAll() {
    var rect = view.contentBounds()
    if (rect === null) { canvas.fitAll(); return }
    canvas.fitBounds(rect)
  }

  // The union of every node and every box, in world coordinates, or null when
  // there is nothing (or nothing measurable) to frame.
  function contentBounds() {
    var boxes = (view.mode === "story" ? view.groups : []) || []
    if (boxes.length === 0) return null
    var rect = null
    function add(item) {
      if (!item || !isFinite(item.x) || !isFinite(item.y) || !(item.w > 0) || !(item.h > 0)) return
      if (rect === null) { rect = { x: item.x, y: item.y, w: item.w, h: item.h }; return }
      var right = Math.max(rect.x + rect.w, item.x + item.w)
      var bottom = Math.max(rect.y + rect.h, item.y + item.h)
      rect.x = Math.min(rect.x, item.x)
      rect.y = Math.min(rect.y, item.y)
      rect.w = right - rect.x
      rect.h = bottom - rect.y
    }
    boxes.forEach(add)
    ;(view.nodes || []).forEach(add)
    return rect
  }

  Local.Canvas {
    id: canvas
    objectName: "graphCanvas"
    anchors.fill: parent
    nodes: view.nodes
    edges: view.edges
    nodeDelegate: view.mode === "story" ? storyDelegate : milestoneDelegate
    // Read-only board: the canvas may drag nodes around, but never draws a
    // dependency of its own.
    canConnect: function() { return false }
    onNodeClicked: function(id) { view.nodeClicked(id) }
    onWidthChanged: Qt.callLater(view.fitAll)
    Component.onCompleted: Qt.callLater(view.fitAll)

    // The story view's milestone boxes. The canvas draws nodes and edges only,
    // so this layer sits inside it, applies the very same camera, and is pushed
    // behind the canvas's own world item -- the boxes must never cover a node.
    Item {
      objectName: "graphGroupLayer"
      z: -1
      visible: view.mode === "story"
      x: canvas.panX
      y: canvas.panY
      scale: canvas.zoom
      transformOrigin: Item.TopLeft

      Repeater {
        model: view.groups

        delegate: Rectangle {
          id: box
          required property var modelData

          objectName: "graphGroup" + (box.modelData ? box.modelData.id : "")
          x: box.modelData ? box.modelData.x : 0
          y: box.modelData ? box.modelData.y : 0
          width: box.modelData ? box.modelData.w : 0
          height: box.modelData ? box.modelData.h : 0
          radius: 12
          color: Qt.alpha(view.theme.foreground, 0.04)
          border.width: 1
          border.color: Qt.alpha(view.theme.foreground, 0.18)

          UI.ThemedText {
            objectName: "graphGroupLabel" + (box.modelData ? box.modelData.id : "")
            variant: "caption"
            theme: view.theme
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.leftMargin: 10
            anchors.topMargin: 6
            anchors.right: parent.right
            anchors.rightMargin: 10
            text: box.modelData ? box.modelData.title : ""
            font.bold: true
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  // Live refreshes replace the model every time the board changes; only a
  // different set of milestones (or showing the view again) reframes it, so a
  // pan/zoom survives an unrelated edit.
  readonly property string idKey: nodes.map(function(n) { return n.id }).join("|")
  onIdKeyChanged: Qt.callLater(view.fitAll)
  onVisibleChanged: if (visible) Qt.callLater(view.fitAll)

  Local.CanvasControls { canvas: canvas; showCulling: false }

  UI.ThemedText {
    objectName: "graphEmpty"
    variant: "dim"
    theme: view.theme
    anchors.centerIn: parent
    visible: view.nodes.length === 0
    text: view.mode === "story" ? "No stories in this project." : "No milestones in this project."
  }

  Component {
    id: milestoneDelegate

    Rectangle {
      id: node
      // The canvas's Loader clears modelData while it tears a node down.
      readonly property var entry: modelData ? modelData : ({ id: "", title: "", status: "", done: 0, total: 0, openIssues: 0 })
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

        Item {
          width: parent.width
          height: progress.implicitHeight

          UI.ThemedText {
            id: progress
            objectName: "graphNodeProgress"
            variant: "caption"
            theme: view.theme
            anchors.left: parent.left
            anchors.right: issues.visible ? issues.left : parent.right
            anchors.rightMargin: issues.visible ? 6 : 0
            text: node.entry.total > 0 ? node.entry.done + "/" + node.entry.total + " done" : "No stories"
            elide: Text.ElideRight
          }

          // Open issues blocking this milestone; closed ones add nothing.
          UI.ThemedText {
            id: issues
            objectName: "graphNodeIssues"
            variant: "caption"
            theme: view.theme
            anchors.right: parent.right
            visible: (node.entry.openIssues || 0) > 0
            text: "\uF024 " + Graph.openIssueLabel(node.entry.openIssues || 0)
            color: Board.statusColor("blocked", view.theme.dim)
          }
        }
      }
    }
  }

  // A story node: the same frame, status stripe and open-issue flag as a
  // milestone, with one pip per subtask where the milestone shows done/total.
  Component {
    id: storyDelegate

    Rectangle {
      id: storyNode
      readonly property var entry: modelData ? modelData
        : ({ id: "", title: "", status: "", openIssues: 0, pips: [], morePips: 0 })
      readonly property bool current: entry.id !== "" && view.cursorId === entry.id
      readonly property color tint: Board.statusColor(entry.status, view.theme.dim)
      objectName: "graphNode" + entry.id
      implicitWidth: Graph.STORY_NODE_W
      implicitHeight: Graph.STORY_NODE_H
      radius: 8
      color: Qt.alpha(view.theme.foreground, current ? 0.14 : 0.06)
      border.width: current ? 2 : 1
      border.color: current ? view.theme.foreground : Qt.alpha(view.theme.foreground, 0.25)

      Rectangle {
        width: 5
        height: parent.height - 2 * storyNode.radius
        anchors.left: parent.left
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        radius: 2
        color: storyNode.tint
      }

      Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 20
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        UI.ThemedText {
          objectName: "graphNodeTitle"
          theme: view.theme
          width: parent.width
          text: storyNode.entry.title
          font.bold: true
          elide: Text.ElideRight
        }

        Item {
          width: parent.width
          height: Math.max(pips.implicitHeight, storyIssues.implicitHeight)

          UI.StatusPips {
            id: pips
            objectName: "graphNodePips"
            theme: view.theme
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            model: storyNode.entry.pips || []
            more: storyNode.entry.morePips || 0
            // The section hides the whole view; a delegate inside the canvas is
            // not always told, so the verdict is handed down explicitly and the
            // pulse never runs for a graph nobody is looking at.
            active: view.visible
          }

          UI.ThemedText {
            id: storyIssues
            objectName: "graphNodeIssues"
            variant: "caption"
            theme: view.theme
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: (storyNode.entry.openIssues || 0) > 0
            text: "\uF024 " + Graph.openIssueLabel(storyNode.entry.openIssues || 0)
            color: Board.statusColor("blocked", view.theme.dim)
          }
        }
      }
    }
  }
}
