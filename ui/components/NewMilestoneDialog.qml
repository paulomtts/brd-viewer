import QtQuick
import qs.Commons
import qs.Ui
import "../../core/domain/documents.js" as Documents
import "../../core/domain/milestones.js" as Milestones
import "../components" as UI
import "../theme" as T

// A modal form for a new milestone, built on the same ModalCard conventions as
// New memory: the backdrop and Escape cancel.
//
// There is one way in: pick one of the project's Markdown documents and let the
// default agent build the milestone from it. The owner owns the selection --
// the dialog only reports it; the spec list's search text is the one thing it
// keeps for itself.
Item {
  id: dialog
  objectName: "newMilestoneDialog"
  z: 100

  property bool shown: false
  property string error: ""
  // Milestones.specChoices(docs): [{ title, path, category }], specs first.
  property var specs: []
  property string selectedSpec: ""
  // "" when the default agent can run unattended, otherwise the reason it cannot.
  property string agentMessage: ""
  property string agentName: ""
  property string agentNote: ""
  // True while the default agent is still being looked up: nothing is known
  // yet, so OK waits rather than starting a run that may be refused.
  property bool agentChecking: false
  // The owner's verdict on whether a run may start at all. The default is what
  // the dialog can work out on its own, so a standalone instance behaves; Panel
  // overrides it with the store's `agentReady`, which also knows that an agent
  // nobody has checked yet is not one to run on.
  property bool agentReady: !dialog.agentChecking && dialog.agentMessage === ""
  // A milestone job is already running (one per shell), so no run can start.
  property bool jobRunning: false
  // The documents listing's own state, so an empty list while it is still
  // being fetched never reads as "this project has no documents".
  property bool docsLoading: false
  property string docsError: ""
  // The one input for every colour and font: Panel passes its Theme down,
  // and a standalone instance renders with the shell defaults.
  property var theme: T.Theme {}

  readonly property Item focusItem: searchField
  readonly property var visibleSpecs: Milestones.filterSpecChoices(dialog.specs, searchField.text)
  // The index the list paints its cursor on: the selected path's row, if it
  // survived the search.
  readonly property int selectedIndex: {
    var list = dialog.visibleSpecs
    for (var i = 0; i < list.length; i++) if (list[i].path === dialog.selectedSpec) return i
    return -1
  }
  readonly property bool valid: dialog.selectedSpec !== ""
    && dialog.agentReady && !dialog.jobRunning

  signal specChosen(string path)
  signal submitRequested()
  signal cancelRequested()

  visible: shown
  onShownChanged: {
    if (!shown) return
    searchField.text = ""
  }

  function cancel() {
    dialog.cancelRequested()
  }

  function submit() {
    if (!dialog.valid) return
    dialog.submitRequested()
  }

  // The keyboard's way through the spec list: the neighbour of whatever is
  // selected, clamped at both ends, over the rows the search actually left.
  function moveSelection(step) {
    var list = dialog.visibleSpecs
    if (list.length === 0) return
    var at = dialog.selectedIndex
    var next = at < 0 ? (step > 0 ? 0 : list.length - 1)
      : Math.max(0, Math.min(list.length - 1, at + step))
    dialog.specChosen(list[next].path)
  }

  UI.ModalCard {
    id: modal
    anchors.fill: parent
    shown: true
    dismissable: true
    maxWidth: Style.space(560)
    maxHeight: modal.height - Style.space(48)
    backdropObjectName: "newMilestoneBackdrop"
    cardObjectName: "newMilestoneCard"
    onDismissed: dialog.cancelRequested()

    UI.ThemedText {
      objectName: "newMilestoneHeading"
      variant: "heading"
      theme: dialog.theme
      text: "New milestone"
      font.bold: true
    }

    Column {
      objectName: "newMilestoneSpecs"
      width: parent.width
      spacing: Style.space(8)

      TextField {
        id: searchField
        objectName: "newMilestoneSearch"
        width: parent.width
        foreground: dialog.theme.foreground
        placeholderText: "Search documents…"
        // The search field is where the keyboard lives, so it also walks the
        // list and starts the run.
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) { dialog.cancel(); event.accepted = true }
          else if (event.key === Qt.Key_Down) { dialog.moveSelection(1); event.accepted = true }
          else if (event.key === Qt.Key_Up) { dialog.moveSelection(-1); event.accepted = true }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { dialog.submit(); event.accepted = true }
        }
      }

      Flickable {
        id: specList
        objectName: "newMilestoneSpecList"
        width: parent.width
        // The card must not grow past the panel: the list scrolls instead.
        height: Math.min(specColumn.implicitHeight, Style.space(220))
        contentHeight: specColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        UI.FilterableList {
          id: specColumn
          width: specList.width
          theme: dialog.theme
          statusObjectName: "specsMessage"
          loading: dialog.docsLoading
          loadingText: "Loading documents…"
          error: dialog.docsError
          empty: dialog.visibleSpecs.length === 0
          filtered: searchField.text !== ""
          emptyText: "No documents found in this project."
          filteredText: "No documents match “" + searchField.text + "”."
          model: dialog.visibleSpecs
          rowDelegate: Component { SpecRow {} }
        }
      }

      UI.ThemedText {
        objectName: "newMilestoneAgentChecking"
        variant: "caption"
        theme: dialog.theme
        visible: dialog.agentChecking
        width: parent.width
        text: "Checking the default agent…"
      }

      UI.ThemedText {
        objectName: "newMilestoneAgent"
        variant: "caption"
        theme: dialog.theme
        visible: !dialog.agentChecking && dialog.agentMessage === "" && dialog.agentName !== ""
        width: parent.width
        text: "Agent: " + dialog.agentName
        elide: Text.ElideRight
      }

      UI.ThemedText {
        objectName: "newMilestoneAgentNote"
        variant: "caption"
        theme: dialog.theme
        visible: !dialog.agentChecking && dialog.agentMessage === "" && dialog.agentNote !== ""
        width: parent.width
        text: dialog.agentNote
        wrapMode: Text.WordWrap
      }

      UI.ThemedText {
        objectName: "newMilestoneJobRunning"
        variant: "caption"
        theme: dialog.theme
        visible: dialog.jobRunning
        width: parent.width
        text: "A milestone run is already in progress."
        color: dialog.theme.urgent
        wrapMode: Text.WordWrap
      }

      UI.ThemedText {
        objectName: "newMilestoneAgentMessage"
        variant: "caption"
        theme: dialog.theme
        visible: !dialog.agentChecking && dialog.agentMessage !== ""
        width: parent.width
        text: dialog.agentMessage
        color: dialog.theme.urgent
        wrapMode: Text.WordWrap
      }
    }

    // ---- Footer -----------------------------------------------------------

    UI.ThemedText {
      objectName: "newMilestoneError"
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
        objectName: "newMilestoneCancel"
        text: "Cancel"
        opacity: 1
        theme: dialog.theme
        onClicked: dialog.cancel()
      }

      UI.ActionButton {
        objectName: "newMilestoneOk"
        text: "Start"
        enabled: dialog.valid
        theme: dialog.theme
        onClicked: dialog.submit()
      }
    }
  }

  component SpecRow: UI.ListRow {
    id: row
    required property var modelData
    required index
    objectName: "specRow" + row.index

    width: specList.width
    theme: dialog.theme
    cursorIndex: dialog.selectedIndex
    onActivated: dialog.specChosen(row.modelData.path)

    Row {
      width: parent.width
      spacing: Style.space(8)

      UI.ThemedText {
        objectName: "specRowTitle" + row.index
        theme: dialog.theme
        width: Math.max(0, parent.width - (rowBadge.visible ? rowBadge.width + parent.spacing : 0))
        text: row.modelData.title
        elide: Text.ElideRight
      }

      UI.Badge {
        id: rowBadge
        theme: dialog.theme
        textObjectName: "specRowBadge" + row.index
        visible: text !== ""
        text: Documents.docCategoryLabel(row.modelData.category)
        tint: Documents.docCategoryColor(row.modelData.category, dialog.theme.dim)
      }
    }

    UI.ThemedText {
      objectName: "specRowPath" + row.index
      variant: "caption"
      theme: dialog.theme
      width: parent.width
      text: row.modelData.path
      elide: Text.ElideMiddle
    }
  }
}
