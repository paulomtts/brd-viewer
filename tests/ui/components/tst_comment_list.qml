// tests/ui/components/tst_comment_list.qml
// The shared comments section: header, one block per comment (author, relative
// time, wrapped plain-text body), oldest first, and the empty line.
import QtQuick
import QtTest
import "../../helpers/find.js" as H

TestCase {
  id: tc
  name: "CommentList"
  when: windowShown
  visible: true
  width: 400; height: 500

  Component { id: hostC; Item { width: 400; height: 500 } }

  property double now: Date.parse("2026-09-24T12:00:00+00:00")
  property var comments: [
    { id: "c1", author: "claude", body: "first thing", createdAt: "2026-09-24T09:00:00+00:00" },
    { id: "c2", author: "", body: "second\nthing", createdAt: "bogus" }
  ]

  function make(list) {
    var host = createTemporaryObject(hostC, tc)
    var comp = Qt.createComponent("../../../ui/components/CommentList.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    return comp.createObject(host, { width: 400, comments: list, nowMs: tc.now })
  }

  function test_each_comment_is_one_block_oldest_first() {
    var list = make(tc.comments); if (!list) return
    compare(H.find(list, "commentAuthor0").text, "claude")
    compare(H.find(list, "commentTime0").text, "3h ago")
    compare(H.find(list, "commentBody0").text, "first thing")
    compare(H.find(list, "commentBody1").text, "second\nthing")
    compare(H.find(list, "commentBody1").wrapMode, Text.WordWrap)
    compare(H.find(list, "commentBody1").textFormat, Text.PlainText, "a comment is never rendered as markup")
  }

  function test_a_missing_author_or_time_degrades_to_plain_text() {
    var list = make(tc.comments); if (!list) return
    compare(H.find(list, "commentAuthor1").text, "unknown")
    compare(H.find(list, "commentTime1").text, "bogus")
  }

  function test_no_comments_shows_one_line_and_no_rows() {
    var list = make([]); if (!list) return
    compare(H.find(list, "commentsEmpty").visible, true)
    compare(H.find(list, "commentsEmpty").text, "No comments.")
    compare(H.find(list, "commentRow0"), null)
  }
}
