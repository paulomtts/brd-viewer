.pragma library
.import "results.js" as Results
.import "taxonomy.js" as Taxonomy
.import "text.js" as Text

var MAX_DOC_BYTES = 1048576

// The Documents badges: a fixed set, in display order. list-docs.py assigns
// each document one of these ids. The colours are fixed hues (the shell theme
// has no palette for this), distinct from the status colours so a category
// badge never reads as a card status; "other" takes the caller's neutral one.
var DOC_TYPES = Taxonomy.makeTaxonomy([
  { id: "architecture", label: "Architecture", color: "#b39ddb" },
  { id: "specs", label: "Specs", color: "#5fa8d3" },
  { id: "standards", label: "Standards", color: "#4db6ac" },
  { id: "audits", label: "Audits", color: "#e2c15a" },
  { id: "other", label: "Other" }
])

var DOC_CATEGORIES = DOC_TYPES.items
var docCategoryLabel = DOC_TYPES.label
var docCategoryColor = DOC_TYPES.color

// An empty/undefined category means "all".
function filterDocsByCategory(docs, categoryId) {
  return DOC_TYPES.filter(docs, "category", categoryId)
}

// [{ id, label, count }] for the categories that have at least one document.
function docCategoryCounts(docs) {
  return DOC_TYPES.counts(docs, "category")
}

function filterDocs(docs, query) {
  return (docs || []).filter(function(d) {
    return Text.matchesQuery(d.title, query) || Text.matchesQuery(d.path, query)
  })
}

// list-docs.py's last stdout line plus its exit code, as
// { ok, docs, truncated, error }. Anything but a clear success is a failure.
function parseDocsResult(stdout, exitCode) {
  var result = Results.parseJsonLine(stdout, exitCode, "Could not list documents.")
  if (result.ok)
    return { ok: true, docs: Array.isArray(result.data.docs) ? result.data.docs : [],
             truncated: result.data.truncated === true, error: "" }
  return { ok: false, docs: [], truncated: false, error: result.error }
}

function docAbsolutePath(rootPath, relPath) {
  return String(rootPath).replace(/\/+$/, "") + "/" + relPath
}

function docTooLarge(size) {
  return size > MAX_DOC_BYTES
}

// Documents may open with a YAML frontmatter block (list-docs.py reads its
// `tag:`); it is metadata, so the rendered document leaves it out.
function stripFrontmatter(text) {
  var value = String(text === undefined || text === null ? "" : text)
  var m = /^---[ \t]*\r?\n[\s\S]*?\r?\n---[ \t]*(?:\r?\n|$)/.exec(value)
  return m ? value.slice(m[0].length) : value
}

// set-doc-tag.py's answer (its last stdout line) plus its exit code, as
// { ok, error }. Anything but a clear success is a failure.
function parseTagResult(stdout, exitCode) {
  var result = Results.parseJsonLine(stdout, exitCode, "Could not change the document type.")
  if (result.ok) return { ok: true, error: "" }
  return { ok: false, error: result.error }
}
