import QtQuick
import qs.Commons
import "../components" as UI
import "../theme" as T

// One open Markdown document: either the too-large/read-error message or the
// rendered body. Its path and its type picker live in the panel's fixed toolbar
// (DocumentsToolbar), so only the body scrolls. It reads the documents store
// and calls it; it owns no state of its own.
Column {
  id: docScreen

  property var app
  property var navigator
  property var theme: T.Theme {}

  visible: docScreen.app.nav.viewMode === "document"
  spacing: Style.space(10)

  UI.ThemedText {
    variant: "dim"
    theme: docScreen.theme
    visible: docScreen.app.docs.docTooLargeFlag || docScreen.app.docs.docError !== ""
    width: parent.width
    text: docScreen.app.docs.docTooLargeFlag ? "This document is too large to display." : docScreen.app.docs.docError
    wrapMode: Text.WordWrap
  }

  UI.ThemedText {
    variant: "small"
    theme: docScreen.theme
    visible: !docScreen.app.docs.docTooLargeFlag && docScreen.app.docs.docError === ""
    width: parent.width
    text: docScreen.app.docs.docText !== "" ? docScreen.app.docs.docText : "Loading…"
    wrapMode: Text.WordWrap
    textFormat: Text.MarkdownText
  }
}
