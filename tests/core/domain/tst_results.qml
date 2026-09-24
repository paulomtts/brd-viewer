// tests/core/domain/tst_results.qml
import QtQuick
import QtTest
import "../../../core/domain/results.js" as Results

TestCase {
  name: "DomainResults"

  function test_parse_json_line_success_exposes_the_payload() {
    var r = Results.parseJsonLine('{"ok": true, "snapshot": "/s"}\n', 0, "generic")
    compare(r.ok, true)
    compare(r.data.snapshot, "/s")
    compare(r.error, "")
  }

  function test_parse_json_line_uses_the_last_non_empty_line() {
    var r = Results.parseJsonLine('noise\n\n{"ok": true, "n": 2}\n\n', 0, "generic")
    compare(r.ok, true)
    compare(r.data.n, 2)
  }

  function test_parse_json_line_fails_on_a_nonzero_exit_code_even_when_ok_is_true() {
    var r = Results.parseJsonLine('{"ok": true}', 1, "generic")
    compare(r.ok, false)
    compare(r.error, "generic")
    compare(r.data.ok, true)
  }

  function test_parse_json_line_reports_the_payload_error() {
    var r = Results.parseJsonLine('{"ok": false, "error": "could not snapshot"}', 1, "generic")
    compare(r.ok, false)
    compare(r.error, "could not snapshot")
  }

  function test_parse_json_line_falls_back_to_the_generic_message() {
    compare(Results.parseJsonLine('{"ok": false}', 0, "generic").error, "generic")
    compare(Results.parseJsonLine('{"ok": false, "error": ""}', 0, "generic").error, "generic")
    compare(Results.parseJsonLine('{"ok": false, "error": 5}', 0, "generic").error, "generic")
  }

  function test_parse_json_line_on_garbage_or_nothing() {
    var g = Results.parseJsonLine("not json", 0, "generic")
    compare(g.ok, false)
    compare(g.data, null)
    compare(g.error, "generic")
    compare(Results.parseJsonLine("", 0, "generic").ok, false)
    compare(Results.parseJsonLine(undefined, 0, "generic").ok, false)
    compare(Results.parseJsonLine("   \n  \n", 0, "generic").data, null)
  }

  function test_parse_json_line_rejects_payloads_that_are_not_objects() {
    compare(Results.parseJsonLine("5", 0, "generic", false).ok, false)
    compare(Results.parseJsonLine("null", 0, "generic", false).ok, false)
    compare(Results.parseJsonLine('"text"', 0, "generic", false).ok, false)
  }

  // The viewer-state helper answers without an `ok` key.
  function test_parse_json_line_without_require_ok_accepts_a_plain_object() {
    var r = Results.parseJsonLine('{"last_project": "/home/u/p"}', 0, "generic", false)
    compare(r.ok, true)
    compare(r.data.last_project, "/home/u/p")
    compare(Results.parseJsonLine('{"last_project": "/x"}', 1, "generic", false).ok, false)
    compare(Results.parseJsonLine('{"last_project": "/x"}', 0, "generic", true).ok, false)
  }
}
