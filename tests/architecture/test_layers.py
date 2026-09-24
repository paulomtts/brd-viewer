"""Layer rule, shell-type name clashes, and duplicated-helper detection."""
import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

SHELL_UI = Path("/usr/share/omarchy/shell/Ui")
CONTROLS = {"Button", "Label", "TextField", "TextArea", "Dialog", "Popup", "Frame", "Pane", "Page",
            "Switch", "Slider", "ScrollBar", "ScrollView", "CheckBox", "ComboBox", "Menu", "Drawer",
            "GroupBox", "ToolTip", "ToolBar", "TabBar", "Tumbler", "SpinBox", "RadioButton", "Control",
            "ItemDelegate", "MenuItem", "ToolButton", "TabButton", "ProgressBar", "BusyIndicator", "RangeSlider",
            "Dial", "StackView", "SwipeView", "SplitView", "DelayButton", "RoundButton", "ScrollIndicator",
            "ToolSeparator", "CheckDelegate", "RadioDelegate", "SwitchDelegate", "SwipeDelegate", "MenuBar",
            "MenuBarItem", "MenuSeparator", "HorizontalHeaderView", "VerticalHeaderView", "TableView", "TreeView",
            "Item", "Text", "Rectangle", "Image", "Canvas", "Shape", "Loader", "Repeater", "Column", "Row",
            "Flow", "Grid", "Flickable", "MouseArea", "Timer", "Behavior", "Component"}
# Fallback so the test also works where the shell is not installed.
SHELL_FALLBACK = {"BarIconButton", "BarIndicator", "BarWidget", "BorderOverlay", "BorderSurface", "ButtonGroup",
                  "Button", "ConfirmDialog", "CursorSurface", "Dropdown", "KeyboardPanel", "MultiSelect",
                  "NumberField", "OpticalGlyph", "PanelActionButton", "PanelController", "PanelHero",
                  "PanelKeyCatcher", "PanelSectionHeader", "PanelSeparator", "PanelSlider", "PanelToolTip",
                  "PluginBarApi", "PointerMoveGate", "PopupCard", "ScreenMoveRemap", "SearchableDropdown",
                  "SpeedTestOverlay", "TextField", "Toggle", "ToggleSwitch", "WidgetButton"}
# Documented clashes; every entry says why it is safe.
ALLOWED_CLASH = {
    "Panel": "manifest entry point; the shell loads it by path, not by type name",
    "Canvas": "vendored canvas plugin's own component; always used qualified (Local.Canvas), see vendor/canvas/VENDORED.md",
}

SOURCE_DIRS = ["core", "ui", "vendor"]
ROOT_SOURCE_ALLOWED = {"install.sh"}


def source_files(*suffixes):
    files = []
    for top in SOURCE_DIRS:
        for path in (ROOT / top).rglob("*") if (ROOT / top).exists() else []:
            if path.suffix in suffixes and "__pycache__" not in path.parts:
                files.append(path)
    return files


def rel(path):
    return path.relative_to(ROOT).as_posix()


def shell_type_names():
    names = {p.stem for p in SHELL_UI.glob("*.qml")} if SHELL_UI.exists() else set()
    return names | SHELL_FALLBACK | CONTROLS


def test_repo_root_holds_no_source_files_and_the_layers_exist():
    for top in SOURCE_DIRS:
        assert (ROOT / top).is_dir(), top
    stray = sorted(p.name for p in ROOT.iterdir()
                   if p.is_file() and p.suffix in {".qml", ".js", ".py"} and p.name not in ROOT_SOURCE_ALLOWED)
    assert stray == []


def test_no_local_qml_type_shares_a_name_with_a_shell_or_controls_type():
    clashes = sorted(rel(p) for p in source_files(".qml")
                     if p.stem in shell_type_names() and p.stem not in ALLOWED_CLASH)
    assert clashes == []


def test_clash_allowlist_is_explained_and_canvas_is_only_used_qualified():
    assert all(why for why in ALLOWED_CLASH.values())
    unqualified = re.compile(r"(?<![.\w])Canvas\s*\{")
    for path in source_files(".qml"):
        if rel(path).startswith("vendor/"):
            continue
        assert not unqualified.search(path.read_text()), rel(path)


# ---- import rules (allowlists) -------------------------------------------------------------

STORE_MODULES = {"QtQml", "Quickshell", "Quickshell.Io"}
BLOCK_COMMENT_RE = re.compile(r"/\*.*?\*/", re.S)
LINE_COMMENT_RE = re.compile(r"//.*$")
IMPORTISH_RE = re.compile(r"^\s*\.?import\b")
PRAGMA_RE = re.compile(r"^\s*\.pragma\s+library\s*$")
_QUOTED = r"(?:\"([^\"]+)\"|'([^']+)')"
IMPORT_LINE_RE = re.compile(r"^\s*(\.?)import\s+(?:" + _QUOTED + r"|([\w.]+)(?:\s+[\d.]+)?)(?:\s+as\s+\w+)?\s*;?\s*$")


def scan_imports(text):
    """Every import of a source text as (kind, value), kind in path | module | pragma | unknown.

    Comments are stripped first. A line that starts with import/.import (or .pragma) but cannot be
    classified is returned as ("unknown", line): the rules treat that as a violation (fail closed).
    """
    text = BLOCK_COMMENT_RE.sub("", text)
    found = []
    for raw in text.splitlines():
        line = LINE_COMMENT_RE.sub("", raw) if IMPORTISH_RE.match(raw) or raw.lstrip().startswith(".pragma") else raw
        if PRAGMA_RE.match(line):
            found.append(("pragma", "library"))
        elif line.lstrip().startswith(".pragma"):
            found.append(("unknown", line.strip()))
        elif IMPORTISH_RE.match(line):
            m = IMPORT_LINE_RE.match(line)
            if not m:
                found.append(("unknown", line.strip()))
            elif m.group(2) or m.group(3):
                found.append(("path", m.group(2) or m.group(3)))
            else:
                found.append(("module", m.group(4)))
    return found


def resolve(path, target):
    return Path(os.path.normpath(path.parent / target))


def under(target, root, *dirs):
    return any(str(target).startswith(str(root / d) + os.sep) for d in dirs)


def violations_domain(path, text, root=ROOT):
    """core/domain/*.js: only `.pragma library` and `.import "x.js" as X` into core/domain or vendor/canvas."""
    bad = []
    for kind, value in scan_imports(text):
        if kind == "pragma":
            continue
        if kind == "path" and value.endswith(".js") and under(resolve(path, value), root, "core/domain", "vendor/canvas"):
            continue
        bad.append(value)
    return bad


def violations_store(path, text, root=ROOT):
    """core/stores/*.qml: QtQml, Quickshell, Quickshell.Io and "../domain/x.js" only."""
    bad = []
    for kind, value in scan_imports(text):
        if kind == "module" and value in STORE_MODULES:
            continue
        if kind == "path" and value.endswith(".js") and resolve(path, value).parent == root / "core" / "domain":
            continue
        bad.append(value)
    return bad


def violations_screen(path, text, root=ROOT):
    """ui/screens/** and ui/components/**: no import of core/stores (they get `app`/props injected); unparseable imports fail."""
    bad = []
    for kind, value in scan_imports(text):
        if kind == "unknown" or (kind == "path" and (resolve(path, value) == root / "core" / "stores"
                                                     or under(resolve(path, value), root, "core/stores"))):
            bad.append(value)
    return bad


def violations_vendor(path, text, root=ROOT):
    """vendor/**: no import of core/ or ui/; unparseable imports fail."""
    bad = []
    for kind, value in scan_imports(text):
        if kind == "unknown" or (kind == "path" and any(
                resolve(path, value) == root / d or under(resolve(path, value), root, d) for d in ("core", "ui"))):
            bad.append(value)
    return bad


def test_import_rule_regexes_flag_and_accept_what_they_should():
    d, s = ROOT / "core/domain/x.js", ROOT / "core/stores/S.qml"
    sc, v = ROOT / "ui/screens/S.qml", ROOT / "vendor/canvas/V.qml"
    # domain
    assert violations_domain(d, ".pragma library\n.import \"y.js\" as Y\n") == []
    assert violations_domain(d, '.import "../../vendor/canvas/layout.js" as L') == []
    assert violations_domain(d, ".import 'y.js' as Y // ok") == []
    assert violations_domain(d, '.import "y.js" as Y /* ok */') == []
    for evil in ["import QtQuick", "import QtQuick 2.15", "import qs.Commons", '.import "../stores/App.qml" as A',
                 '.import "../../ui/x.js" as A', ".pragma nonshared", ".import '../../ui/x.js' as A // c",
                 "import QtQuick as QQ", ".import y.js as Y"]:
        assert violations_domain(d, evil) != [], evil
    # stores
    assert violations_store(s, 'import QtQml\nimport Quickshell\nimport Quickshell.Io\nimport "../domain/x.js" as X') == []
    assert violations_store(s, "import QtQml // c\nimport Quickshell.Io /* c */") == []
    assert violations_store(s, "import '../domain/x.js' as X") == []
    for evil in ["import QtQuick", "import QtQuick 2.15", "import QtQuick as QQ", "import qs.Ui",
                 'import "../../ui/components" as C', 'import "../../vendor/canvas" as V', 'import "." as Sib',
                 'import "../domain/y.qml" as Q', "import Quickshell.Widgets", "import '../../ui/x' as C",
                 'import "../../ui/x" as C // c', "import QtQuick // QtQml"]:
        assert violations_store(s, evil) != [], evil
    # screens
    assert violations_screen(sc, 'import "../../core/domain/board.js" as Board\nimport "../components" as UI') == []
    assert violations_screen(sc, "import QtQuick 2.15\nimport QtQuick as QQ\nimport '../components' as UI") == []
    assert violations_screen(sc, '// import "../../core/stores" as C') == []
    assert violations_screen(sc, '/* import "../../core/stores" as C */') == []
    for evil in ['import "../../core/stores" as Core', "import '../../core/stores' as C",
                 'import "../../core/stores" as C // x', 'import "../../core/stores" as C /* x */',
                 'import "../../core/stores/App.qml" as C', "import ../../core/stores as C"]:
        assert violations_screen(sc, evil) != [], evil
    # components are prop-driven too (same rule, same scanner)
    comp = ROOT / "ui/components/C.qml"
    assert violations_screen(comp, 'import "../../core/stores" as X') != []
    assert violations_screen(comp, "import '../../core/stores/App.qml' as X // c") != []
    assert violations_screen(comp, 'import "../../core/domain/text.js" as T\nimport "../theme" as T2') == []
    # vendor
    assert violations_vendor(v, 'import "positions.js" as P\nimport qs.Commons\nimport QtQuick 2.15') == []
    for evil in ['import "../../core/domain/x.js" as X', 'import "../../ui/theme" as T', "import '../../core/x' as C",
                 'import "../../ui/theme" as T // c', '.import "../../core/domain/x.js" as X /* c */']:
        assert violations_vendor(v, evil) != [], evil


def test_core_layout_is_closed_and_layers_are_populated():
    core = ROOT / "core"
    assert sorted(p.name for p in core.iterdir() if p.name != "__pycache__") == ["backend", "domain", "stores"]
    for d in ("domain", "stores", "backend"):
        assert any(p.is_file() and "__pycache__" not in p.parts for p in (core / d).rglob("*")), d
    assert [rel(p) for p in source_files(".js", ".qml") if rel(p).startswith("core/backend/")] == []


def test_layers_import_only_what_their_allowlist_permits():
    for path in source_files(".js", ".qml", ".py"):
        r, text = rel(path), path.read_text()
        if r.startswith("core/domain/"):
            assert path.suffix == ".js", r
            assert violations_domain(path, text) == [], r
        elif r.startswith("core/stores/"):
            assert path.suffix == ".qml", r
            assert violations_store(path, text) == [], r
        elif r.startswith("core/backend/"):
            assert path.suffix not in {".qml", ".js"}, r
        elif r.startswith(("ui/screens/", "ui/components/")):
            assert violations_screen(path, text) == [], r
        elif r.startswith("vendor/"):
            assert violations_vendor(path, text) == [], r


DUPLICATED_PY = ["def emit(", "def inside(", "def write_atomic(", "def split_frontmatter(", "def frontmatter_of("]


def test_shared_python_helpers_are_defined_once():
    seen = {}
    for path in source_files(".py"):
        text = path.read_text()
        for needle in DUPLICATED_PY:
            if needle in text:
                seen.setdefault(needle, []).append(rel(path))
    assert all(len(v) == 1 for v in seen.values()), seen


# ---- duplication guards ("reuse before writing a second copy") ------------------------------
# pattern -> {file or directory prefix: why it is allowed}. Anything else is a second copy.
GUARDS = {
    r"Qt\.rgba\(0, 0, 0, 0\.55\)": {
        "ui/components/ModalCard.qml": "the one modal backdrop",
    },
    r"radius:\s*height\s*/\s*2": {
        "ui/components/Badge.qml": "pill primitive",
        "ui/components/Chip.qml": "pill primitive",
        "ui/screens/CardDetailScreen.qml": "documented: detail-panel tone pill (own tone colour and padding; not a Badge)",
    },
    r"bordered:\s*true": {
        "ui/components/ActionButton.qml": "the one bordered button",
        "vendor/canvas/": "vendored canvas controls",
        "ui/components/Sidebar.qml": "documented CursorSurface: project dropdown button",
        "ui/screens/BoardScreen.qml": "documented CursorSurface: BoardCard",
    },
    r"font\.family:": {
        "ui/components/ThemedText.qml": "the one text primitive",
        "vendor/": "vendored",
        # A Controls.TextArea, not a Text, so it cannot be a ThemedText; the one single-file exception.
        "ui/components/TextAreaBox.qml": "Controls.TextArea primitive; not a Text, cannot use ThemedText",
    },
    r"\bCursorSurface\s*\{": {
        "ui/components/ListRow.qml": "the row primitive",
        "ui/components/Sidebar.qml": "documented: project button, NavRow, ProjectItem",
        "ui/screens/BoardScreen.qml": "documented: BoardCard",
    },
}


def guard_hits(pattern, files):
    """files: {relpath: text}; returns the relpaths containing the pattern."""
    rx = re.compile(pattern)
    return sorted(r for r, text in files.items() if rx.search(text))


def allowed(relpath, allow):
    return any(relpath == a or (a.endswith("/") and relpath.startswith(a)) for a in allow)


def test_guard_helpers_flag_and_accept_what_they_should():
    files = {"ui/components/ModalCard.qml": "color: Qt.rgba(0, 0, 0, 0.55)",
             "ui/screens/X.qml": "color: Qt.rgba(0, 0, 0, 0.55)", "ui/screens/Y.qml": "color: Qt.rgba(0, 0, 0, 0.5)"}
    hits = guard_hits(next(iter(GUARDS)), files)
    assert hits == ["ui/components/ModalCard.qml", "ui/screens/X.qml"]
    assert [h for h in hits if not allowed(h, GUARDS[next(iter(GUARDS))])] == ["ui/screens/X.qml"]
    assert allowed("vendor/canvas/CanvasControls.qml", {"vendor/canvas/": "x"})
    assert not allowed("vendor/canvasX.qml", {"vendor/canvas/": "x"})
    assert guard_hits(r"radius:\s*height\s*/\s*2", {"a.qml": "radius:height/2"}) == ["a.qml"]
    assert guard_hits(r"\bCursorSurface\s*\{", {"a.qml": "component R: CursorSurface {"}) == ["a.qml"]


def test_no_second_copy_of_shared_visual_patterns():
    files = {rel(p): p.read_text() for p in source_files(".qml")}
    for pattern, allow in GUARDS.items():
        assert all(allow.values())
        extra = [h for h in guard_hits(pattern, files) if not allowed(h, allow)]
        assert extra == [], (pattern, extra)
