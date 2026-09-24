import QtQuick
import qs.Commons
import qs.Ui
import "../../core/domain/brd-extras.js" as Extras
import "../theme" as T

// The read-only comments of a card or an issue: author, relative time and the
// body as plain text, oldest first. It renders and owns nothing -- the caller
// passes the list in (a store never reaches a component).
Column {
  id: list

  property var comments: []
  property var theme: T.Theme {}
  // Fixed "now" for the relative times; 0 means the real clock.
  property double nowMs: 0
  property string heading: "COMMENTS"

  readonly property double clock: list.nowMs > 0 ? list.nowMs : Date.now()

  spacing: Style.space(8)

  PanelSectionHeader {
    text: list.heading
    foreground: list.theme.foreground
    fontFamily: list.theme.fontFamily
  }

  ThemedText {
    objectName: "commentsEmpty"
    variant: "dim"
    theme: list.theme
    visible: list.comments.length === 0
    width: parent.width
    text: "No comments."
  }

  Repeater {
    model: list.comments

    Column {
      id: commentRow
      required property var modelData
      required property int index
      objectName: "commentRow" + index
      width: list.width
      spacing: Style.space(2)

      Row {
        spacing: Style.space(8)

        ThemedText {
          objectName: "commentAuthor" + commentRow.index
          variant: "caption"
          theme: list.theme
          text: commentRow.modelData.author !== "" ? commentRow.modelData.author : "unknown"
          font.bold: true
        }

        ThemedText {
          objectName: "commentTime" + commentRow.index
          variant: "caption"
          theme: list.theme
          text: Extras.relativeTime(commentRow.modelData.createdAt, list.clock)
          color: list.theme.dim
        }
      }

      ThemedText {
        objectName: "commentBody" + commentRow.index
        variant: "small"
        theme: list.theme
        width: parent.width
        text: commentRow.modelData.body
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
      }
    }
  }
}
