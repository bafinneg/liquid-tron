import QtQuick
import "../theme"
import "../components"
import "../services" as Services

// GPU usage module: hidden when nvidia-smi is unavailable.
ModuleContainer {
    id: root

    property var parentBar
    sourceActive: parentBar && parentBar.activePopoverId === "gpu"
    property int warningThreshold: 90
    property int criticalThreshold: 98
    readonly property int moduleWidth: gpuMetrics.advanceWidth + 34

    visible: Services.GpuStats.available
    implicitWidth: Services.GpuStats.available
        ? Geometry.borderWidth + root.moduleWidth + 2 * Geometry.barPaddingModule
        : 0

    moduleState: Services.GpuStats.gpuUsage >= criticalThreshold ? "critical"
               : Services.GpuStats.gpuUsage >= warningThreshold ? "warning"
               : "normal"

    TextMetrics {
        id: gpuMetrics
        font.family: Geometry.fontFamily
        font.pixelSize: Geometry.fontSize
        font.weight: Geometry.fontWeight
        text: "GPU 100%"
    }

    contentItem: [
        Item {
            width: root.moduleWidth
            height: Geometry.barHeightCenter

            Row {
                anchors.fill: parent
                spacing: 5

                TweenedNumber {
                    width: gpuMetrics.advanceWidth
                    value: Services.GpuStats.gpuUsage
                    prefix: "GPU "
                    suffix: "%"
                    padWidth: 3
                    textColor: Services.GpuStats.gpuUsage >= root.warningThreshold ? Colors.amber : Colors.cyan
                }

                Sparkline {
                    y: Math.round((parent.height - height) / 2)
                    width: 28
                    height: 13
                    points: Services.GpuStats.gpuHistory
                    lineColor: Services.GpuStats.gpuUsage >= root.warningThreshold ? Colors.amber : Colors.cyan
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.parentBar.togglePopover("gpu")
            }
        }
    ]
}
