// tests/core/domain/tst_text.qml
import QtQuick
import QtTest
import "../../../core/domain/text.js" as Text

TestCase {
  name: "DomainText"

  function test_matches_query_is_case_insensitive_substring() {
    compare(Text.matchesQuery("Write the Parser", "parser"), true)
    compare(Text.matchesQuery("Write the Parser", "PARSER"), true)
    compare(Text.matchesQuery("Write the Parser", "xyz"), false)
  }

  function test_matches_query_empty_query_matches_everything() {
    compare(Text.matchesQuery("anything", ""), true)
    compare(Text.matchesQuery("anything", "   "), true)
    compare(Text.matchesQuery("anything", undefined), true)
  }

  function test_matches_query_trims_the_query() {
    compare(Text.matchesQuery("Write the Parser", "  parser  "), true)
  }

  function test_matches_query_on_missing_text() {
    compare(Text.matchesQuery(undefined, "x"), false)
    compare(Text.matchesQuery(null, "x"), false)
    compare(Text.matchesQuery(undefined, ""), true)
  }
}
