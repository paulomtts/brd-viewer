# Issues, comments and brd documents — design

Status: proposed. Builds on the core/ vs ui/ architecture and the issue-blocker
work already on main (`BoardStore.issueMap`, `brd issue list` fetched with the
board).

## Problem

brd now tracks issues (bugs/questions that can block cards), comments (on cards
and issues), documents (registered `.md` files with a backup state and tags) and
refs. The panel shows only cards; issues appear just as a blocker row and a
graph flag. This adds three read-only views. The only board write stays card
creation (New milestone).

## Non-goals

- No writing: no opening/closing issues, no comments, no doc registration, no
  brd tags. Read-only, like the rest of the panel.
- No refs editor. Refs are shown, not managed.
- brd's tags are not merged with the plugin's own document *category* (the
  frontmatter `tag:` that set-doc-tag.py edits); they are shown side by side and
  named "brd tags" vs the category.

## Data (verified against the installed brd)

- `brd issue list` -> `[{id, title, body, status: open|closed, close_reason,
  blocks:[card ids], created_at, updated_at, comments:[…], refs:[{id, kind,
  title, origin}], referenced_by:[…]}]`. Already fetched by BoardStore.
- `brd show <card id>` -> card + `comments`, `refs`, `referenced_by`, `parent_id`.
  `brd tree` carries none of these, so card comments/refs need `brd export`
  (one call: `cards, issues, documents, comments, tags, refs`) or per-card
  `brd show`.
- `brd doc list` -> `[{id, title, source_path, source_state: ok|missing|…, tags,
  created_at, updated_at}]` (syncs backups as a side effect: it writes brd's
  backup, so it is called only when the Documents screen opens, never on the
  DB-watch refetch).
- Comment: `{id, entity_id, author, body, created_at}`.

## Design

One extra data source for all three: **`brd export`**, parsed by a new
`core/domain/brd-extras.js` (`indexComments(export)` -> entityId -> comments,
`indexRefs`, `indexDocs`). A new `ExtrasStore` (Scope, HelperRunner) fetches it
with the board (same triggers as `issueProc`: project select, DB watch,
Refresh) and exposes `commentsByEntity`, `refsByEntity`, `issues`,
`registeredDocs`. Failure or an older brd means empty extras, never an error.
Documents' `brd doc list` is a separate on-open fetch inside DocumentsStore
(it has the write side effect above).

1. **Issues screen** (sidebar item "Issues", Ctrl+5, icon from the Nerd Font;
   glyph-coverage test applies). Filterable list (reuses FilterableList/ListRow/
   Badge): open first, then closed; row = status badge, title, "blocks N cards",
   comment count. Filter chips All/Open/Closed. Enter opens an **issue detail**
   (reuses the card-detail layout): body, close reason, blocks (navigable to the
   card), refs and referenced-by (navigable when the target is a card or issue),
   comments.
2. **Blocked-card badge**: on Board rows and card detail, a card blocked by an
   open issue shows an "issue" badge next to "blocked" (data already in
   `issueMap`).
3. **Comments**: a "Comments" section on card detail and issue detail: author,
   relative time, body (plain text, wrapped, oldest first). Read-only.
4. **Documents**: rows whose file is registered in brd show a small "brd" badge
   with a warning colour when `source_state` is not `ok`, and their brd tags as
   chips; detail header shows backup state. Registered docs whose file is
   missing but backed up are listed (dimmed, "missing on disk") so the backup is
   discoverable. Matching registered docs to listed files is by
   `source_path` (relative to project root).

## Architecture

```
core/domain/brd-extras.js   parse export/doc list; pure, tested
core/stores/ExtrasStore.qml comments/refs/issues fetch (HelperRunner); App wiring
core/stores/DocumentsStore  + registeredDocs fetch on open, merge helper in documents.js
ui/screens/IssuesScreen.qml, IssueDetailScreen.qml  presentational
ui/components/CommentList.qml  shared by both detail screens
Navigator/Shortcuts/Panel  new section "issues", Ctrl+5, breadcrumbs "Issues > <title>"
```

UI rules unchanged: screens take props/signals; only Panel talks to `app`.
Sidebar order and Ctrl+N follow the screen order.

## Testing

Hermetic: fixtures of real brd JSON in domain tests; store tests with the stub
Process; component tests per screen; Panel flow test (navigate to Issues, open a
detail, follow a blocks link, Escape/breadcrumb back); a real-brd contract test
in a sandbox that opens an issue, adds a comment, registers a doc and asserts
the parsers read the real output (guards against brd shape drift). Architecture
tests stay green.

## Risks

- **Shape drift in brd** (it changed under us once): contract test above; unknown
  fields ignored; missing fields default.
- **`brd export` size** on big boards: fetched with the board on the same debounce;
  content of documents is in the export, so ExtrasStore drops `documents[].content`
  in the parser immediately. If it proves heavy, switch to `issue list` + per-card
  `brd show` on demand.
- **`brd doc list` writes brd's backup**: fetched only on Documents open.
