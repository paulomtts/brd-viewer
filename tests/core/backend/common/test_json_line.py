import io, json, os, sys
from contextlib import redirect_stdout
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), *[".."] * 4, "core", "backend"))
from common import json_line


def test_emit_prints_one_json_line_and_returns_the_code():
    buf = io.StringIO()
    with redirect_stdout(buf):
        assert json_line.emit({"ok": True}, 3) == 3
    assert buf.getvalue() == '{"ok": true}\n'
    assert json.loads(buf.getvalue()) == {"ok": True}


def test_emit_defaults_to_code_zero():
    with redirect_stdout(io.StringIO()):
        assert json_line.emit({"ok": False}) == 0
