import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// The Documents section's list: one row per Markdown file (title, dim path).
// It renders and emits only; Panel.qml owns the list, the cursor and the query.
Column {
  id: view
  objectName: "documentsView"
  spacing: Style.space(6)

  property var docs: []
  property string query: ""
  property int cursorIndex: -1
  property bool loading: false
  property string error: ""
  property bool truncated: false
  property bool scrollOnCursor: false
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.55)
  property string fontFamily: Style.font.family

  signal docChosen(string path)
  signal hovered(int index)
  signal revealRequested(var item)

  Text {
    objectName: "docsMessage"
    visible: text !== ""
    width: parent.width
    text: view.loading ? "Loading documents…"
      : view.error !== "" ? view.error
      : view.docs.length === 0 ? (view.query === "" ? "No Markdown documents found in this project."
        : "No documents match “" + view.query + "”.")
      : ""
    color: view.dim
    font.family: view.fontFamily
    font.pixelSize: Style.font.body
    wrapMode: Text.WordWrap
  }

  Repeater {
    model: view.loading || view.error !== "" ? [] : view.docs
    delegate: DocRow {}
  }

  Text {
    objectName: "docsTruncated"
    visible: view.truncated
    width: parent.width
    text: "Showing the first 500 documents."
    color: view.dim
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
  }

  component DocRow: CursorSurface {
    id: row
    required property var modelData
    required property int index
    objectName: "docRow" + index

    width: view.width
    implicitHeight: rowColumn.implicitHeight + Style.spacing.rowPaddingX
    hasCursor: view.cursorIndex === index
    foreground: view.foreground
    onHasCursorChanged: if (hasCursor && view.scrollOnCursor) view.revealRequested(row)

    Column {
      id: rowColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(2)

      Text {
        width: parent.width
        text: row.modelData.title
        color: view.foreground
        font.family: view.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: row.modelData.path
        color: view.dim
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideMiddle
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: view.hovered(row.index)
      onClicked: view.docChosen(row.modelData.path)
    }
  }
}
