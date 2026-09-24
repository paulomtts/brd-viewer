import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui
import "core/domain/memories.js" as Memories

// A modal form for a new memory note. Keeps its own field state, reset each
// time it opens; emits createRequested(name, type, description, body).
Item {
  id: dialog
  objectName: "newMemoryDialog"
  z: 100

  property bool shown: false
  property bool busy: false
  property string error: ""
  property color foreground: Color.foreground
  property color urgent: Color.urgent
  property color dim: Qt.darker(foreground, 1.55)
  property string fontFamily: Style.font.family
  property string type: "feedback"
  readonly property Item focusItem: nameField
  readonly property bool valid: nameField.text.trim() !== ""

  signal createRequested(string name, string type, string description, string body)
  signal cancelRequested()

  visible: shown
  onShownChanged: {
    if (!shown) return
    nameField.text = ""
    descriptionField.text = ""
    bodyArea.text = ""
    dialog.type = "feedback"
  }

  function submit() {
    if (!dialog.valid || dialog.busy) return
    dialog.createRequested(nameField.text.trim(), dialog.type, descriptionField.text.trim(), bodyArea.text)
  }

  Rectangle {
    objectName: "newMemoryBackdrop"
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.55)
    MouseArea { anchors.fill: parent; onClicked: if (!dialog.busy) dialog.cancelRequested() }
  }

  Rectangle {
    id: card
    objectName: "newMemoryCard"
    anchors.centerIn: parent
    width: Math.min(Style.space(520), parent.width - Style.space(48))
    height: Math.min(parent.height - Style.space(48), content.implicitHeight + Style.space(36))
    radius: Style.space(10)
    color: Color.popups.background
    border.width: 1
    border.color: Color.popups.border

    MouseArea { anchors.fill: parent }

    Column {
      id: content
      anchors.fill: parent
      anchors.margins: Style.space(18)
      spacing: Style.space(8)

      Text {
        text: "New memory"
        color: dialog.foreground
        font.family: dialog.fontFamily
        font.pixelSize: Style.font.heading
        font.bold: true
      }

      TextField {
        id: nameField
        objectName: "newMemoryName"
        width: parent.width
        foreground: dialog.foreground
        placeholderText: "Name"
        enabled: !dialog.busy
        KeyNavigation.tab: descriptionField
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) { dialog.cancelRequested(); event.accepted = true }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { dialog.submit(); event.accepted = true }
        }
      }

      Flow {
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: Memories.MEMORY_TYPES.filter(function(t) { return t.id !== "other" })
          delegate: Rectangle {
            id: chip
            required property var modelData
            readonly property bool active: dialog.type === modelData.id
            readonly property color tint: Memories.memoryTypeColor(modelData.id, dialog.dim)
            objectName: "newMemoryType" + modelData.id
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
              color: dialog.foreground
              font.family: dialog.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: chip.active
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: dialog.type = chip.modelData.id
            }
          }
        }
      }

      TextField {
        id: descriptionField
        objectName: "newMemoryDescription"
        width: parent.width
        foreground: dialog.foreground
        placeholderText: "One-line description (shown in the list and MEMORY.md)"
        enabled: !dialog.busy
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) { dialog.cancelRequested(); event.accepted = true }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { dialog.submit(); event.accepted = true }
        }
      }

      Rectangle {
        width: parent.width
        height: Style.space(160)
        radius: Style.space(6)
        color: Qt.alpha(dialog.foreground, 0.06)
        border.width: 1
        border.color: bodyArea.activeFocus ? dialog.foreground : Qt.alpha(dialog.foreground, 0.3)

        Controls.TextArea {
          id: bodyArea
          objectName: "newMemoryBody"
          anchors.fill: parent
          anchors.margins: Style.space(8)
          background: null
          placeholderText: "What should be remembered?"
          color: dialog.foreground
          font.family: dialog.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: TextEdit.Wrap
          selectByMouse: true
          enabled: !dialog.busy
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { dialog.cancelRequested(); event.accepted = true }
            else if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
              dialog.submit(); event.accepted = true
            }
          }
        }
      }

      Text {
        objectName: "newMemoryError"
        visible: dialog.error !== ""
        width: parent.width
        text: dialog.error
        color: dialog.urgent
        font.family: dialog.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Row {
        spacing: Style.spacing.md

        Button {
          objectName: "newMemoryCancel"
          text: "Cancel"
          enabled: !dialog.busy
          bordered: true
          foreground: dialog.foreground
          fontFamily: dialog.fontFamily
          fontSize: Style.font.bodySmall
          verticalPadding: Style.spacing.controlPaddingY
          onClicked: dialog.cancelRequested()
        }

        Button {
          objectName: "newMemoryCreate"
          text: dialog.busy ? "Creating…" : "Create"
          enabled: !dialog.busy && dialog.valid
          opacity: enabled ? 1 : 0.5
          bordered: true
          foreground: dialog.foreground
          fontFamily: dialog.fontFamily
          fontSize: Style.font.bodySmall
          verticalPadding: Style.spacing.controlPaddingY
          onClicked: dialog.submit()
        }
      }
    }
  }
}
