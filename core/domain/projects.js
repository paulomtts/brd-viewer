.pragma library
.import "results.js" as Results
.import "text.js" as Text

function filterProjects(projects, query) {
  return (projects || []).filter(function(p) { return Text.matchesQuery(p.name, query) })
}

// Which project the panel should show: the one already on screen if it is
// still registered, else the one remembered from last time, else the first.
function chooseProject(projects, currentPath, storedPath) {
  var list = projects || []
  if (list.length === 0) return null
  function byPath(path) {
    if (!path) return null
    for (var i = 0; i < list.length; i++) if (list[i].root_path === path) return list[i]
    return null
  }
  return byPath(currentPath) || byPath(storedPath) || list[0]
}

// viewer-state.py get: its last stdout line is {"last_project": path|null}.
// That answer carries no `ok` key, so success is the exit code plus a parse.
function parseStateResult(stdout, exitCode) {
  var result = Results.parseJsonLine(stdout, exitCode, "", false)
  if (!result.ok) return null
  var last = result.data.last_project
  return typeof last === "string" && last !== "" ? last : null
}

// The word the user has to type before a project is removed; deliberately the
// same gate the Claude Memory plugin uses for its deletes.
function isDeleteConfirmed(text) {
  return String(text === undefined || text === null ? "" : text).trim().toLowerCase() === "delete"
}

// snapshot-and-forget.py's answer (its last stdout line, a JSON object) plus
// its exit code, as { ok, snapshot, error }. Anything that isn't a clear
// success counts as a failure: a delete is never assumed to have worked.
function parseDeleteResult(stdout, exitCode) {
  var result = Results.parseJsonLine(stdout, exitCode, "Could not delete the project.")
  if (result.ok) return { ok: true, snapshot: String(result.data.snapshot || ""), error: "" }
  return { ok: false, snapshot: "", error: result.error }
}
