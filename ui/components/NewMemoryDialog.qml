import QtQuick
import qs.Commons
import qs.Ui
import "../../core/domain/memories.js" as Memories
import "../components" as UI
import "../theme" as T

// A modal form for a new memory note. Keeps its own field state, reset each
// time it opens; emits createRequested(name, type, description, body).
Item {
  id: dialog
  objectName: "newMemoryDialog"
  z: 100

  property bool shown: false
  property bool busy: false
  property string error: ""
  property string type: "feedback"
  // The one input for every colour and font: Panel passes its Theme down,
  // and a standalone instance renders with the shell defaults.
  property var theme: T.Theme {}
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

    UI.ThemedText {
      variant: "heading"
      theme: dialog.theme
      text: "New memory"
      font.bold: true
    }

    TextField {
      id: nameField
      objectName: "newMemoryName"
      width: parent.width
      foreground: dialog.theme.foreground
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
          return { id: t.id, label: t.label, tint: Memories.memoryTypeColor(t.id, dialog.theme.dim) }
        })
      onChosen: function(id) { dialog.type = id }
    }

    TextField {
      id: descriptionField
      objectName: "newMemoryDescription"
      width: parent.width
      foreground: dialog.theme.foreground
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

    UI.ThemedText {
      objectName: "newMemoryError"
      variant: "caption"
      theme: dialog.theme
      visible: dialog.error !== ""
      width: parent.width
      text: dialog.error
      color: dialog.theme.urgent
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
