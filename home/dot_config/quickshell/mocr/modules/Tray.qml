import Quickshell
import QtQuick
import Quickshell.Services.SystemTray
import "../theme"
import "../components"

// System tray module: renders StatusNotifier icons at 14px with 6px spacing.
// Click → activate. Right-click → context menu via display().

ModuleContainer {
    id: root

    property var parentBar

    // Tray hidden: Quickshell's image provider fails to render
    // StatusNotifier icons at requested sizes, producing magenta fallback
    // squares. Revisit when icon resolution is fixed upstream or when
    // a text-glyph fallback is implemented.
    visible: false
    contentItem: []
}
