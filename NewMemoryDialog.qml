import QtQuick
import qs.Commons
import qs.Ui
import "core/domain/memories.js" as Memories
import "ui/components" as UI
import "ui/theme" as T

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
  // What the shared components draw with; Panel still passes the colours one
  // by one, so the theme follows them.
  property var theme: T.Theme {
    foreground: dialog.foreground
    dim: dialog.dim
    urgent: dialog.urgent
    fontFamily: dialog.fontFamily
  }
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

  UI.ModalCard {
    id: modal
    anchors.fill: parent
    shown: true
    dismissable: !dialog.busy
    maxWidth: Style.space(520)
    maxHeight: modal.height - Style.space(48)
    backdropObjectName: "newMemoryBackdrop"
    cardObjectName: "newMemoryCard"
    onDismissed: dialog.cancelRequested()

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

    UI.ChipRow {
      width: parent.width
      theme: dialog.theme
      chipPrefix: "newMemoryType"
      active: dialog.type
      model: Memories.MEMORY_TYPES.filter(function(t) { return t.id !== "other" })
        .map(function(t) {
          return { id: t.id, label: t.label, tint: Memories.memoryTypeColor(t.id, dialog.dim) }
        })
      onChosen: function(id) { dialog.type = id }
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

    UI.TextAreaBox {
      id: bodyArea
      width: parent.width
      height: Style.space(160)
      editorObjectName: "newMemoryBody"
      submitChords: ["ctrl-enter"]
      placeholder: "What should be remembered?"
      theme: dialog.theme
      enabled: !dialog.busy
      onEscapePressed: dialog.cancelRequested()
      onSubmitRequested: dialog.submit()
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

      UI.ActionButton {
        objectName: "newMemoryCancel"
        text: "Cancel"
        enabled: !dialog.busy
        opacity: 1
        theme: dialog.theme
        onClicked: dialog.cancelRequested()
      }

      UI.ActionButton {
        objectName: "newMemoryCreate"
        text: dialog.busy ? "Creating…" : "Create"
        enabled: !dialog.busy && dialog.valid
        theme: dialog.theme
        onClicked: dialog.submit()
      }
    }
  }
}
