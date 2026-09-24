"""Layer rule, shell-type name clashes, and duplicated-helper detection."""
import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

SHELL_UI = Path("/usr/share/omarchy/shell/Ui")
CONTROLS = {"Button", "Label", "TextField", "TextArea", "Dialog", "Popup", "Frame", "Pane", "Page",
            "Switch", "Slider", "ScrollBar", "ScrollView", "CheckBox", "ComboBox", "Menu", "Drawer",
            "GroupBox", "ToolTip", "ToolBar", "TabBar", "Tumbler", "SpinBox", "RadioButton", "Control"}
# Fallback so the test also works where the shell is not installed.
SHELL_FALLBACK = {"BarIconButton", "BarIndicator", "BarWidget", "BorderOverlay", "BorderSurface", "ButtonGroup",
                  "Button", "ConfirmDialog", "CursorSurface", "Dropdown", "KeyboardPanel", "MultiSelect",
                  "NumberField", "OpticalGlyph", "PanelActionButton", "PanelController", "PanelHero",
                  "PanelKeyCatcher", "PanelSectionHeader", "PanelSeparator", "PanelSlider", "PanelToolTip",
                  "PluginBarApi", "PointerMoveGate", "PopupCard", "ScreenMoveRemap", "SearchableDropdown",
                  "SpeedTestOverlay", "TextField", "Toggle", "ToggleSwitch", "WidgetButton"}
# The manifest entry point must be called Panel.qml, which the shell also has; that one clash is known and works.
ALLOWED_CLASH = {"Panel"}

SOURCE_DIRS = ["core", "ui", "vendor"]


def source_files(*suffixes):
    files = []
    for top in SOURCE_DIRS:
        for path in (ROOT / top).rglob("*") if (ROOT / top).exists() else []:
            if path.suffix in suffixes and "__pycache__" not in path.parts:
                files.append(path)
    # today's flat layout
    for path in ROOT.glob("*"):
        if path.is_file() and path.suffix in suffixes:
            files.append(path)
    return files


def shell_type_names():
    names = {p.stem for p in SHELL_UI.glob("*.qml")} if SHELL_UI.exists() else set()
    return names | SHELL_FALLBACK | CONTROLS


def test_no_local_qml_type_shares_a_name_with_a_shell_or_controls_type():
    clashes = sorted(p.name for p in source_files(".qml")
                     if p.stem in shell_type_names() and p.stem not in ALLOWED_CLASH)
    assert clashes == []


IMPORT_RE = re.compile(r'^\s*(?:\.?import)\s+(?:"([^"]+)"|([\w.]+))', re.M)

CORE_DOMAIN_FORBIDDEN = re.compile(r"^\s*import\s+(Qt|Quickshell|qs\.)", re.M)
CORE_STORES_FORBIDDEN = re.compile(r"^\s*import\s+(QtQuick|qs\.Ui|qs\.Commons)", re.M)


def test_core_never_imports_anything_visual():
    for path in source_files(".js", ".qml"):
        rel = path.relative_to(ROOT).as_posix()
        text = path.read_text()
        if rel.startswith("core/domain/"):
            assert not CORE_DOMAIN_FORBIDDEN.search(text), rel
            assert '.qml' not in " ".join(m[0] for m in IMPORT_RE.findall(text)), rel
        if rel.startswith("core/stores/"):
            assert not CORE_STORES_FORBIDDEN.search(text), rel
            for target in (m[0] for m in IMPORT_RE.findall(text) if m[0]):
                assert not target.lstrip("./").startswith(("ui/", "vendor/canvas/Canvas")), (rel, target)
        if rel.startswith("core/backend/"):
            assert path.suffix != ".qml", rel


DUPLICATED_PY = ["def emit(", "def inside(", "def write_atomic(", "def split_frontmatter(", "def frontmatter_of("]


def test_shared_python_helpers_are_defined_once():
    seen = {}
    for path in source_files(".py"):
        text = path.read_text()
        for needle in DUPLICATED_PY:
            if needle in text:
                seen.setdefault(needle, []).append(path.relative_to(ROOT).as_posix())
    # STRICT_AFTER_TASK_5: while helpers are still being ported this only records the state; the
    # strict branch turns on once the ported domain folders exist (core/backend/memories).
    if (ROOT / "core" / "backend" / "memories").exists():
        assert all(len(v) == 1 for v in seen.values()), seen
