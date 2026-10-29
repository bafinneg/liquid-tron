import QtQuick
import QtQuick.Shapes
import "../theme"

// 60-point sparkline chart for detail popovers.
// Renders a polyline from the points array, auto-scaled to the component bounds.
// Updates reactively when points change.
//
// Usage:
//   Sparkline {
//       width: 200; height: 40
//       points: cpuHistory  // array of numbers, newest last
//       lineColor: Colors.cyan
//   }

Item {
    id: root

    property var points: []
    property color lineColor: Colors.cyan
    property color fillColor: Qt.alpha(lineColor, 0.08)
    property int maxPoints: 60

    // Computed path for the polyline, scaled to fit the item bounds.
    property var _scaledPath: {
        var pts = root.points
        if (!pts || pts.length < 2) return []

        var count = pts.length
        var w = root.width
        var h = root.height
        var padding = 2

        // Find min/max for vertical scaling.
        var minVal = pts[0], maxVal = pts[0]
        for (var i = 1; i < count; i++) {
            if (pts[i] < minVal) minVal = pts[i]
            if (pts[i] > maxVal) maxVal = pts[i]
        }
        var range = maxVal - minVal
        if (range < 0.001) range = 1  // flat line: center vertically

        var result = []
        for (var j = 0; j < count; j++) {
            var x = (j / (count - 1)) * w
            // Invert Y: QML y=0 is top, high values should be top.
            var y = padding + (h - 2 * padding) * (1 - (pts[j] - minVal) / range)
            result.push(Qt.point(x, y))
        }
        return result
    }

    // Fill area path: line path + bottom-right + bottom-left to close the polygon.
    property var _fillPath: {
        var line = root._scaledPath
        if (line.length < 2) return []
        var fill = line.slice()
        fill.push(Qt.point(root.width, root.height))
        fill.push(Qt.point(0, root.height))
        return fill
    }

    Shape {
        anchors.fill: parent
        antialiasing: true

        // Filled area under the line.
        ShapePath {
            fillColor: root.fillColor
            strokeColor: "transparent"
            PathPolyline { path: root._fillPath }
        }

        // The line itself.
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.lineColor
            strokeWidth: 1
            PathPolyline { path: root._scaledPath }
        }
    }
}
