// tests/core/domain/tst_documents.qml
import QtQuick
import QtTest
import "../../../core/domain/documents.js" as Documents

TestCase {
  name: "DomainDocuments"

  property var docList: [
    { path: "README.md", title: "Readme", size: 10 },
    { path: "docs/specs/Design.md", title: "Sidebar design", size: 20 },
    { path: "docs/plan.md", title: "Plan", size: 30 }
  ]

  function test_filter_docs_matches_title_and_path() {
    compare(Documents.filterDocs(docList, "").length, 3)
    compare(Documents.filterDocs(docList, "sidebar").map(function(d) { return d.path }).join(","), "docs/specs/Design.md")
    compare(Documents.filterDocs(docList, "DOCS/").length, 2)
    compare(Documents.filterDocs(docList, "zzz").length, 0)
    compare(Documents.filterDocs(undefined, "a").length, 0)
  }

  function test_parse_docs_result_success() {
    var r = Documents.parseDocsResult('{"ok": true, "docs": [{"path": "README.md", "title": "T", "size": 1}], "truncated": true}\n', 0)
    compare(r.ok, true)
    compare(r.docs.length, 1)
    compare(r.truncated, true)
    compare(r.error, "")
  }

  function test_parse_docs_result_failures_carry_a_message() {
    var h = Documents.parseDocsResult('{"ok": false, "error": "nope"}', 1)
    compare(h.ok, false); compare(h.error, "nope"); compare(h.docs.length, 0)
    var g = Documents.parseDocsResult("garbage", 0)
    compare(g.ok, false); compare(g.error, "Could not list documents.")
    compare(Documents.parseDocsResult("", 1).ok, false)
    compare(Documents.parseDocsResult(undefined, 0).ok, false)
    compare(Documents.parseDocsResult('{"ok": true, "docs": []}', 1).ok, false)
  }

  function test_parse_docs_result_defaults() {
    var r = Documents.parseDocsResult('{"ok": true}', 0)
    compare(r.ok, true); compare(r.docs.length, 0); compare(r.truncated, false)
  }

  function test_doc_absolute_path() {
    compare(Documents.docAbsolutePath("/home/u/p", "docs/a b.md"), "/home/u/p/docs/a b.md")
    compare(Documents.docAbsolutePath("/home/u/p/", "README.md"), "/home/u/p/README.md")
  }

  function test_doc_too_large() {
    compare(Documents.MAX_DOC_BYTES, 1048576)
    compare(Documents.docTooLarge(1048576), false)
    compare(Documents.docTooLarge(1048577), true)
    compare(Documents.docTooLarge(0), false)
  }

  // ---- document categories -------------------------------------------------

  property var catDocs: [
    { path: "docs/architecture/a.md", title: "Arch", size: 1, category: "architecture" },
    { path: "docs/specs/s1.md", title: "Spec one", size: 1, category: "specs" },
    { path: "docs/superpowers/specs/s2.md", title: "Spec two", size: 1, category: "specs" },
    { path: "docs/audits/u.md", title: "Audit", size: 1, category: "audits" }
  ]

  function test_doc_categories_are_fixed_and_ordered() {
    compare(Documents.DOC_CATEGORIES.map(function(c) { return c.id }).join(","), "architecture,specs,standards,audits,other")
    compare(Documents.DOC_CATEGORIES.map(function(c) { return c.label }).join(","), "Architecture,Specs,Standards,Audits,Other")
    compare(Documents.docCategoryLabel("specs"), "Specs")
    compare(Documents.docCategoryLabel("nope"), "")
  }

  function test_filter_docs_by_category() {
    compare(Documents.filterDocsByCategory(catDocs, "").length, 4)
    compare(Documents.filterDocsByCategory(catDocs, undefined).length, 4)
    compare(Documents.filterDocsByCategory(catDocs, "specs").map(function(d) { return d.title }).join(","), "Spec one,Spec two")
    compare(Documents.filterDocsByCategory(catDocs, "audits").length, 1)
    compare(Documents.filterDocsByCategory(catDocs, "unknown").length, 0)
    compare(Documents.filterDocsByCategory(undefined, "specs").length, 0)
  }

  function test_doc_category_counts_in_display_order() {
    var counts = Documents.docCategoryCounts(catDocs)
    compare(counts.map(function(c) { return c.id + ":" + c.count }).join(","), "architecture:1,specs:2,audits:1")
    compare(counts[1].label, "Specs")
  }

  function test_doc_category_counts_hide_empty_categories() {
    var counts = Documents.docCategoryCounts([catDocs[3], catDocs[3]])
    compare(counts.length, 1)
    compare(counts[0].id, "audits")
    compare(counts[0].count, 2)
    compare(Documents.docCategoryCounts([]).length, 0)
    compare(Documents.docCategoryCounts(undefined).length, 0)
  }

  function test_doc_category_counts_ignore_docs_with_an_unknown_category() {
    var counts = Documents.docCategoryCounts([{ path: "x.md", title: "X", size: 1, category: "weird" }, catDocs[0]])
    compare(counts.length, 1)
    compare(counts[0].id, "architecture")
  }

  function test_doc_category_colors() {
    compare(Documents.docCategoryColor("architecture", "#111111"), "#b39ddb")
    compare(Documents.docCategoryColor("specs", "#111111"), "#5fa8d3")
    compare(Documents.docCategoryColor("audits", "#111111"), "#e2c15a")
    compare(Documents.docCategoryColor("weird", "#111111"), "#111111")
    compare(Documents.docCategoryColor(undefined, "#111111"), "#111111")
  }

  function test_standards_and_other_are_categories() {
    compare(Documents.docCategoryLabel("standards"), "Standards")
    compare(Documents.docCategoryLabel("other"), "Other")
    var docs = [{ category: "other" }, { category: "standards" }, { category: "audits" }, { category: "architecture" }]
    compare(Documents.docCategoryCounts(docs).map(function(c) { return c.id }).join(","),
      "architecture,standards,audits,other")
    compare(Documents.docCategoryColor("standards", "#111111"), "#4db6ac")
    compare(Documents.docCategoryColor("other", "#111111"), "#111111")
  }

  function test_strip_frontmatter_hides_a_leading_yaml_block() {
    compare(Documents.stripFrontmatter("---\ntag: spec\n---\n# Title\nbody"), "# Title\nbody")
    compare(Documents.stripFrontmatter("---\r\ntag: spec\r\n---\r\nbody"), "body")
    compare(Documents.stripFrontmatter("# Title\n---\nnot front\n---\n"), "# Title\n---\nnot front\n---\n")
    compare(Documents.stripFrontmatter("---\ntag: spec\nnever closed"), "---\ntag: spec\nnever closed")
    compare(Documents.stripFrontmatter(""), "")
    compare(Documents.stripFrontmatter(undefined), "")
  }

  function test_parse_tag_result() {
    var ok = Documents.parseTagResult('{"ok": true, "changed": true}\n', 0)
    compare(ok.ok, true)
    var bad = Documents.parseTagResult('{"ok": false, "error": "nope"}', 1)
    compare(bad.ok, false)
    compare(bad.error, "nope")
    compare(Documents.parseTagResult("", 1).error, "Could not change the document type.")
    compare(Documents.parseTagResult("garbage", 0).ok, false)
    compare(Documents.parseTagResult('{"ok": true}', 1).ok, false)
  }
}
