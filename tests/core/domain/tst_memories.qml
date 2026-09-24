// tests/core/domain/tst_memories.qml
import QtQuick
import QtTest
import "../../../core/domain/memories.js" as Memories

TestCase {
  name: "DomainMemories"

  property var memNotes: [
    { file: "feedback_a.md", name: "Terse replies", description: "no trailing summaries", type: "feedback", size: 10, indexed: true },
    { file: "user_role.md", name: "Role", description: "data scientist", type: "user", size: 10, indexed: true },
    { file: "notes.md", name: "Misc", description: "", type: "other", size: 10, indexed: false },
    { file: "feedback_b.md", name: "Testing", description: "real database", type: "feedback", size: 10, indexed: true }
  ]

  function test_memory_types_labels_colors() {
    compare(Memories.MEMORY_TYPES.map(function(t) { return t.id }).join(","), "user,feedback,project,reference,other")
    compare(Memories.memoryTypeLabel("feedback"), "Feedback")
    compare(Memories.memoryTypeLabel("nope"), "")
    compare(Memories.memoryTypeColor("user", "#111111"), "#d98cb3")
    compare(Memories.memoryTypeColor("other", "#111111"), "#111111")
  }

  function test_memory_type_counts_and_filters() {
    compare(Memories.memoryTypeCounts(memNotes).map(function(c) { return c.id + ":" + c.count }).join(","),
      "user:1,feedback:2,other:1")
    compare(Memories.filterMemoriesByType(memNotes, "feedback").length, 2)
    compare(Memories.filterMemoriesByType(memNotes, "").length, 4)
    compare(Memories.filterMemoriesByType(memNotes, undefined).length, 4)
    compare(Memories.filterMemoriesByType(memNotes, "project").length, 0)
  }

  function test_memory_search_matches_name_description_and_file() {
    compare(Memories.filterMemories(memNotes, "terse").length, 1)
    compare(Memories.filterMemories(memNotes, "DATABASE").length, 1)
    compare(Memories.filterMemories(memNotes, "user_role").length, 1)
    compare(Memories.filterMemories(memNotes, "  ").length, 4)
    compare(Memories.filterMemories(memNotes, "zzz").length, 0)
  }

  function test_parse_memories_result() {
    var ok = Memories.parseMemoriesResult('{"ok": true, "found": true, "memory_dir": "/m/memory", "notes": [{"file": "a.md", "name": "A", "description": "", "type": "user", "size": 1, "indexed": true}]}', 0)
    compare(ok.ok, true); compare(ok.found, true); compare(ok.memoryDir, "/m/memory"); compare(ok.notes.length, 1)
    var none = Memories.parseMemoriesResult('{"ok": true, "found": false, "memory_dir": "", "notes": []}', 0)
    compare(none.ok, true); compare(none.found, false)
    var bad = Memories.parseMemoriesResult('{"ok": false, "error": "nope"}', 1)
    compare(bad.ok, false); compare(bad.error, "nope"); compare(bad.notes.length, 0)
    compare(Memories.parseMemoriesResult("", 1).error, "Could not read this project's memories.")
    compare(Memories.parseMemoriesResult("garbage", 0).ok, false)
  }

  function test_parse_memory_op_result() {
    var ok = Memories.parseMemoryOpResult('{"ok": true, "backup": "/b"}', 0)
    compare(ok.ok, true); compare(ok.backup, "/b")
    var bad = Memories.parseMemoryOpResult('{"ok": false, "error": "exists"}', 1)
    compare(bad.ok, false); compare(bad.error, "exists")
    compare(Memories.parseMemoryOpResult("", 1).error, "Could not update the memory.")
    compare(Memories.parseMemoryOpResult('{"ok": true}', 1).ok, false)
  }

  function test_memory_absolute_path_and_new_file_names() {
    compare(Memories.memoryAbsolutePath("/m/memory", "a b.md"), "/m/memory/a b.md")
    compare(Memories.newMemoryFile("feedback", "Terse Replies!", []), "feedback_terse-replies.md")
    compare(Memories.newMemoryFile("feedback", "Terse Replies!", ["feedback_terse-replies.md"]), "feedback_terse-replies-2.md")
    compare(Memories.newMemoryFile("feedback", "Terse Replies!", ["feedback_terse-replies.md", "feedback_terse-replies-2.md"]), "feedback_terse-replies-3.md")
    compare(Memories.newMemoryFile("weird", "  ", []), "other_memory.md")
    compare(Memories.newMemoryFile("user", "../../etc/passwd", []), "user_etc-passwd.md")
    compare(Memories.newMemoryFile("project", "Ünïcode ✨ name", []), "project_n-code-name.md")
  }

  function test_compose_memory_builds_frontmatter() {
    compare(Memories.composeMemory("Terse", "no summaries", "feedback", "Body text\n"),
      "---\nname: Terse\ndescription: no summaries\nmetadata:\n  type: feedback\n---\n\nBody text\n")
    compare(Memories.composeMemory("A: b", 'say "hi" # x', "user", ""),
      '---\nname: "A: b"\ndescription: "say \\"hi\\" # x"\nmetadata:\n  type: user\n---\n\n')
    compare(Memories.composeMemory("Multi\nline", "d\r\ne", "project", "b"),
      "---\nname: Multi line\ndescription: d e\nmetadata:\n  type: project\n---\n\nb")
  }
}
