pragma Singleton
import QtQuick

// Monitor-local workspace glyphs for FEAT-workspace-split-monitor.
// The split-monitor-workspaces plugin exposes user-facing workspace numbers
// 1-3 on each focused monitor. These labels are intentionally generic rather
// than activity names from the retired summon model.
QtObject {
    function glyphFor(id) {
        switch (id) {
            case 1: return "Ⅰ"
            case 2: return "Ⅱ"
            case 3: return "Ⅲ"
            default: return ""
        }
    }

    function nameFor(id) {
        switch (id) {
            case 1: return "One"
            case 2: return "Two"
            case 3: return "Three"
            default: return "ws:" + id
        }
    }
}
