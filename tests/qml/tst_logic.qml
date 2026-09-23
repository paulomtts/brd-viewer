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
    compare(result.rows.length, 0)
  }

  function test_index_tree_builds_flat_map_and_depth_first_rows() {
    var leaf = makeCard("c2", "todo")
    var mid = makeCard("c1", "todo", [leaf])
    var root = makeCard("root", "todo", [mid])
    var result = Logic.indexTree([root])

    compare(Object.keys(result.cardMap).length, 3)
    compare(result.cardMap["c2"].id, "c2")
    compare(result.rows.length, 3)
    compare(result.rows[0].id, "root")
    compare(result.rows[0].depth, 0)
    compare(result.rows[1].id, "c1")
    compare(result.rows[1].depth, 1)
    compare(result.rows[2].id, "c2")
    compare(result.rows[2].depth, 2)
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
    compare(result.rows.length, 2)
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
}
