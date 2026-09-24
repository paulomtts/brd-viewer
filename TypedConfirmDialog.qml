import QtQuick
import qs.Commons
import qs.Ui
import "core/domain/projects.js" as Projects

// A modal card over a dimmed backdrop that asks for a typed word before a
// destructive action. Renders and emits only.
Item {
  id: dialog
  objectName: "typedConfirmDialog"
  z: 100

  property bool shown: false
  property string message: ""
  property string detail: ""
  property string confirmLabel: "Confirm delete"
  property bool busy: false
  property string error: ""
  property color foreground: Color.foreground
  property color urgent: Color.urgent
  property color dim: Qt.darker(foreground, 1.55)
  property string fontFamily: Style.font.family
  readonly property Item focusItem: field
  readonly property bool confirmed: Projects.isDeleteConfirmed(field.text)

  signal confirmRequested()
  signal cancelRequested()

  visible: shown
  onShownChanged: if (!shown) field.text = ""

  Rectangle {
    objectName: "confirmBackdrop"
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.55)
    MouseArea { anchors.fill: parent; onClicked: if (!dialog.busy) dialog.cancelRequested() }
  }

  Rectangle {
    id: card
    objectName: "confirmCard"
    anchors.centerIn: parent
    width: Math.min(Style.space(440), parent.width - Style.space(48))
    height: content.implicitHeight + Style.space(36)
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
        width: parent.width
        text: dialog.message
        color: dialog.urgent
        font.family: dialog.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Text {
        visible: dialog.detail !== ""
        width: parent.width
        text: dialog.detail
        color: dialog.dim
        font.family: dialog.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideMiddle
      }

      TextField {
        id: field
        objectName: "confirmTyped"
        width: parent.width
        foreground: dialog.foreground
        placeholderText: "delete"
        enabled: !dialog.busy

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) { dialog.cancelRequested(); event.accepted = true; return }
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (dialog.confirmed && !dialog.busy) dialog.confirmRequested()
            event.accepted = true
          }
        }
      }

      Text {
        objectName: "confirmError"
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
          objectName: "confirmCancel"
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
          objectName: "confirmAccept"
          text: dialog.busy ? "Working…" : dialog.confirmLabel
          enabled: !dialog.busy && dialog.confirmed
          opacity: enabled ? 1 : 0.5
          bordered: true
          foreground: dialog.urgent
          fontFamily: dialog.fontFamily
          fontSize: Style.font.bodySmall
          verticalPadding: Style.spacing.controlPaddingY
          onClicked: dialog.confirmRequested()
        }
      }
    }
  }
}
