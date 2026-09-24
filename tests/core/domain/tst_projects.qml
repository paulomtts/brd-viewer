// tests/core/domain/tst_projects.qml
import QtQuick
import QtTest
import "../../../core/domain/projects.js" as Projects

TestCase {
  name: "DomainProjects"

  // ---- delete confirmation and result parsing -----------------------------

  function test_is_delete_confirmed_data() {
    return [
      { tag: "exact", text: "delete", ok: true },
      { tag: "padded", text: "  delete  ", ok: true },
      { tag: "case", text: "DeLeTe", ok: true },
      { tag: "partial", text: "delet", ok: false },
      { tag: "extra", text: "delete it", ok: false },
      { tag: "empty", text: "", ok: false },
      { tag: "undefined", text: undefined, ok: false }
    ]
  }

  function test_is_delete_confirmed(data) {
    compare(Projects.isDeleteConfirmed(data.text), data.ok)
  }

  function test_parse_delete_result_success() {
    var r = Projects.parseDeleteResult('{"ok": true, "snapshot": "/h/Snapshots/x"}\n', 0)
    compare(r.ok, true)
    compare(r.snapshot, "/h/Snapshots/x")
    compare(r.error, "")
  }

  function test_parse_delete_result_reports_the_helpers_error() {
    var r = Projects.parseDeleteResult('{"ok": false, "error": "could not snapshot"}', 1)
    compare(r.ok, false)
    compare(r.error, "could not snapshot")
  }

  function test_parse_delete_result_uses_the_last_line() {
    var r = Projects.parseDeleteResult('noise\n{"ok": true, "snapshot": "/s"}\n', 0)
    compare(r.ok, true)
  }

  function test_parse_delete_result_failure_when_exit_code_nonzero_even_if_ok_true() {
    compare(Projects.parseDeleteResult('{"ok": true, "snapshot": "/s"}', 1).ok, false)
  }

  function test_parse_delete_result_unparseable_or_empty_output() {
    compare(Projects.parseDeleteResult("", 1).ok, false)
    compare(Projects.parseDeleteResult("", 1).error, "Could not delete the project.")
    compare(Projects.parseDeleteResult("not json", 0).ok, false)
    compare(Projects.parseDeleteResult(undefined, 0).ok, false)
  }

  // ---- project selection ------------------------------------------------

  property var pa: ({ root_path: "/a", name: "alpha" })
  property var pb: ({ root_path: "/b", name: "beta" })
  property var pc: ({ root_path: "/c", name: "gamma" })

  function test_filter_projects() {
    var list = [pa, pb, pc]
    compare(Projects.filterProjects(list, "").length, 3)
    compare(Projects.filterProjects(list, "  ").length, 3)
    compare(Projects.filterProjects(list, "AL").map(function(p) { return p.name }).join(","), "alpha")
    compare(Projects.filterProjects(list, "a").length, 3)
    compare(Projects.filterProjects(list, "zzz").length, 0)
    compare(Projects.filterProjects(undefined, "a").length, 0)
  }

  function test_choose_project_data() {
    return [
      { tag: "current wins", current: "/b", stored: "/c", expect: "/b" },
      { tag: "stored when no current", current: "", stored: "/c", expect: "/c" },
      { tag: "stale current falls to stored", current: "/gone", stored: "/c", expect: "/c" },
      { tag: "stale both fall to first", current: "/gone", stored: "/also-gone", expect: "/a" },
      { tag: "nothing given falls to first", current: undefined, stored: null, expect: "/a" }
    ]
  }

  function test_choose_project(data) {
    var chosen = Projects.chooseProject([pa, pb, pc], data.current, data.stored)
    compare(chosen ? chosen.root_path : null, data.expect)
  }

  function test_choose_project_with_no_projects_is_null() {
    compare(Projects.chooseProject([], "/a", "/a"), null)
    compare(Projects.chooseProject(undefined, "/a", "/a"), null)
  }

  function test_parse_state_result_data() {
    return [
      { tag: "path", out: '{"last_project": "/home/u/p"}\n', code: 0, expect: "/home/u/p" },
      { tag: "last line wins", out: 'noise\n{"last_project": "/x"}', code: 0, expect: "/x" },
      { tag: "null", out: '{"last_project": null}', code: 0, expect: null },
      { tag: "empty string", out: '{"last_project": ""}', code: 0, expect: null },
      { tag: "wrong type", out: '{"last_project": 5}', code: 0, expect: null },
      { tag: "nonzero exit", out: '{"last_project": "/x"}', code: 1, expect: null },
      { tag: "garbled", out: "not json", code: 0, expect: null },
      { tag: "empty", out: "", code: 0, expect: null },
      { tag: "undefined", out: undefined, code: 0, expect: null }
    ]
  }

  function test_parse_state_result(data) {
    compare(Projects.parseStateResult(data.out, data.code), data.expect)
  }
}
