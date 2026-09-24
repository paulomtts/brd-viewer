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

QML_IMPORT_RE = re.compile(r'^\s*import\s+(?:"([^"]+)"|([\w.]+))(?:\s+[\d.]+)?(?:\s+as\s+\w+)?\s*;?\s*$')
JS_IMPORT_RE = re.compile(r'^\s*\.import\s+"([^"]+)"\s+as\s+\w+\s*;?\s*$')
JS_PRAGMA_RE = re.compile(r"^\s*\.pragma\s+library\s*$")
IMPORTISH_RE = re.compile(r"^\s*\.?(?:import|pragma)\b")

STORE_MODULES = {"QtQml", "Quickshell", "Quickshell.Io"}


def resolve(path, target):
    return Path(os.path.normpath(path.parent / target))


def violations_domain(path, text, root=ROOT):
    """core/domain/*.js: only `.pragma library` and `.import "x.js" as X` into core/domain or vendor/canvas."""
    bad = []
    for line in text.splitlines():
        if not IMPORTISH_RE.match(line):
            continue
        if JS_PRAGMA_RE.match(line):
            continue
        m = JS_IMPORT_RE.match(line)
        if not m or not m.group(1).endswith(".js"):
            bad.append(line.strip())
            continue
        target = resolve(path, m.group(1))
        if not any(str(target).startswith(str(root / d) + os.sep) for d in ("core/domain", "vendor/canvas")):
            bad.append(line.strip())
    return bad


def violations_store(path, text, root=ROOT):
    """core/stores/*.qml: QtQml, Quickshell, Quickshell.Io and "../domain/x.js" only."""
    bad = []
    for line in text.splitlines():
        if not IMPORTISH_RE.match(line):
            continue
        m = QML_IMPORT_RE.match(line)
        if not m:
            bad.append(line.strip())
        elif m.group(2):
            if m.group(2) not in STORE_MODULES:
                bad.append(line.strip())
        else:
            target = resolve(path, m.group(1))
            if not (target.suffix == ".js" and target.parent == root / "core" / "domain"):
                bad.append(line.strip())
    return bad


def violations_screen(path, text, root=ROOT):
    """ui/screens/**: no import of core/stores (screens get `app` injected)."""
    bad = []
    for line in text.splitlines():
        m = QML_IMPORT_RE.match(line)
        if m and m.group(1) and str(resolve(path, m.group(1))).startswith(str(root / "core" / "stores")):
            bad.append(line.strip())
    return bad


def violations_vendor(path, text, root=ROOT):
    """vendor/**: no import of core/ or ui/."""
    bad = []
    for line in text.splitlines():
        m = QML_IMPORT_RE.match(line) or JS_IMPORT_RE.match(line)
        if m and m.group(1):
            target = resolve(path, m.group(1))
            if any(str(target).startswith(str(root / d)) for d in ("core", "ui")):
                bad.append(line.strip())
    return bad


def test_import_rule_regexes_flag_and_accept_what_they_should():
    d = ROOT / "core/domain/x.js"
    assert violations_domain(d, ".pragma library\n.import \"y.js\" as Y\n") == []
    assert violations_domain(d, '.import "../../vendor/canvas/layout.js" as L') == []
    assert violations_domain(d, "import QtQuick") != []
    assert violations_domain(d, "import qs.Commons") != []
    assert violations_domain(d, '.import "../stores/App.qml" as A') != []
    assert violations_domain(d, '.import "../../ui/x.js" as A') != []
    assert violations_domain(d, ".pragma nonshared") != []
    s = ROOT / "core/stores/S.qml"
    assert violations_store(s, 'import QtQml\nimport Quickshell\nimport Quickshell.Io\nimport "../domain/x.js" as X') == []
    for evil in ["import QtQuick", "import QtQuick.Layouts", "import qs.Ui", 'import "../../ui/components" as C',
                 'import "../../vendor/canvas" as V', 'import "." as Sib', 'import "../domain/y.qml" as Q',
                 "import Quickshell.Widgets"]:
        assert violations_store(s, evil) != [], evil
    sc = ROOT / "ui/screens/S.qml"
    assert violations_screen(sc, 'import "../../core/stores" as Core') != []
    assert violations_screen(sc, 'import "../../core/domain/board.js" as Board\nimport "../components" as UI') == []
    v = ROOT / "vendor/canvas/V.qml"
    assert violations_vendor(v, 'import "../../core/domain/x.js" as X') != []
    assert violations_vendor(v, 'import "../../ui/theme" as T') != []
    assert violations_vendor(v, 'import "positions.js" as P\nimport qs.Commons') == []


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
            assert path.suffix != ".qml", r
        elif r.startswith("ui/screens/"):
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
        "ui/components/Badge.qml": "shared primitive owning its caption Text (resolves the family in one place)",
        "ui/components/Chip.qml": "shared primitive owning its caption Text (resolves the family in one place)",
        "ui/components/TextAreaBox.qml": "shared primitive owning its Controls.TextArea (resolves the family in one place)",
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
