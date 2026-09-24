.pragma library
.import "results.js" as Results
.import "text.js" as Text

// ---- New milestone: parsing the create / run / describe helper output

function parseCreateResult(stdout, exitCode) {
  var result = Results.parseJsonLine(stdout, exitCode, "Could not create the milestone card.")
  if (result.ok) return { ok: true, id: String(result.data.id || ""), error: "" }
  return { ok: false, id: "", error: result.error }
}

function parseRunResult(stdout, exitCode) {
  var result = Results.parseJsonLine(stdout, exitCode, "The agent run failed.")
  var d = result.data || {}
  return {
    ok: result.ok,
    agent: String(d.agent || ""),
    log: String(d.log || ""),
    exitCode: typeof d.exit_code === "number" ? d.exit_code : null,
    error: result.ok ? "" : result.error
  }
}

// `--describe` has no "ok" field: it succeeds when the process exits 0 with an object.
function parseDescribeResult(stdout, exitCode) {
  var result = Results.parseJsonLine(stdout, exitCode, "Could not check the default agent.", false)
  var d = result.data || {}
  if (!result.ok) {
    return { agent: "", supported: false, restricted: false, note: "", installed: false, error: result.error }
  }
  return {
    agent: String(d.agent || ""),
    supported: d.supported === true,
    restricted: d.restricted === true,
    note: String(d.note || ""),
    installed: d.installed === true,
    error: typeof d.error === "string" ? d.error : ""
  }
}

// "" when the agent can run unattended, otherwise the reason it cannot.
function agentMessage(info) {
  var i = info || {}
  var agent = String(i.agent || "")
  if (agent === "") return "No default agent is set."
  if (i.installed !== true) return agent + " is not installed."
  if (i.supported !== true) return agent + " has no supported unattended mode."
  return ""
}

function formatElapsed(ms) {
  var total = Math.floor(Number(ms) / 1000)
  if (!isFinite(total) || total < 0) total = 0
  var h = Math.floor(total / 3600)
  var m = Math.floor((total % 3600) / 60)
  var s = total % 60
  var ss = (s < 10 ? "0" : "") + s
  if (h > 0) return h + ":" + (m < 10 ? "0" : "") + m + ":" + ss
  return m + ":" + ss
}

// A new array: "specs" documents first, then the rest; each group by path
// (case-insensitive), ties keeping their input order.
function specChoices(docs) {
  var items = (docs || []).map(function(d, i) { return { d: d, i: i } })
  items.sort(function(a, b) {
    var ra = a.d.category === "specs" ? 0 : 1
    var rb = b.d.category === "specs" ? 0 : 1
    if (ra !== rb) return ra - rb
    var pa = String(a.d.path || "").toLowerCase()
    var pb = String(b.d.path || "").toLowerCase()
    if (pa !== pb) return pa < pb ? -1 : 1
    return a.i - b.i
  })
  return items.map(function(x) { return x.d })
}

function filterSpecChoices(list, query) {
  return (list || []).filter(function(d) {
    return Text.matchesQuery(d.title, query) || Text.matchesQuery(d.path, query)
  })
}
