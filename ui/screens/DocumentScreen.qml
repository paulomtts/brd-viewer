import QtQuick
import qs.Commons
import "../components" as UI
import "../theme" as T

// One open Markdown document: its path, its type picker, and either the
// too-large/read-error message or the rendered body. It reads the documents
// store and calls it; it owns no state of its own.
Column {
  id: docScreen

  property var app
  property var navigator
  property var theme: T.Theme {}

  visible: docScreen.app.nav.viewMode === "document"
  spacing: Style.space(10)

  UI.ThemedText {
    variant: "caption"
    theme: docScreen.theme
    width: parent.width
    text: docScreen.app.docs.selectedDocPath
    elide: Text.ElideMiddle
  }

  UI.TagPicker {
    width: parent.width
    current: docScreen.app.docs.selectedDocCategory
    busy: docScreen.app.docs.docTagBusy
    error: docScreen.app.docs.docTagError
    theme: docScreen.theme
    onTagChosen: function(id) { docScreen.app.docs.setDocTag(id) }
  }

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
