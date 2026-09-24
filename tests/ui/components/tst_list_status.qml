import QtQuick
import QtTest
import qs.Commons
import "../../../ui/components" as UI
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "ListStatus"
  when: windowShown
  visible: true
  width: 400; height: 200

  T.Theme { id: tcTheme; foreground: "#00ff00" }

  Component {
    id: statusC
    UI.ListStatus {
      theme: tcTheme
      loadingText: "Loading documents…"
      emptyText: "No Markdown documents found in this project."
      filteredText: "No documents match “zz”."
    }
  }

  function make() { return createTemporaryObject(statusC, tc) }

  function test_it_says_nothing_when_the_list_has_rows() {
    var status = make()
    compare(status.text, "")
    compare(status.visible, false)
  }

  function test_loading_wins_over_everything() {
    var status = make()
    status.error = "boom"
    status.empty = true
    status.filtered = true
    status.loading = true
    compare(status.text, "Loading documents…")
    compare(status.visible, true)
  }

  function test_an_error_wins_over_the_empty_texts() {
    var status = make()
    status.empty = true
    status.filtered = true
    status.error = "boom"
    compare(status.text, "boom")
  }

  function test_an_empty_list_shows_the_plain_empty_text() {
    var status = make()
    status.empty = true
    compare(status.text, "No Markdown documents found in this project.")
    compare(status.visible, true)
  }

  function test_an_empty_filtered_list_shows_the_filtered_text() {
    var status = make()
    status.empty = true
    status.filtered = true
    compare(status.text, "No documents match “zz”.")
  }

  function test_it_is_a_dim_body_text_in_the_theme() {
    var status = make()
    status.empty = true
    compare(String(status.color), String(tcTheme.dim))
    compare(status.font.pixelSize, Style.font.body)
  }
}
