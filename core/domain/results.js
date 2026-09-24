.pragma library

// Every helper script answers on stdout with a single JSON object on its last
// non-empty line. This is the one place that turns (stdout, exitCode) into a
// decided result: the domain parsers build their own shapes on top of it.
//
// `ok` is true only when the process exited 0, the last line parsed into a
// plain object and -- unless `requireOk` is false -- that object says
// `"ok": true`. `error` is the payload's own message when it has a non-empty
// string one, else the caller's `generic` fallback.
function parseJsonLine(stdout, exitCode, generic, requireOk) {
  var needOk = requireOk === undefined ? true : requireOk
  var lines = String(stdout === undefined || stdout === null ? "" : stdout)
    .split("\n").filter(function(l) { return l.trim() !== "" })

  var payload = null
  if (lines.length > 0) {
    try { payload = JSON.parse(lines[lines.length - 1]) } catch (e) { payload = null }
  }
  if (payload === null || typeof payload !== "object" || Array.isArray(payload)) payload = null

  var ok = exitCode === 0 && payload !== null && (!needOk || payload.ok === true)
  if (ok) return { ok: true, data: payload, error: "" }

  var message = payload && typeof payload.error === "string" && payload.error !== ""
    ? payload.error : generic
  return { ok: false, data: payload, error: message }
}
