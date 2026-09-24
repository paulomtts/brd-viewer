import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../../core/domain/board.js" as Board
import "../components" as UI
import "../theme" as T

// One card, opened from the Board or the Graph: its parent, its blockers and
// its children as keyboard-navigable link rows, plus the kind/status badges and
// the description. It reads the board store and opens links through the
// navigator; it owns no state of its own.
Column {
  id: detailCard

  property var app
  property var navigator
  property var theme: T.Theme {}

  // The panel scrolls; a link row that takes the cursor asks for it here.
  signal revealRequested(var item)

  visible: detailCard.app.nav.viewMode === "entry" && !!detailCard.app.board.cardMap[detailCard.app.board.selectedCardId]
  spacing: Style.space(10)

  readonly property var card: detailCard.app.board.cardMap[detailCard.app.board.selectedCardId]

  DetailLink {
    visible: !!(detailCard.card && detailCard.card.parentId)
    width: parent.width
    prefix: "↑ "
    resolved: detailCard.card && detailCard.card.parentId
      ? detailCard.app.board.resolvedCard(detailCard.card.parentId) : ({ title: "", status: "", inBoard: false })
    rowIndex: detailCard.card && detailCard.card.parentId ? detailCard.app.board.linkIndex("parent", detailCard.card.parentId) : -1
    onActivated: if (resolved.inBoard) detailCard.navigator.openCard(detailCard.card.parentId)
  }

  UI.ThemedText {
    variant: "heading"
    theme: detailCard.theme
    width: parent.width
    text: detailCard.card ? detailCard.card.title : ""
    font.bold: true
    wrapMode: Text.WordWrap
  }

  Row {
    spacing: Style.space(6)

    Badge {
      text: detailCard.card ? Board.kindLabel(detailCard.card.depth) : ""
      tone: detailCard.theme.foreground
    }

    Badge {
      text: detailCard.card ? detailCard.app.board.statusText(detailCard.card.status) : ""
      tone: detailCard.card ? Board.statusColor(detailCard.card.status, detailCard.theme.dim) : detailCard.theme.dim
    }
  }

  PanelSeparator { foreground: detailCard.theme.foreground }

  UI.ThemedText {
    variant: "small"
    theme: detailCard.theme
    width: parent.width
    text: (detailCard.card && detailCard.card.description) ? detailCard.card.description : "No description."
    wrapMode: Text.WordWrap
    textFormat: Text.MarkdownText
  }

  PanelSectionHeader {
    visible: !!(detailCard.card && detailCard.card.blocked_by && detailCard.card.blocked_by.length > 0)
    text: "BLOCKED BY"
    foreground: detailCard.theme.foreground
    fontFamily: detailCard.theme.fontFamily
  }

  Repeater {
    model: (detailCard.card && detailCard.card.blocked_by) ? detailCard.card.blocked_by : []

    DetailLink {
      required property string modelData
      width: parent.width
      resolved: detailCard.app.board.resolvedCard(modelData)
      rowIndex: detailCard.app.board.linkIndex("blocker", modelData)
      onActivated: if (resolved.inBoard) detailCard.navigator.openCard(modelData)
    }
  }

  PanelSectionHeader {
    visible: !!(detailCard.card && detailCard.card.children && detailCard.card.children.length > 0)
    text: "CHILDREN"
    foreground: detailCard.theme.foreground
    fontFamily: detailCard.theme.fontFamily
  }

  Repeater {
    model: (detailCard.card && detailCard.card.children) ? detailCard.card.children : []

    DetailLink {
      required property var modelData
      width: parent.width
      resolved: detailCard.app.board.resolvedCard(modelData.id)
      rowIndex: detailCard.app.board.linkIndex("child", modelData.id)
      onActivated: detailCard.navigator.openCard(modelData.id)
    }
  }

  // The card detail's own pill: bordered, translucent and wider than the shared
  // ui/components/Badge, which is a filled chip. A documented duplication: the
  // two designs are not the same component.
  component Badge: Rectangle {
    id: badge
    property string text: ""
    property color tone: detailCard.theme.foreground

    visible: text !== ""
    width: implicitWidth
    height: implicitHeight
    implicitWidth: badgeLabel.implicitWidth + Style.space(14)
    implicitHeight: badgeLabel.implicitHeight + Style.space(4)
    radius: height / 2
    color: Qt.rgba(tone.r, tone.g, tone.b, 0.16)
    border.color: tone
    border.width: 1

    UI.ThemedText {
      id: badgeLabel
      variant: "caption"
      theme: detailCard.theme
      anchors.centerIn: parent
      text: badge.text
      color: badge.tone
      font.bold: true
    }
  }

  component DetailLink: UI.ListRow {
    id: detailLink
    property var resolved: ({ title: "", status: "", inBoard: true })
    property alias rowIndex: detailLink.index
    property string prefix: ""

    theme: detailCard.theme
    cursorIndex: detailCard.app.nav.cursorIndex
    scrollOnCursor: detailCard.app.nav.scrollOnCursor
    contentMargin: Style.space(6)
    hoverCursorShape: detailLink.resolved.inBoard ? Qt.PointingHandCursor : Qt.ArrowCursor
    onHovered: function(index) { detailCard.navigator.hoverCursor(index) }
    onRevealRequested: function(item) { detailCard.revealRequested(item) }

    RowLayout {
      id: detailLinkLayout
      width: parent.width

      UI.ThemedText {
        variant: "small"
        theme: detailCard.theme
        Layout.fillWidth: true
        text: detailLink.prefix + detailLink.resolved.title + (detailLink.resolved.inBoard ? "" : " (not in this board)")
        color: detailLink.resolved.inBoard ? detailCard.theme.foreground : detailCard.theme.dim
        elide: Text.ElideRight
      }

      UI.ThemedText {
        variant: "caption"
        theme: detailCard.theme
        visible: detailLink.resolved.inBoard
        text: "[" + detailLink.resolved.status + "]"
        color: Board.statusColor(detailLink.resolved.status, detailCard.theme.dim)
      }
    }
  }
}
