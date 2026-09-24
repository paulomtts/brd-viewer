import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "core/domain/documents.js" as Documents

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
  property var categories: []
  property string activeCategory: ""
  property bool scrollOnCursor: false
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.55)
  property string fontFamily: Style.font.family

  signal docChosen(string path)
  signal hovered(int index)
  signal revealRequested(var item)
  signal categoryToggled(string id)

  Flow {
    objectName: "docChips"
    visible: view.categories.length > 0 && !view.loading && view.error === ""
    width: parent.width
    spacing: Style.space(6)

    Repeater {
      model: view.categories
      delegate: CategoryChip {}
    }
  }

  Text {
    objectName: "docsMessage"
    visible: text !== ""
    width: parent.width
    text: view.loading ? "Loading documents…"
      : view.error !== "" ? view.error
      : view.docs.length === 0 ? (view.query !== "" ? "No documents match “" + view.query + "”."
        : view.activeCategory !== "" ? "No " + Documents.docCategoryLabel(view.activeCategory) + " documents."
        : "No Markdown documents found in this project.")
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

      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          width: Math.max(0, parent.width - (rowBadge.visible ? rowBadge.width + parent.spacing : 0))
          text: row.modelData.title
          color: view.foreground
          font.family: view.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Rectangle {
          id: rowBadge
          visible: badgeText.text !== ""
          width: badgeText.implicitWidth + Style.space(12)
          height: badgeText.implicitHeight + Style.space(2)
          radius: height / 2
          color: Qt.alpha(badgeText.color, 0.18)

          Text {
            id: badgeText
            objectName: "docRowBadge" + row.index
            anchors.centerIn: parent
            text: Documents.docCategoryLabel(row.modelData.category)
            color: Documents.docCategoryColor(row.modelData.category, view.dim)
            font.family: view.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
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

  component CategoryChip: Rectangle {
    id: chip
    required property var modelData
    readonly property bool active: view.activeCategory === modelData.id
    property alias text: chipText.text
    objectName: "docChip" + modelData.id

    width: chipText.implicitWidth + Style.space(20)
    height: chipText.implicitHeight + Style.space(8)
    radius: height / 2
    color: active ? Qt.alpha(tint, 0.35) : Qt.alpha(tint, 0.12)
    border.width: 1
    border.color: active ? tint : Qt.alpha(tint, 0.4)
    readonly property color tint: Documents.docCategoryColor(modelData.id, view.dim)

    Text {
      id: chipText
      anchors.centerIn: parent
      text: chip.modelData.label + " " + chip.modelData.count
      color: view.foreground
      font.family: view.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: chip.active
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: view.categoryToggled(chip.modelData.id)
    }
  }
}
