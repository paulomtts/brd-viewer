import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../../core/domain/board.js" as Board
import "../../core/domain/brd-extras.js" as Extras
import "../components" as UI
import "../theme" as T

// One issue, opened from the Issues list: its status and close reason, its
// body, the cards it blocks, its refs and referenced-by as keyboard-navigable
// link rows, and its comments. It reads the extras store and opens links
// through the navigator; it owns no state of its own.
Column {
  id: issueDetail
  objectName: "issueDetail"

  property var app
  property var navigator
  property var theme: T.Theme {}

  // The panel scrolls; a link row that takes the cursor asks for it here.
  signal revealRequested(var item)

  readonly property var issue: issueDetail.app.extras.selectedIssue

  visible: issueDetail.app.nav.viewMode === "issue" && !!issueDetail.issue
  spacing: Style.space(10)

  UI.ThemedText {
    objectName: "issueDetailTitle"
    variant: "heading"
    theme: issueDetail.theme
    width: parent.width
    text: issueDetail.issue ? issueDetail.issue.title : ""
    font.bold: true
    wrapMode: Text.WordWrap
  }

  Row {
    spacing: Style.space(6)

    UI.Badge {
      theme: issueDetail.theme
      textObjectName: "issueDetailStatus"
      text: issueDetail.issue ? Extras.issueStatusLabel(issueDetail.issue.status) : ""
      tint: issueDetail.issue ? Extras.issueStatusColor(issueDetail.issue.status, issueDetail.theme.dim)
                              : issueDetail.theme.dim
    }

    UI.ThemedText {
      objectName: "issueDetailBlocksLabel"
      variant: "caption"
      theme: issueDetail.theme
      anchors.verticalCenter: parent.verticalCenter
      visible: text !== ""
      text: issueDetail.issue ? Extras.blocksLabel(issueDetail.issue.blocks.length) : ""
      color: issueDetail.theme.dim
    }
  }

  UI.ThemedText {
    objectName: "issueDetailReason"
    variant: "caption"
    theme: issueDetail.theme
    width: parent.width
    visible: !!(issueDetail.issue && issueDetail.issue.closeReason !== "")
    text: issueDetail.issue ? "Closed: " + issueDetail.issue.closeReason : ""
    color: issueDetail.theme.dim
    wrapMode: Text.WordWrap
  }

  PanelSeparator { foreground: issueDetail.theme.foreground }

  UI.ThemedText {
    objectName: "issueDetailBody"
    variant: "small"
    theme: issueDetail.theme
    width: parent.width
    text: (issueDetail.issue && issueDetail.issue.body !== "") ? issueDetail.issue.body : "No description."
    wrapMode: Text.WordWrap
    textFormat: Text.MarkdownText
  }

  PanelSectionHeader {
    visible: blocksRepeater.count > 0
    text: "BLOCKS"
    foreground: issueDetail.theme.foreground
    fontFamily: issueDetail.theme.fontFamily
  }

  Repeater {
    id: blocksRepeater
    model: issueDetail.sectionLinks("blocks")

    IssueLink {
      required property var modelData
      width: parent.width
      linkName: "issueDetailBlocks" + modelData.number
      targetId: modelData.id
      section: "blocks"
    }
  }

  PanelSectionHeader {
    visible: refsRepeater.count > 0
    text: "REFERENCES"
    foreground: issueDetail.theme.foreground
    fontFamily: issueDetail.theme.fontFamily
  }

  Repeater {
    id: refsRepeater
    model: issueDetail.sectionLinks("ref")

    IssueLink {
      required property var modelData
      width: parent.width
      linkName: "issueDetailRef" + modelData.number
      targetId: modelData.id
      section: "ref"
    }
  }

  PanelSectionHeader {
    visible: backRepeater.count > 0
    text: "REFERENCED BY"
    foreground: issueDetail.theme.foreground
    fontFamily: issueDetail.theme.fontFamily
  }

  Repeater {
    id: backRepeater
    model: issueDetail.sectionLinks("referenced_by")

    IssueLink {
      required property var modelData
      width: parent.width
      linkName: "issueDetailReferencedBy" + modelData.number
      targetId: modelData.id
      section: "referenced_by"
    }
  }

  UI.CommentList {
    objectName: "issueComments"
    width: parent.width
    theme: issueDetail.theme
    comments: issueDetail.issue ? issueDetail.app.extras.commentsFor(issueDetail.issue.id) : []
  }

  // The store's one link list, split per section: the cursor still walks the
  // whole list in its order, so the row's own index comes from the store and
  // the `number` carried here only names the row inside its section.
  function sectionLinks(section) {
    var rows = []
    var links = issueDetail.app.extras.detailLinkList
    for (var i = 0; i < links.length; i++) {
      if (links[i].section === section) rows.push({ id: links[i].id, number: rows.length })
    }
    return rows
  }

  // A card opens as a card, a known issue opens as an issue; nothing else is
  // ever listed (issueDetailLinks leaves unreachable ids out).
  function openTarget(id) {
    var resolved = issueDetail.app.extras.resolvedTarget(id)
    if (resolved.inBoard) issueDetail.navigator.openCard(id)
    else if (resolved.kind === "issue") issueDetail.navigator.openIssue(id)
  }

  component IssueLink: UI.ListRow {
    id: link
    property string linkName: ""
    property string targetId: ""
    property string section: ""
    readonly property var resolved: issueDetail.app.extras.resolvedTarget(link.targetId)
    readonly property bool isIssue: link.resolved.kind === "issue"

    objectName: link.linkName
    theme: issueDetail.theme
    index: issueDetail.app.extras.linkIndex(link.section, link.targetId)
    cursorIndex: issueDetail.app.nav.cursorIndex
    scrollOnCursor: issueDetail.app.nav.scrollOnCursor
    contentMargin: Style.space(6)
    opacity: link.isIssue && link.resolved.status === "closed" ? 0.5 : 1
    onHovered: function(index) { issueDetail.navigator.hoverCursor(index) }
    onActivated: issueDetail.openTarget(link.targetId)
    onRevealRequested: function(item) { issueDetail.revealRequested(item) }

    RowLayout {
      width: parent.width

      UI.ThemedText {
        variant: "small"
        theme: issueDetail.theme
        Layout.fillWidth: true
        text: link.resolved.title
        elide: Text.ElideRight
      }

      UI.ThemedText {
        variant: "caption"
        theme: issueDetail.theme
        text: link.isIssue ? Board.issueBlockerLabel(link.resolved.status) : "[" + link.resolved.status + "]"
        color: link.isIssue
          ? (link.resolved.status === "open" ? Board.statusColor("blocked", issueDetail.theme.dim) : issueDetail.theme.dim)
          : Board.statusColor(link.resolved.status, issueDetail.theme.dim)
      }
    }
  }
}
