// Tron Compute — ambient selector (singleton)
// Managed by apply-theme.sh — do not edit directly.
// Source of truth: shared/themes/palettes/tron-compute.yaml `ambient:` block.
pragma Singleton
import QtQuick

QtObject {
    readonly property string variant: "nostromo-whispers"
    readonly property var monitorScope: ["DP-2", "DP-4"]
    readonly property real maxOpacity: 0.85
    readonly property int idleFps: 15
    readonly property int activeFps: 30
}
