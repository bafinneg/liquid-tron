import QtQuick
import "../theme"

// Animated number display: smoothly interpolates between value changes
// over 200ms using the decay bezier curve. Renders as a single Text element
// with configurable prefix/suffix and fixed-width padding.
//
// For modules that need the raw interpolated value (e.g. Network's formatBw),
// read displayValue directly and set visible: false on this component.

Item {
    id: root

    property real value: 0
    property string prefix: ""
    property string suffix: ""
    property int padWidth: 0
    property color textColor: Colors.cyan
    property alias font: label.font

    // The interpolated value — readable by parent for custom formatting.
    readonly property real displayValue: _displayValue

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight

    // Internal animated property. Initialized to value on first binding
    // to suppress the 0→first-real-value tween on startup.
    property real _displayValue: value
    property bool _initialized: false

    Component.onCompleted: {
        _displayValue = value
        _initialized = true
    }

    Behavior on _displayValue {
        enabled: root._initialized
        NumberAnimation {
            duration: Motion.durationTween
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.decay
        }
    }

    onValueChanged: {
        _displayValue = value
    }

    Text {
        id: label
        text: root.prefix + root._displayValue.toFixed(0).padStart(root.padWidth, ' ') + root.suffix
        color: root.textColor
        font.family: Geometry.fontFamily
        font.pixelSize: Geometry.fontSize
        font.weight: Geometry.fontWeight
        verticalAlignment: Text.AlignVCenter
        height: Geometry.barHeightCenter
    }
}
