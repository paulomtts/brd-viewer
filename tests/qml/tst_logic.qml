// tests/qml/tst_logic.qml
import QtQuick
import QtTest
import "../../logic.js" as Logic

TestCase {
  name: "BrdViewerLogic"

  function makeCard(id, status, children, blockedBy) {
    return {
      id: id, title: id, description: "", status: status,
      blocked_by: blockedBy || [], created_at: "", updated_at: "",
      children: children || []
    }
  }

  function test_index_tree_on_empty_forest() {
    var result = Logic.indexTree([])
    compare(Object.keys(result.cardMap).length, 0)
  }

  function test_index_tree_builds_a_flat_map_of_every_card() {
    var leaf = makeCard("c2", "todo")
    var mid = makeCard("c1", "todo", [leaf])
    var root = makeCard("root", "todo", [mid])
    var result = Logic.indexTree([root])

    compare(Object.keys(result.cardMap).length, 3)
    compare(result.cardMap["c2"].id, "c2")
    compare(result.cardMap["c1"].id, "c1")
    compare(result.cardMap["root"].id, "root")
  }

  function test_index_tree_annotates_parent_id() {
    var child = makeCard("child", "todo")
    var root = makeCard("root", "todo", [child])
    var result = Logic.indexTree([root])
    compare(result.cardMap["root"].parentId, null)
    compare(result.cardMap["child"].parentId, "root")
  }

  function test_index_tree_handles_multiple_roots() {
    var result = Logic.indexTree([makeCard("a", "todo"), makeCard("b", "todo")])
    compare(Object.keys(result.cardMap).length, 2)
    compare(result.cardMap["a"].parentId, null)
    compare(result.cardMap["b"].parentId, null)
  }

  function test_subtree_counts_on_childless_card() {
    var counts = Logic.subtreeCounts(makeCard("solo", "todo"))
    compare(counts.done, 0)
    compare(counts.total, 0)
  }

  // A card's own status must never be folded into its descendant count --
  // the parent here is "done" but every descendant is still "todo".
  function test_subtree_counts_ignores_own_status_counts_descendants_only() {
    var child = makeCard("child", "todo")
    var root = makeCard("root", "done", [child])
    var counts = Logic.subtreeCounts(root)
    compare(counts.done, 0)
    compare(counts.total, 1)
  }

  function test_subtree_counts_counts_nested_descendants_recursively() {
    var grandchild1 = makeCard("g1", "done")
    var grandchild2 = makeCard("g2", "todo")
    var child = makeCard("child", "in_progress", [grandchild1, grandchild2])
    var root = makeCard("root", "todo", [child])
    var counts = Logic.subtreeCounts(root)
    compare(counts.total, 3)
    compare(counts.done, 1)
  }

  // ---- search --------------------------------------------------------

  function test_matches_query_is_case_insensitive_substring() {
    compare(Logic.matchesQuery("Write the Parser", "parser"), true)
    compare(Logic.matchesQuery("Write the Parser", "PARSER"), true)
    compare(Logic.matchesQuery("Write the Parser", "xyz"), false)
  }

  function test_matches_query_empty_query_matches_everything() {
    compare(Logic.matchesQuery("anything", ""), true)
    compare(Logic.matchesQuery("anything", "   "), true)
  }

  function test_subtree_matches_on_own_title() {
    var card = makeCard("root", "todo")
    card.title = "Fix the parser"
    compare(Logic.subtreeMatches(card, "parser"), true)
    compare(Logic.subtreeMatches(card, "nope"), false)
  }

  // Keeping ancestors of a match visible: a non-matching root whose
  // grandchild matches must still report true.
  function test_subtree_matches_true_for_ancestor_of_a_nested_match() {
    var grandchild = makeCard("g", "todo")
    grandchild.title = "Deep task about parsers"
    var child = makeCard("c", "todo", [grandchild])
    child.title = "Middle"
    var root = makeCard("root", "todo", [child])
    root.title = "Top"
    compare(Logic.subtreeMatches(root, "parsers"), true)
    compare(Logic.subtreeMatches(child, "parsers"), true)
  }

  function test_subtree_matches_false_when_nothing_in_subtree_matches() {
    var child = makeCard("c", "todo")
    child.title = "Unrelated"
    var root = makeCard("root", "todo", [child])
    root.title = "Also unrelated"
    compare(Logic.subtreeMatches(root, "parsers"), false)
  }

  function test_subtree_matches_false_for_undefined_card() {
    compare(Logic.subtreeMatches(undefined, "x"), false)
  }

  // ---- colors, kinds, board order, detail links --------------------------

  function test_status_color_maps_known_statuses() {
    compare(Logic.statusColor("done", "#111111"), "#7fb069")
    compare(Logic.statusColor("blocked", "#111111"), "#e8954a")
    compare(Logic.statusColor("in_progress", "#111111"), "#5fa8d3")
  }

  function test_status_color_falls_back_for_todo_and_unknown() {
    compare(Logic.statusColor("todo", "#111111"), "#111111")
    compare(Logic.statusColor("weird", "#111111"), "#111111")
    compare(Logic.statusColor(undefined, "#111111"), "#111111")
  }

  function test_kind_label_by_depth() {
    compare(Logic.kindLabel(0), "Milestone")
    compare(Logic.kindLabel(1), "Story")
    compare(Logic.kindLabel(2), "Subtask")
    compare(Logic.kindLabel(7), "Subtask")
    compare(Logic.kindLabel(undefined), "Card")
    compare(Logic.kindLabel(-1), "Card")
  }

  function test_index_tree_annotates_depth() {
    var leaf = makeCard("leaf", "todo")
    var mid = makeCard("mid", "todo", [leaf])
    var root = makeCard("root", "todo", [mid])
    var map = Logic.indexTree([root]).cardMap
    compare(map["root"].depth, 0)
    compare(map["mid"].depth, 1)
    compare(map["leaf"].depth, 2)
  }

  function test_effective_status_folds_blocked_into_todo() {
    compare(Logic.effectiveStatus(makeCard("a", "blocked")), "todo")
    compare(Logic.effectiveStatus(makeCard("a", "done")), "done")
    compare(Logic.effectiveStatus(undefined), "todo")
  }

  function test_board_order_groups_by_section_in_order() {
    var a = makeCard("a", "done")
    var b = makeCard("b", "todo")
    var c = makeCard("c", "blocked")
    var d = makeCard("d", "in_progress")
    var ids = Logic.boardOrder([a, b, c, d], ["todo", "in_progress", "done"]).map(function(x) { return x.id })
    compare(ids.join(","), "b,c,d,a")
  }

  function test_board_order_empty() {
    compare(Logic.boardOrder([], ["todo", "in_progress", "done"]).length, 0)
  }

  function test_detail_links_orders_parent_blockers_children() {
    var kid = makeCard("kid", "todo")
    var dep = makeCard("dep", "todo")
    var mid = makeCard("mid", "todo", [kid], ["dep", "ghost"])
    var root = makeCard("root", "todo", [mid])
    var map = Logic.indexTree([root, dep]).cardMap
    var links = Logic.detailLinks(map["mid"], map)
    compare(links.map(function(l) { return l.section + ":" + l.id }).join(","), "parent:root,blocker:dep,child:kid")
  }

  function test_detail_links_skips_dangling_blockers_and_missing_parent() {
    var card = makeCard("c", "todo", [], ["ghost"])
    var map = Logic.indexTree([card]).cardMap
    compare(Logic.detailLinks(card, map).length, 0)
    compare(Logic.detailLinks(undefined, {}).length, 0)
  }

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
    compare(Logic.isDeleteConfirmed(data.text), data.ok)
  }

  function test_parse_delete_result_success() {
    var r = Logic.parseDeleteResult('{"ok": true, "snapshot": "/h/Snapshots/x"}\n', 0)
    compare(r.ok, true)
    compare(r.snapshot, "/h/Snapshots/x")
    compare(r.error, "")
  }

  function test_parse_delete_result_reports_the_helpers_error() {
    var r = Logic.parseDeleteResult('{"ok": false, "error": "could not snapshot"}', 1)
    compare(r.ok, false)
    compare(r.error, "could not snapshot")
  }

  function test_parse_delete_result_uses_the_last_line() {
    var r = Logic.parseDeleteResult('noise\n{"ok": true, "snapshot": "/s"}\n', 0)
    compare(r.ok, true)
  }

  function test_parse_delete_result_failure_when_exit_code_nonzero_even_if_ok_true() {
    compare(Logic.parseDeleteResult('{"ok": true, "snapshot": "/s"}', 1).ok, false)
  }

  function test_parse_delete_result_unparseable_or_empty_output() {
    compare(Logic.parseDeleteResult("", 1).ok, false)
    compare(Logic.parseDeleteResult("", 1).error, "Could not delete the project.")
    compare(Logic.parseDeleteResult("not json", 0).ok, false)
    compare(Logic.parseDeleteResult(undefined, 0).ok, false)
  }

  // ---- project selection ------------------------------------------------

  property var pa: ({ root_path: "/a", name: "alpha" })
  property var pb: ({ root_path: "/b", name: "beta" })
  property var pc: ({ root_path: "/c", name: "gamma" })

  function test_filter_projects() {
    var list = [pa, pb, pc]
    compare(Logic.filterProjects(list, "").length, 3)
    compare(Logic.filterProjects(list, "  ").length, 3)
    compare(Logic.filterProjects(list, "AL").map(function(p) { return p.name }).join(","), "alpha")
    compare(Logic.filterProjects(list, "a").length, 3)
    compare(Logic.filterProjects(list, "zzz").length, 0)
    compare(Logic.filterProjects(undefined, "a").length, 0)
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
    var chosen = Logic.chooseProject([pa, pb, pc], data.current, data.stored)
    compare(chosen ? chosen.root_path : null, data.expect)
  }

  function test_choose_project_with_no_projects_is_null() {
    compare(Logic.chooseProject([], "/a", "/a"), null)
    compare(Logic.chooseProject(undefined, "/a", "/a"), null)
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
    compare(Logic.parseStateResult(data.out, data.code), data.expect)
  }

  // ---- documents ---------------------------------------------------------

  property var docList: [
    { path: "README.md", title: "Readme", size: 10 },
    { path: "docs/specs/Design.md", title: "Sidebar design", size: 20 },
    { path: "docs/plan.md", title: "Plan", size: 30 }
  ]

  function test_filter_docs_matches_title_and_path() {
    compare(Logic.filterDocs(docList, "").length, 3)
    compare(Logic.filterDocs(docList, "sidebar").map(function(d) { return d.path }).join(","), "docs/specs/Design.md")
    compare(Logic.filterDocs(docList, "DOCS/").length, 2)
    compare(Logic.filterDocs(docList, "zzz").length, 0)
    compare(Logic.filterDocs(undefined, "a").length, 0)
  }

  function test_parse_docs_result_success() {
    var r = Logic.parseDocsResult('{"ok": true, "docs": [{"path": "README.md", "title": "T", "size": 1}], "truncated": true}\n', 0)
    compare(r.ok, true)
    compare(r.docs.length, 1)
    compare(r.truncated, true)
    compare(r.error, "")
  }

  function test_parse_docs_result_failures_carry_a_message() {
    var h = Logic.parseDocsResult('{"ok": false, "error": "nope"}', 1)
    compare(h.ok, false); compare(h.error, "nope"); compare(h.docs.length, 0)
    var g = Logic.parseDocsResult("garbage", 0)
    compare(g.ok, false); compare(g.error, "Could not list documents.")
    compare(Logic.parseDocsResult("", 1).ok, false)
    compare(Logic.parseDocsResult(undefined, 0).ok, false)
    compare(Logic.parseDocsResult('{"ok": true, "docs": []}', 1).ok, false)
  }

  function test_parse_docs_result_defaults() {
    var r = Logic.parseDocsResult('{"ok": true}', 0)
    compare(r.ok, true); compare(r.docs.length, 0); compare(r.truncated, false)
  }

  function test_doc_absolute_path() {
    compare(Logic.docAbsolutePath("/home/u/p", "docs/a b.md"), "/home/u/p/docs/a b.md")
    compare(Logic.docAbsolutePath("/home/u/p/", "README.md"), "/home/u/p/README.md")
  }

  function test_doc_too_large() {
    compare(Logic.MAX_DOC_BYTES, 1048576)
    compare(Logic.docTooLarge(1048576), false)
    compare(Logic.docTooLarge(1048577), true)
    compare(Logic.docTooLarge(0), false)
  }

  // ---- document categories -------------------------------------------------

  property var catDocs: [
    { path: "docs/architecture/a.md", title: "Arch", size: 1, category: "architecture" },
    { path: "docs/specs/s1.md", title: "Spec one", size: 1, category: "specs" },
    { path: "docs/superpowers/specs/s2.md", title: "Spec two", size: 1, category: "specs" },
    { path: "docs/audits/u.md", title: "Audit", size: 1, category: "audits" }
  ]

  function test_doc_categories_are_fixed_and_ordered() {
    compare(Logic.DOC_CATEGORIES.map(function(c) { return c.id }).join(","), "architecture,specs,audits")
    compare(Logic.DOC_CATEGORIES.map(function(c) { return c.label }).join(","), "Architecture,Specs,Audits")
    compare(Logic.docCategoryLabel("specs"), "Specs")
    compare(Logic.docCategoryLabel("nope"), "")
  }

  function test_filter_docs_by_category() {
    compare(Logic.filterDocsByCategory(catDocs, "").length, 4)
    compare(Logic.filterDocsByCategory(catDocs, undefined).length, 4)
    compare(Logic.filterDocsByCategory(catDocs, "specs").map(function(d) { return d.title }).join(","), "Spec one,Spec two")
    compare(Logic.filterDocsByCategory(catDocs, "audits").length, 1)
    compare(Logic.filterDocsByCategory(catDocs, "unknown").length, 0)
    compare(Logic.filterDocsByCategory(undefined, "specs").length, 0)
  }

  function test_doc_category_counts_in_display_order() {
    var counts = Logic.docCategoryCounts(catDocs)
    compare(counts.map(function(c) { return c.id + ":" + c.count }).join(","), "architecture:1,specs:2,audits:1")
    compare(counts[1].label, "Specs")
  }

  function test_doc_category_counts_hide_empty_categories() {
    var counts = Logic.docCategoryCounts([catDocs[3], catDocs[3]])
    compare(counts.length, 1)
    compare(counts[0].id, "audits")
    compare(counts[0].count, 2)
    compare(Logic.docCategoryCounts([]).length, 0)
    compare(Logic.docCategoryCounts(undefined).length, 0)
  }

  function test_doc_category_counts_ignore_docs_with_an_unknown_category() {
    var counts = Logic.docCategoryCounts([{ path: "x.md", title: "X", size: 1, category: "weird" }, catDocs[0]])
    compare(counts.length, 1)
    compare(counts[0].id, "architecture")
  }

  function test_doc_category_colors() {
    compare(Logic.docCategoryColor("architecture", "#111111"), "#b39ddb")
    compare(Logic.docCategoryColor("specs", "#111111"), "#5fa8d3")
    compare(Logic.docCategoryColor("audits", "#111111"), "#e2c15a")
    compare(Logic.docCategoryColor("weird", "#111111"), "#111111")
    compare(Logic.docCategoryColor(undefined, "#111111"), "#111111")
  }

  function graphRoots() {
    return [
      makeCard("m1", "done", [makeCard("s1", "done", []), makeCard("s2", "todo", [])]),
      makeCard("m2", "todo", [makeCard("s3", "todo", [])], ["m1"]),
      makeCard("m3", "blocked", [], ["m2", "ghost"]),
      makeCard("m4", "in_progress", [])
    ]
  }

  function test_graph_model_has_a_node_per_milestone_with_progress() {
    var g = Logic.graphModel(graphRoots())
    compare(g.nodes.map(function(n) { return n.id }).join(","), "m1,m2,m3,m4")
    compare(g.nodes[0].title, "m1")
    compare(g.nodes[0].status, "done")
    compare(g.nodes[0].done, 1)
    compare(g.nodes[0].total, 2)
    compare(g.nodes[2].status, "blocked")
    compare(g.nodes[3].total, 0)
  }

  function test_graph_edges_run_from_blocker_to_blocked_and_skip_unknown_ids() {
    var g = Logic.graphModel(graphRoots())
    compare(g.edges.map(function(e) { return e.from + ">" + e.to }).join(","), "m1>m2,m2>m3")
    compare(g.edges[0].id, "m1>m2")
  }

  function test_graph_nodes_are_positioned_and_sized_by_the_layout() {
    var g = Logic.graphModel(graphRoots())
    for (var i = 0; i < g.nodes.length; i++) {
      verify(isFinite(g.nodes[i].x) && isFinite(g.nodes[i].y), "node " + i)
      compare(g.nodes[i].w, Logic.GRAPH_NODE_W)
      compare(g.nodes[i].h, Logic.GRAPH_NODE_H)
    }
    verify(g.nodes[1].x > g.nodes[0].x, "blocked milestone sits to the right of its blocker")
    verify(g.nodes[2].x > g.nodes[1].x)
  }

  function test_graph_model_of_nothing_is_empty() {
    compare(Logic.graphModel([]).nodes.length, 0)
    compare(Logic.graphModel(undefined).edges.length, 0)
  }

  function test_graph_move_picks_the_nearest_node_in_the_direction() {
    var nodes = [
      { id: "a", x: 0, y: 0, w: 100, h: 50 },
      { id: "b", x: 300, y: 0, w: 100, h: 50 },
      { id: "c", x: 300, y: 200, w: 100, h: 50 },
      { id: "d", x: 600, y: 10, w: 100, h: 50 }
    ]
    compare(Logic.graphMove(nodes, "a", "right"), "b")
    compare(Logic.graphMove(nodes, "b", "right"), "d")
    compare(Logic.graphMove(nodes, "b", "left"), "a")
    compare(Logic.graphMove(nodes, "b", "down"), "c")
    compare(Logic.graphMove(nodes, "c", "up"), "b")
    compare(Logic.graphMove(nodes, "a", "left"), "a")
    compare(Logic.graphMove(nodes, "d", "down"), "c")
  }

  function test_graph_move_starts_at_the_first_node_when_nothing_is_selected() {
    var nodes = [{ id: "a", x: 0, y: 0 }, { id: "b", x: 300, y: 0 }]
    compare(Logic.graphMove(nodes, "", "right"), "a")
    compare(Logic.graphMove(nodes, "gone", "left"), "a")
    compare(Logic.graphMove([], "", "right"), "")
  }
}
