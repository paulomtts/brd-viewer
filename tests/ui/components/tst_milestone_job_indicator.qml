import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components" as UI

TestCase {
  id: tc
  name: "MilestoneJobIndicator"
  when: windowShown
  visible: true
  width: 700; height: 200

  Component { id: indicatorC; UI.MilestoneJobIndicator { width: 680 } }
  SignalSpy { id: cancels; signalName: "cancelRequested" }
  SignalSpy { id: dismissals; signalName: "dismissRequested" }

  function make(state) {
    var ind = createTemporaryObject(indicatorC, tc)
    cancels.target = ind; dismissals.target = ind
    cancels.clear(); dismissals.clear()
    ind.state = state
    wait(30)
    return ind
  }
  function click(item) { mouseClick(item, item.width / 2, item.height / 2) }

  function test_it_is_invisible_until_a_job_has_a_state() {
    var ind = createTemporaryObject(indicatorC, tc)
    compare(ind.visible, false)
    ind.state = "running"
    compare(ind.visible, true)
  }

  function test_running_spins_a_glyph_beside_the_label_the_elapsed_time_and_the_detail() {
    var ind = make("running")
    ind.elapsed = "1:07"
    ind.detail = "3 cards created"
    var spinner = H.find(ind, "milestoneSpinner")
    verify(spinner, "the spinner button")
    verify(String(spinner.iconText) !== "", "it draws a glyph")
    compare(spinner.iconSpinning, true)
    compare(spinner.enabled, false)
    compare(spinner.opacity, 1)
    compare(H.find(ind, "milestoneStatus").text, "Creating milestone…")
    compare(H.find(ind, "milestoneElapsed").text, "1:07")
    compare(H.find(ind, "milestoneElapsed").visible, true)
    compare(H.find(ind, "milestoneDetail").text, "3 cards created")
    compare(H.find(ind, "milestoneCancel").visible, true)
    compare(H.find(ind, "milestoneDismiss").visible, false)
  }

  function test_the_running_label_can_be_worded_by_the_owner() {
    var ind = make("running")
    ind.label = "Still working…"
    compare(H.find(ind, "milestoneStatus").text, "Still working…")
  }

  function test_the_elapsed_time_hides_itself_while_it_is_empty() {
    var ind = make("running")
    compare(H.find(ind, "milestoneElapsed").visible, false)
    compare(H.find(ind, "milestoneDetail").visible, false)
  }

  function test_cancel_reports_and_only_shows_while_the_job_runs() {
    var ind = make("running")
    click(H.find(ind, "milestoneCancel"))
    compare(cancels.count, 1)
    compare(dismissals.count, 0)
    ind.state = "done"
    compare(H.find(ind, "milestoneCancel").visible, false)
  }

  function test_done_says_so_in_the_success_colour_with_its_detail_and_a_dismiss() {
    var ind = make("done")
    ind.detail = "3 cards created"
    var status = H.find(ind, "milestoneStatus")
    compare(status.text, "Done")
    compare(status.color, "#7fb069")
    compare(H.find(ind, "milestoneDetail").text, "3 cards created")
    compare(H.find(ind, "milestoneDismiss").visible, true)
    compare(H.find(ind, "milestoneSpinner").visible, false)
  }

  function test_failed_says_so_in_the_urgent_colour_and_shows_the_reason() {
    var ind = make("failed")
    ind.detail = "The agent run failed."
    var status = H.find(ind, "milestoneStatus")
    compare(status.text, "Failed")
    compare(status.color, ind.theme.urgent)
    compare(H.find(ind, "milestoneDetail").text, "The agent run failed.")
    compare(H.find(ind, "milestoneSpinner").visible, false)
  }

  function test_dismiss_reports_and_only_shows_once_the_job_ended() {
    var ind = make("running")
    compare(H.find(ind, "milestoneDismiss").visible, false)
    ind.state = "failed"
    wait(30)
    click(H.find(ind, "milestoneDismiss"))
    compare(dismissals.count, 1)
    compare(cancels.count, 0)
  }

  function test_the_log_path_is_a_dim_elided_caption_that_hides_when_there_is_none() {
    var ind = make("failed")
    var log = H.find(ind, "milestoneLog")
    compare(log.visible, false)
    ind.logPath = "/home/x/.local/state/omarchy-project-manager/agent-logs/2026-run.log"
    compare(log.visible, true)
    compare(log.text, "/home/x/.local/state/omarchy-project-manager/agent-logs/2026-run.log")
    compare(log.elide, Text.ElideMiddle)
    compare(String(log.color), String(ind.theme.dim))
  }
}
