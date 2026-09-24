import QtQuick
import qs.Commons
import "../../core/domain/brd-extras.js" as Extras
import "../components" as UI
import "../theme" as T

// The Issues section: brd's issues, open first, then closed. One row per issue
// (status badge, title, how many cards it blocks, how many comments it has),
// with Open/Closed filter chips -- clicking the active chip means All again. It
// reads the extras store and asks the navigator to open an issue or move the
// cursor; it owns no state of its own.
Column {
  id: screen
  objectName: "issuesView"

  property var app
  property var navigator
  property var theme: T.Theme {}

  // The panel scrolls; a row that takes the cursor asks for it here.
  signal revealRequested(var item)

  visible: screen.app.nav.viewMode === "issues" && !!screen.app.projects.selectedProject
  spacing: Style.space(6)

  UI.FilterableList {
    width: parent.width
    theme: screen.theme

    chipsObjectName: "issueChips"
    chipPrefix: "issueChip"
    statusObjectName: "issuesMessage"
    chips: screen.app.extras.statusCounts.map(function(entry) {
      return { id: entry.id, label: entry.label, count: entry.count,
               tint: Extras.issueStatusColor(entry.id, screen.theme.dim) }
    })
    activeChip: screen.app.extras.issueStatus
    onChipToggled: function(id) { screen.app.extras.toggleIssueStatus(id) }

    loading: screen.app.extras.extrasLoading && screen.app.extras.issues.length === 0
    loadingText: "Loading issues…"
    empty: screen.app.extras.filteredIssues.length === 0
    filtered: screen.app.nav.searchQuery !== "" || screen.app.extras.issueStatus !== ""
    filteredText: screen.app.nav.searchQuery !== ""
      ? "No issues match “" + screen.app.nav.searchQuery + "”."
      : "No " + Extras.issueStatusLabel(screen.app.extras.issueStatus) + " issues."
    emptyText: "No issues in this project."

    model: screen.app.extras.filteredIssues
    rowDelegate: Component { IssueRow {} }
  }

  component IssueRow: UI.ListRow {
    id: row
    required property var modelData
    required index
    objectName: "issueRow" + row.index

    width: screen.width
    theme: screen.theme
    cursorIndex: screen.app.nav.cursorIndex
    scrollOnCursor: screen.app.nav.scrollOnCursor
    onHovered: function(index) { screen.navigator.hoverCursor(index) }
    onActivated: screen.navigator.openIssue(row.modelData.id)
    onRevealRequested: function(item) { screen.revealRequested(item) }

    Row {
      width: parent.width
      spacing: Style.space(8)

      UI.Badge {
        id: rowBadge
        theme: screen.theme
        textObjectName: "issueRowBadge" + row.index
        text: Extras.issueStatusLabel(row.modelData.status)
        tint: Extras.issueStatusColor(row.modelData.status, screen.theme.dim)
      }

      UI.ThemedText {
        theme: screen.theme
        width: Math.max(0, parent.width - rowBadge.width - parent.spacing)
        text: row.modelData.title
        elide: Text.ElideRight
      }
    }

    Row {
      width: parent.width
      spacing: Style.space(10)

      UI.ThemedText {
        objectName: "issueRowBlocks" + row.index
        variant: "caption"
        theme: screen.theme
        visible: text !== ""
        text: Extras.blocksLabel(row.modelData.blocks.length)
        color: screen.theme.dim
      }

      UI.ThemedText {
        objectName: "issueRowComments" + row.index
        variant: "caption"
        theme: screen.theme
        visible: text !== ""
        text: Extras.commentCountLabel(row.modelData.commentCount)
        color: screen.theme.dim
      }
    }
  }
}
