import QtQuick
import "../theme"
import "../components"

// Calendar content: month view with current day highlighted.

Item {
    id: calendar

    property int _year: new Date().getFullYear()
    property int _month: new Date().getMonth()
    property int _today: new Date().getDate()
    property int _todayMonth: new Date().getMonth()
    property int _todayYear: new Date().getFullYear()

    property int _firstDayOffset: {
        var d = new Date(_year, _month, 1).getDay()
        return (d + 6) % 7
    }
    property int _daysInMonth: new Date(_year, _month + 1, 0).getDate()
    property int _numRows: Math.ceil((_firstDayOffset + _daysInMonth) / 7)

    property var _monthNames: [
        "JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE",
        "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"
    ]
    property var _dayNames: ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]

    Column {
        anchors.fill: parent
        spacing: 4

        Text {
            text: calendar._monthNames[calendar._month] + " " + calendar._year
            color: Colors.cyan
            font.family: Geometry.fontFamily
            font.pixelSize: Geometry.fontSize
            font.weight: Font.DemiBold
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Row {
            spacing: 0
            Repeater {
                model: 7
                Text {
                    width: Math.floor(calendar.width / 7)
                    height: 16
                    text: calendar._dayNames[index]
                    color: Colors.cyan
                    font.family: Geometry.fontFamily
                    font.pixelSize: 10
                    font.weight: Geometry.fontWeight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        Grid {
            columns: 7
            spacing: 0

            Repeater {
                model: calendar._numRows * 7

                Text {
                    property int dayNum: index - calendar._firstDayOffset + 1
                    property bool isValid: dayNum >= 1 && dayNum <= calendar._daysInMonth
                    property bool isToday: isValid && dayNum === calendar._today
                        && calendar._month === calendar._todayMonth
                        && calendar._year === calendar._todayYear
                    property bool isWeekend: (index % 7) >= 5

                    width: Math.floor(calendar.width / 7)
                    height: 20
                    text: isValid ? dayNum.toString() : ""
                    color: isToday ? Colors.amber
                         : isWeekend && isValid ? Colors.fg_dim
                         : Colors.fg
                    font.family: Geometry.fontFamily
                    font.pixelSize: Geometry.fontSize
                    font.weight: isToday ? Font.DemiBold : Geometry.fontWeight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
}
