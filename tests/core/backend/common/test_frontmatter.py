import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), *[".."] * 4, "core", "backend"))
from common import frontmatter as fm


def test_split_returns_front_and_body_lines():
    assert fm.split("---\ntag: spec\n---\n# T\nbody\n") == (["tag: spec"], ["# T", "body"])


def test_split_without_a_block_or_with_an_unclosed_one_has_no_front():
    assert fm.split("# T\n") == ([], ["# T"])
    assert fm.split("---\ntag: spec\n# T\n") == ([], ["---", "tag: spec", "# T"])
    assert fm.split("") == ([], [])


def test_split_only_treats_a_leading_fence_as_frontmatter():
    text = "# T\n---\ntag: spec\n---\n"
    assert fm.split(text)[0] == []


def test_split_handles_crlf_and_padded_fences():
    assert fm.split("---\r\ntag: spec\r\n--- \r\nbody\r\n") == (["tag: spec"], ["body"])


def test_value_reads_a_key_case_insensitively():
    assert fm.value(["Tag: spec"], "tag") == "spec"
    assert fm.value(["tag: spec"], "TAG") == "spec"


def test_value_strips_quotes_and_trailing_comments():
    assert fm.value(['tag: "spec"'], "tag") == "spec"
    assert fm.value(["tag: 'audit'"], "tag") == "audit"
    assert fm.value(["tag: standard  # why"], "tag") == "standard"
    assert fm.value(['tag: " spec "'], "tag") == "spec"


def test_value_is_none_when_the_key_is_absent():
    assert fm.value(["title: x", "tagline: y"], "tag") is None
    assert fm.value([], "tag") is None


def test_set_key_replaces_an_existing_line_keeping_other_lines():
    out = fm.set_key("---\ntitle: x\ntag: audit\nz: 1\n---\nbody\n", "tag", "spec")
    assert out == "---\ntitle: x\ntag: spec\nz: 1\n---\nbody\n"


def test_set_key_appends_to_an_existing_block():
    assert fm.set_key("---\ntitle: x\n---\nbody\n", "tag", "spec") == "---\ntitle: x\ntag: spec\n---\nbody\n"


def test_set_key_creates_a_block_when_there_is_none():
    assert fm.set_key("# T\n", "tag", "spec") == "---\ntag: spec\n---\n# T\n"


def test_set_key_creates_a_block_before_an_unclosed_one():
    out = fm.set_key("---\ntag: x\n# T\n", "tag", "spec")
    assert out == "---\ntag: spec\n---\n---\ntag: x\n# T\n"


def test_set_key_none_removes_the_key():
    assert fm.set_key("---\ntitle: x\ntag: spec\n---\nb\n", "tag", None) == "---\ntitle: x\n---\nb\n"


def test_set_key_none_drops_an_emptied_block():
    assert fm.set_key("---\ntag: spec\n---\n# T\n", "tag", None) == "# T\n"


def test_set_key_none_without_a_key_or_block_is_unchanged():
    assert fm.set_key("# T\n", "tag", None) == "# T\n"
    assert fm.set_key("---\ntitle: x\n---\nb\n", "tag", None) == "---\ntitle: x\n---\nb\n"


def test_set_key_preserves_crlf():
    assert fm.set_key("---\r\ntag: a\r\n---\r\nb\r\n", "tag", "spec") == "---\r\ntag: spec\r\n---\r\nb\r\n"
    assert fm.set_key("# T\r\n", "tag", "spec") == "---\r\ntag: spec\r\n---\r\n# T\r\n"
    assert fm.set_key("---\r\ntitle: x\r\n---\r\n", "tag", "spec") == "---\r\ntitle: x\r\ntag: spec\r\n---\r\n"


def test_set_key_collapses_duplicate_keys_to_one():
    out = fm.set_key("---\ntag: a\ntitle: x\ntag: b\n---\n", "tag", "spec")
    assert out == "---\ntag: spec\ntitle: x\n---\n"
    assert fm.set_key("---\ntag: a\ntag: b\ntitle: x\n---\n", "tag", None) == "---\ntitle: x\n---\n"


def test_set_key_matches_the_key_case_insensitively():
    assert fm.set_key("---\nTAG: a\n---\nb\n", "tag", "spec") == "---\ntag: spec\n---\nb\n"


def test_set_key_leaves_the_rest_of_the_file_byte_for_byte():
    body = "# T\n\nline  \n\n---\nnot front\n"
    assert fm.set_key("---\ntag: a\n---\n" + body, "tag", "spec").endswith("---\n" + body)
