import QtQuick
import qs.Commons
import "core/domain/documents.js" as Documents

// Chooses the open document's type. Renders and emits only; Panel.qml runs
// set-doc-tag.py and owns busy/error.
Column {
  id: picker
  objectName: "tagPicker"
  spacing: Style.space(6)

  property string current: ""
  property bool busy: false
  property string error: ""
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.55)
  property string fontFamily: Style.font.family

  signal tagChosen(string id)

  readonly property var choices: [
    { id: "architecture", label: "Architecture" },
    { id: "specs", label: "Specs" },
    { id: "standards", label: "Standards" },
    { id: "audits", label: "Audits" },
    { id: "default", label: "Folder default" }
  ]

  Row {
    spacing: Style.space(8)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "Type"
      color: picker.dim
      font.family: picker.fontFamily
      font.pixelSize: Style.font.caption
    }

    Flow {
      width: picker.width - Style.space(48)
      spacing: Style.space(6)

      Repeater {
        model: picker.choices
        delegate: Rectangle {
          id: chip
          required property var modelData
          readonly property bool active: picker.current === modelData.id
          readonly property color tint: Documents.docCategoryColor(modelData.id, picker.dim)
          property alias text: chipText.text
          objectName: "tagChip" + modelData.id
          opacity: picker.busy ? 0.5 : 1
          width: chipText.implicitWidth + Style.space(20)
          height: chipText.implicitHeight + Style.space(8)
          radius: height / 2
          color: active ? Qt.alpha(tint, 0.35) : Qt.alpha(tint, 0.12)
          border.width: 1
          border.color: active ? tint : Qt.alpha(tint, 0.4)

          Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.modelData.label
            color: picker.foreground
            font.family: picker.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: chip.active
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: if (!picker.busy) picker.tagChosen(chip.modelData.id)
          }
        }
      }
    }
  }

  Text {
    objectName: "tagError"
    visible: picker.error !== ""
    width: parent.width
    text: picker.error
    color: picker.dim
    font.family: picker.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }
}
