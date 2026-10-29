import QtQuick
import "../theme"

// Shared module shell: 1px fg_dark left divider, horizontal padding, and
// label-value typography. Persistent chassis chrome belongs to group wrappers,
// not individual modules.
//
// Threshold states: set moduleState to "warning" for a one-shot cyan border
// pulse, or "critical" for a sustained 1Hz red breathing border. Default
// "normal" shows no threshold border.

Item {
    id: container

    property alias contentItem: content.data
    property bool showLeftBorder: true
    // Keep the historical 1px footprint when group composition suppresses
    // divider paint. This avoids changing content and pointer geometry.
    property bool reserveLeftBorderSpace: false
    property string moduleState: "normal"  // "normal" | "warning" | "critical"
    property string visualRole: "telemetry"  // "telemetry" | "leader"; opacity only
    property real visualWeight: 0.66
    property bool sourceActive: false
    property int horizontalPadding: Geometry.barPaddingModule
    readonly property bool apertureActive: sourceActive && moduleState === "normal"

    // Quiet healthy telemetry yields hierarchy without removing data or controls.
    // A source-owned detail surface temporarily promotes only its real invoker.
    opacity: moduleState === "normal" ? (sourceActive ? 1.0 : (visualRole === "leader" ? 1.0 : visualWeight)) : 1.0

    implicitWidth: leftBorder.width + content.implicitWidth + 2 * horizontalPadding
    implicitHeight: Geometry.barHeightCenter

    // Source aperture stays inside the existing footprint; warning/critical
    // borders and module content render above it unchanged.
    Item {
        anchors.fill: parent
        visible: container.apertureActive
        z: 0

        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(Colors.bg_dark, 0.86)
            radius: 0
        }

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: Geometry.borderWidth
            color: Qt.alpha(Colors.blue, 0.24)
            radius: 0
        }

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Geometry.borderWidthAccent
            color: Qt.alpha(Colors.cyan, 0.76)
        }

        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Geometry.borderWidth
            color: Qt.alpha(Colors.blue, 0.72)
        }
    }

    // 1px fg_dark left divider (matching waybar's border-left: 1px solid #505060)
    Rectangle {
        id: leftBorder
        visible: container.showLeftBorder || container.reserveLeftBorderSpace
        width: visible ? Geometry.borderWidth : 0
        height: parent.height
        color: Colors.fg_dark
        opacity: container.showLeftBorder ? 1.0 : 0.0
        anchors.left: parent.left
        z: 2
    }

    // Content area with horizontal padding, full bar height so children
    // with height: bar.effectiveBarHeight + verticalAlignment: AlignVCenter
    // all land at the same vertical position regardless of implicitHeight.
    Item {
        id: content
        anchors.left: leftBorder.right
        anchors.leftMargin: container.horizontalPadding
        anchors.right: parent.right
        anchors.rightMargin: container.horizontalPadding
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        implicitWidth: childrenRect.width
        z: 3
    }

    // ── Threshold border overlay ─────────────────────────────
    // Separate from the left divider — this is a colored border around
    // the entire module content area for warning/critical feedback.
    Rectangle {
        id: thresholdBorder
        anchors.fill: parent
        color: "transparent"
        border.width: Geometry.borderWidth
        border.color: Qt.alpha(Colors.cyan, _thresholdAlpha)
        visible: _thresholdAlpha > 0
        z: 6

        property real _thresholdAlpha: 0
    }

    // Warning: one-shot cyan pulse on transition into "warning" state.
    SequentialAnimation {
        id: warningPulse
        PropertyAnimation {
            target: thresholdBorder; property: "_thresholdAlpha"
            to: 0.8; duration: 150
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.snap
        }
        PropertyAnimation {
            target: thresholdBorder; property: "_thresholdAlpha"
            to: 0; duration: 350
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.decay
        }
    }

    // Critical: sustained 1Hz red breathing, 30%→100% alpha sine wave.
    // ~50% duty cycle at peak luminance per OLED discipline rule 4.
    SequentialAnimation {
        id: criticalBreathing
        loops: Animation.Infinite
        NumberAnimation {
            target: thresholdBorder; property: "_thresholdAlpha"
            from: 0.3; to: 1.0; duration: 500
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: thresholdBorder; property: "_thresholdAlpha"
            from: 1.0; to: 0.3; duration: 500
            easing.type: Easing.InOutSine
        }
    }

    onModuleStateChanged: {
        warningPulse.stop()
        criticalBreathing.stop()

        if (moduleState === "warning") {
            thresholdBorder.border.color = Qt.binding(() => Qt.alpha(Colors.cyan, thresholdBorder._thresholdAlpha))
            thresholdBorder._thresholdAlpha = 0
            warningPulse.start()
        } else if (moduleState === "critical") {
            thresholdBorder.border.color = Qt.binding(() => Qt.alpha(Colors.red, thresholdBorder._thresholdAlpha))
            thresholdBorder._thresholdAlpha = 0.3
            criticalBreathing.start()
        } else {
            thresholdBorder._thresholdAlpha = 0
        }
    }
}
