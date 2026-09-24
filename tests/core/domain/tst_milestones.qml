// tests/core/domain/tst_milestones.qml
import QtQuick
import QtTest
import "../../../core/domain/milestones.js" as Milestones

TestCase {
  name: "DomainMilestones"

  function test_run_result() {
    var r = Milestones.parseRunResult('noise\n{"ok": true, "agent": "claude", "log": "/tmp/l", "exit_code": 0, "error": null}\n', 0)
    compare(r.ok, true); compare(r.agent, "claude"); compare(r.log, "/tmp/l"); compare(r.exitCode, 0); compare(r.error, "")
    r = Milestones.parseRunResult('{"ok": false, "agent": "claude", "log": "/l", "exit_code": -15, "error": "Cancelled."}', 1)
    compare(r.ok, false); compare(r.exitCode, -15); compare(r.error, "Cancelled."); compare(r.log, "/l")
    r = Milestones.parseRunResult('{"ok": false, "agent": null, "log": null, "exit_code": null, "error": null}', 0)
    compare(r.ok, false); compare(r.agent, ""); compare(r.log, ""); compare(r.exitCode, null); verify(r.error !== "")
    r = Milestones.parseRunResult("", 0)
    compare(r.ok, false); verify(r.error !== ""); compare(r.exitCode, null)
    r = Milestones.parseRunResult('{"ok": true}', 0)
    compare(r.ok, true); compare(r.agent, "")
  }

  function test_describe_result() {
    var r = Milestones.parseDescribeResult('{"agent": "claude", "supported": true, "restricted": false, "note": "n", "installed": true, "zzz": 1}', 0)
    compare(r.agent, "claude"); compare(r.supported, true); compare(r.restricted, false)
    compare(r.note, "n"); compare(r.installed, true); compare(r.error, "")
    r = Milestones.parseDescribeResult("garbage", 0)
    compare(r.agent, ""); compare(r.supported, false); compare(r.installed, false); verify(r.error !== "")
    r = Milestones.parseDescribeResult('{"error": "bad"}', 1)
    compare(r.error, "bad"); compare(r.supported, false)
    r = Milestones.parseDescribeResult('{"agent": "x"}', 0)
    compare(r.agent, "x"); compare(r.supported, false); compare(r.note, ""); compare(r.error, "")
    r = Milestones.parseDescribeResult('{"agent": "x", "supported": true, "installed": true}', 2)
    verify(r.error !== "")
  }

  function test_agent_message() {
    compare(Milestones.agentMessage({ agent: "claude", installed: true, supported: true }), "")
    compare(Milestones.agentMessage({ agent: "", installed: false, supported: false }), "No default agent is set.")
    compare(Milestones.agentMessage({ agent: "codex", installed: false, supported: true }), "codex is not installed.")
    compare(Milestones.agentMessage({ agent: "codex", installed: true, supported: false }), "codex has no supported unattended mode.")
    compare(Milestones.agentMessage({}), "No default agent is set.")
    // Nothing has been checked yet: there is nothing to say about the agent.
    compare(Milestones.agentMessage(null), "")
    compare(Milestones.agentMessage(undefined), "")
    // The check itself failed (or the helper reported a reason): say that,
    // rather than blaming a missing default agent.
    compare(Milestones.agentMessage({ agent: "", installed: false, supported: false, error: "Could not check the default agent." }),
      "Could not check the default agent.")
    compare(Milestones.agentMessage({ agent: "claude", installed: true, supported: true, error: "omarchy-default-agent failed." }),
      "omarchy-default-agent failed.")
  }

  function test_format_elapsed() {
    compare(Milestones.formatElapsed(0), "0:00")
    compare(Milestones.formatElapsed(999), "0:00")
    compare(Milestones.formatElapsed(5000), "0:05")
    compare(Milestones.formatElapsed(65000), "1:05")
    compare(Milestones.formatElapsed(3599000), "59:59")
    compare(Milestones.formatElapsed(3600000), "1:00:00")
    compare(Milestones.formatElapsed(3725000), "1:02:05")
    compare(Milestones.formatElapsed(-5), "0:00")
    compare(Milestones.formatElapsed(NaN), "0:00")
    compare(Milestones.formatElapsed(undefined), "0:00")
  }

  property var docs: [
    { path: "b/zeta.md", title: "Zeta", category: "other" },
    { path: "specs/B.md", title: "Bee", category: "specs" },
    { path: "a/alpha.md", title: "Alpha", category: "other" },
    { path: "specs/a.md", title: "Ay", category: "specs" }
  ]

  function test_spec_choices() {
    var out = Milestones.specChoices(docs)
    compare(out.map(function(d) { return d.path }).join(","), "specs/a.md,specs/B.md,a/alpha.md,b/zeta.md")
    verify(out !== docs)
    compare(docs[0].path, "b/zeta.md")
    compare(Milestones.specChoices([]).length, 0)
    compare(Milestones.specChoices(undefined).length, 0)
    var same = [{ path: "x", title: "1", category: "specs" }, { path: "X", title: "2", category: "specs" }]
    compare(Milestones.specChoices(same).map(function(d) { return d.title }).join(","), "1,2")
  }

  function test_filter_spec_choices() {
    compare(Milestones.filterSpecChoices(docs, "").length, 4)
    compare(Milestones.filterSpecChoices(docs, "  ").length, 4)
    compare(Milestones.filterSpecChoices(docs, undefined).length, 4)
    compare(Milestones.filterSpecChoices(docs, "ALPHA").length, 1)
    compare(Milestones.filterSpecChoices(docs, "specs/").length, 2)
    compare(Milestones.filterSpecChoices(docs, "bee").length, 1)
    compare(Milestones.filterSpecChoices(docs, "nope").length, 0)
    compare(Milestones.filterSpecChoices(undefined, "a").length, 0)
  }
}
