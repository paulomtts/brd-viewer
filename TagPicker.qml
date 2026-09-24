import QtQuick
import qs.Commons
import "core/domain/documents.js" as Documents
import "ui/components" as UI
import "ui/theme" as T

// Chooses the open document's type. Renders and emits only; Panel.qml runs
// set-doc-tag.py and owns busy/error.
Column {
  id: picker
  objectName: "tagPicker"
  spacing: Style.space(6)

  property string current: ""
  property bool busy: false
  property string error: ""
  // The one input for every colour and font: Panel passes its Theme down,
  // and a standalone instance renders with the shell defaults.
  property var theme: T.Theme {}

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

    UI.ThemedText {
      variant: "caption"
      theme: picker.theme
      anchors.verticalCenter: parent.verticalCenter
      text: "Type"
    }

    UI.ChipRow {
      width: picker.width - Style.space(48)
      theme: picker.theme
      chipPrefix: "tagChip"
      active: picker.current
      busy: picker.busy
      model: picker.choices.map(function(choice) {
        return {
          id: choice.id,
          label: choice.label,
          tint: Documents.docCategoryColor(choice.id, picker.theme.dim)
        }
      })
      onChosen: function(id) { picker.tagChosen(id) }
    }
  }

  UI.ThemedText {
    objectName: "tagError"
    variant: "caption"
    theme: picker.theme
    visible: picker.error !== ""
    width: parent.width
    text: picker.error
    wrapMode: Text.WordWrap
  }
}
