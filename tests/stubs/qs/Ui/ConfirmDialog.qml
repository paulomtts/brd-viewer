import QtQuick
// Stand-in for the shell's own qs.Ui ConfirmDialog. It exists so a local
// component that reuses this name (which the real shell resolves to ITS type,
// not ours) fails in the harness instead of only when the plugin loads.
Item { property bool opened; property string message; property string cancelText; property string confirmText }
