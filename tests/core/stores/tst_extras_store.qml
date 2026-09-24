// tests/core/stores/tst_extras_store.qml
// `brd export`: when it runs, what it fills, what a failure leaves behind, and
// the Issues list/detail bookkeeping -- driven through App so the wiring to the
// project, board and navigation stores is exercised too.
import QtQuick
import QtTest

TestCase {
  id: tc
  name: "StoresExtrasStore"

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })
  property var pB: ({ root_path: "/home/u/b", name: "beta" })

  // Verbatim `brd export` shape: the issues carry no `blocks` and no `kind` --
  // the issue -> card blocking relation survives only on the nested `cards[]`
  // tree, as `blocked_by`. The whole export is handed to the parser, or the
  // issues' `blocks` would come back empty.
  function exportLine() {
    return JSON.stringify({ ok: true, data: {
      brd_export: 1,
      cards: roots(), documents: [], tags: [],
      issues: [
        { id: "i1", title: "Broken build", body: "It fails.", status: "open", close_reason: null,
          created_at: "2026-09-20T10:00:00+00:00", updated_at: "2026-09-24T10:00:00+00:00" },
        { id: "i2", title: "Old bug", body: "", status: "closed", close_reason: "resolved",
          created_at: "2026-09-10T10:00:00+00:00", updated_at: "2026-09-11T10:00:00+00:00" }],
      comments: [{ id: "m1c", entity_id: "m1", author: "paulo", body: "hi", created_at: "2026-09-24T09:00:00+00:00" },
                 { id: "i1c", entity_id: "i1", author: "claude", body: "looking", created_at: "2026-09-24T09:30:00+00:00" }],
      refs: [{ src_id: "i1", dst_id: "m1", origin: "explicit" }] } })
  }
  function roots() {
    return [{ id: "m1", title: "Milestone", status: "blocked", description: "d", blocked_by: ["i1"], children: [] }]
  }
  function make() {
    var comp = Qt.createComponent("../../../core/stores/App.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var app = comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
    app.projects.applyStoredState('{"last_project": null}', 0)
    app.projects.applyProjectsList([pA, pB])
    app.board.applyTreeData(roots())
    app.board.applyIssueData([{ id: "i1", title: "Broken build", status: "open" },
                              { id: "i2", title: "Old bug", status: "closed" }])
    return app
  }
  function ids(list) { return list.map(function(x) { return x.id }).join(",") }

  function test_the_export_runs_with_the_board_in_the_projects_directory() {
    var app = make(); if (!app) return
    var proc = app.extras.exportProc
    verify(proc, "exportProc exists")
    compare(proc.command.join(" "), "brd export")
    compare(proc.workingDirectory, "/home/u/a")
    compare(proc.running, true)
    proc.running = false
    app.board.dbFile.fileChanged()
    compare(proc.running, true, "a database change refetches the extras too")
    proc.running = false
    app.projects.chooseProject(pB)
    compare(proc.workingDirectory, "/home/u/b")
    compare(proc.running, true)
  }

  function test_a_parsed_export_fills_issues_comments_and_refs() {
    var app = make(); if (!app) return
    app.extras.exportProc.stdout.text = exportLine()
    app.extras.exportProc.stdout.streamFinished()
    compare(ids(app.extras.issues), "i1,i2")
    compare(app.extras.issues[0].commentCount, 1)
    compare(app.extras.issues[0].blocks.join(","), "m1", "blocks are derived from the card tree")
    compare(app.extras.commentsFor("m1").length, 1)
    compare(app.extras.commentsFor("m1")[0].body, "hi")
    compare(app.extras.commentsFor("nope").length, 0)
    compare(app.extras.extrasLoading, false)
    compare(app.projects.loadError, "", "extras never raise a board error")
  }

  function test_an_old_or_broken_brd_leaves_empty_extras_and_no_error() {
    var app = make(); if (!app) return
    var cases = ['{"ok": false, "error": {"type": "UsageError", "message": "no such command"}}',
                 "Usage: brd [OPTIONS] COMMAND", "not json", ""]
    for (var i = 0; i < cases.length; i++) {
      app.extras.applyExportResult(exportLine(), 0)
      app.extras.exportProc.stdout.text = cases[i]
      app.extras.exportProc.stdout.streamFinished()
      compare(app.extras.issues.length, 0, "case " + i)
      compare(app.projects.loadError, "", "case " + i)
    }
    app.extras.applyExportResult(exportLine(), 0)
    app.extras.exportProc.exited(2)
    compare(app.extras.issues.length, 0)
    compare(app.extras.extrasLoading, false)
    compare(app.projects.loadError, "")
  }

  function test_a_reply_for_a_project_the_user_has_left_is_dropped() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pB)
    app.extras.applyExportResult(exportLine(), 0, "/home/u/a")
    compare(app.extras.issues.length, 0, "the guard is the project the fetch was launched for")
    compare(app.extras.extrasLoading, false, "the newest run still clears the flag")
    app.extras.applyExportResult(exportLine(), 0, "/home/u/b")
    compare(app.extras.issues.length, 2)
  }

  function test_the_status_chips_and_the_search_narrow_the_list() {
    var app = make(); if (!app) return
    app.extras.applyExportResult(exportLine(), 0)
    compare(ids(app.extras.filteredIssues), "i1,i2")
    compare(app.extras.statusCounts.map(function(c) { return c.id + ":" + c.count }).join(","), "open:1,closed:1")
    app.extras.toggleIssueStatus("closed")
    compare(ids(app.extras.filteredIssues), "i2")
    app.extras.toggleIssueStatus("closed")
    compare(ids(app.extras.filteredIssues), "i1,i2", "toggling the active chip means All again")
    app.nav.searchQuery = "broken"
    compare(ids(app.extras.filteredIssues), "i1")
    app.nav.searchQuery = ""
  }

  function test_opening_an_issue_and_its_detail_links() {
    var app = make(); if (!app) return
    app.extras.applyExportResult(exportLine(), 0)
    compare(app.extras.openIssue("nope"), false)
    compare(app.extras.openIssue("i1"), true)
    compare(app.extras.selectedIssueId, "i1")
    compare(app.extras.selectedIssue.title, "Broken build")
    app.nav.viewMode = "issue"
    compare(app.extras.detailLinkList.map(function(l) { return l.section + ":" + l.id }).join(","),
            "blocks:m1,ref:m1")
    compare(app.extras.linkIndex("ref", "m1"), 1)
    compare(app.extras.linkIndex("blocks", "nope"), -1)
    compare(app.extras.issueIndexOf("i2"), 1)
    compare(app.extras.issueIndexOf("nope"), -1)
    compare(app.extras.resolvedTarget("m1").inBoard, true)
    compare(app.extras.resolvedTarget("i2").kind, "issue")
    compare(app.extras.resolvedTarget("ghost").title, "ghost")
    app.extras.restoreIssuesList()
    compare(app.extras.selectedIssueId, "")
  }

  function test_an_issue_that_leaves_the_export_asks_for_the_list_view() {
    var app = make(); if (!app) return
    app.extras.applyExportResult(exportLine(), 0)
    app.extras.openIssue("i1")
    app.nav.viewMode = "issue"
    var spy = Qt.createQmlObject('import QtTest; SignalSpy {}', tc)
    spy.target = app.extras
    spy.signalName = "listViewRequested"
    app.extras.applyExportResult(JSON.stringify({ ok: true, data: { issues: [], comments: [], refs: [] } }), 0)
    compare(spy.count, 1)
    compare(app.extras.detailLinkList.length, 0)
  }

  function test_a_project_change_clears_the_extras_and_the_filter() {
    var app = make(); if (!app) return
    app.extras.applyExportResult(exportLine(), 0)
    app.extras.toggleIssueStatus("open")
    app.extras.openIssue("i1")
    app.projects.chooseProject(pB)
    compare(app.extras.issues.length, 0)
    compare(app.extras.issueStatus, "")
    compare(app.extras.selectedIssueId, "")
    compare(app.extras.commentsFor("m1").length, 0)
    app.extras.applyExportResult(exportLine(), 0)
    app.projects.applyProjectsList([])
    compare(app.extras.issues.length, 0, "an empty registry empties the extras")
  }
}
