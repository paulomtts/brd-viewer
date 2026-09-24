// tests/core/domain/tst_taxonomy.qml
import QtQuick
import QtTest
import "../../../core/domain/taxonomy.js" as Taxonomy

TestCase {
  name: "DomainTaxonomy"

  property var kinds: Taxonomy.makeTaxonomy([
    { id: "alpha", label: "Alpha", color: "#aaaaaa" },
    { id: "beta", label: "Beta", color: "#bbbbbb" },
    { id: "other", label: "Other" }
  ])

  function test_taxonomy_exposes_ids_and_items_in_declaration_order() {
    compare(kinds.ids.join(","), "alpha,beta,other")
    compare(kinds.items.length, 3)
    compare(kinds.items[1].label, "Beta")
  }

  function test_taxonomy_label_of_a_known_and_an_unknown_id() {
    compare(kinds.label("beta"), "Beta")
    compare(kinds.label("nope"), "")
    compare(kinds.label(undefined), "")
  }

  function test_taxonomy_color_falls_back_for_unknown_ids_and_colourless_items() {
    compare(kinds.color("alpha", "#111111"), "#aaaaaa")
    compare(kinds.color("other", "#111111"), "#111111")
    compare(kinds.color("nope", "#111111"), "#111111")
    compare(kinds.color(undefined, "#111111"), "#111111")
  }

  function test_taxonomy_counts_are_in_declaration_order_and_omit_zeroes() {
    var rows = [{ kind: "beta" }, { kind: "alpha" }, { kind: "beta" }, { kind: "weird" }]
    var counts = kinds.counts(rows, "kind")
    compare(counts.map(function(c) { return c.id + ":" + c.count }).join(","), "alpha:1,beta:2")
    compare(counts[1].label, "Beta")
  }

  function test_taxonomy_counts_of_nothing() {
    compare(kinds.counts([], "kind").length, 0)
    compare(kinds.counts(undefined, "kind").length, 0)
  }

  function test_taxonomy_filter_by_id() {
    var rows = [{ kind: "beta" }, { kind: "alpha" }, { kind: "beta" }]
    compare(kinds.filter(rows, "kind", "beta").length, 2)
    compare(kinds.filter(rows, "kind", "nope").length, 0)
    compare(kinds.filter(undefined, "kind", "beta").length, 0)
  }

  function test_taxonomy_filter_with_an_empty_id_returns_everything() {
    var rows = [{ kind: "beta" }, { kind: "alpha" }]
    compare(kinds.filter(rows, "kind", "").length, 2)
    compare(kinds.filter(rows, "kind", undefined).length, 2)
    compare(kinds.filter(rows, "kind", null).length, 2)
  }

  function test_taxonomy_of_nothing_is_empty() {
    var empty = Taxonomy.makeTaxonomy(undefined)
    compare(empty.ids.length, 0)
    compare(empty.items.length, 0)
    compare(empty.label("alpha"), "")
    compare(empty.color("alpha", "#111111"), "#111111")
    compare(empty.counts([{ kind: "alpha" }], "kind").length, 0)
  }
}
