pragma Singleton
import QtQuick

QtObject {
    readonly property int radiusChrome:      10
    readonly property int radiusInteractive: 8
    readonly property int radiusContent:     0
    readonly property int barHeightCenter:  52
    readonly property int barHeightSide:    22
    readonly property int barPaddingOuter:   10
    readonly property int barPaddingModule:  12
    readonly property int identityZoneInsetHorizontal: 6
    readonly property int identityZoneInsetVertical:   4
    readonly property int identityZoneGap:             8
    readonly property real identityZoneOpacity:        0.86
    readonly property int commandSpinePaddingHorizontal: 18
    readonly property int commandSpineGap:               16
    readonly property int commandSpineSeamWidth:          2
    readonly property int borderWidth:       1
    readonly property int borderWidthAccent: 2
    readonly property int toastWidth:         350
    readonly property int transientSurfaceGap: 8
    readonly property int actionFeedbackWidth: 260
    readonly property int actionFeedbackRadiusChrome: 8
    readonly property int actionFeedbackRadiusMeter: 6

    readonly property string fontFamily:    "IosevkaTerm Nerd Font"
    readonly property int    fontSize:      14
    readonly property int    fontWeight:    Font.Medium  // 500
}
