import QtQuick
import QtQuick.Shapes

// The Mullvad Orb mark: an original mole peeking out of its burrow - a nod
// to the name ("mullvad" is Swedish for mole) without borrowing Mullvad's
// logo. Drawn natively from 24-unit path data (same as docs/img/mole.svg),
// so it stays crisp in a 14px bar slot and takes any theme colour.
Item {
  id: root

  property real iconSize: 16
  property color color: "white"
  property color noseColor: color
  property bool pulsing: false

  // The artwork spans x 1..23, y 6..21.3 of its 24-unit box; the item is
  // cropped to it so the mole fills iconSize wide and centres optically.
  readonly property real unit: iconSize / 22
  implicitWidth: iconSize
  implicitHeight: Math.round(15.3 * unit)
  width: implicitWidth
  height: implicitHeight

  Item {
    id: art
    anchors.fill: parent

    Shape {
      x: -1 * root.unit
      y: -6 * root.unit
      width: 24
      height: 24
      scale: root.unit
      transformOrigin: Item.TopLeft
      preferredRendererType: Shape.CurveRenderer

      // Head with a pointed snout; the eyes are holes.
      ShapePath {
        fillColor: root.color
        strokeColor: "transparent"
        fillRule: ShapePath.OddEvenFill
        PathSvg {
          path: "M5 17.4 C4.6 11 8 6 12 6 C16 6 19.4 11 19 17.4 L14.3 17.4 L12 20 L9.7 17.4 Z "
            + "M9.75 11.3 A0.85 0.85 0 1 0 8.05 11.3 A0.85 0.85 0 1 0 9.75 11.3 Z "
            + "M15.95 11.3 A0.85 0.85 0 1 0 14.25 11.3 A0.85 0.85 0 1 0 15.95 11.3 Z"
        }
      }
      // Two digging paws resting on the rim of the burrow.
      ShapePath {
        fillColor: root.color
        strokeColor: "transparent"
        PathSvg {
          path: "M1 18.4 C1.4 15.4 4.3 14.4 6.9 15.8 L7.6 18.4 L6.6 20.3 L6 18.8 L5 20.5 L4.4 18.8 L3.3 20.3 L2.9 18.8 L1.7 19.9 Z "
            + "M23 18.4 C22.6 15.4 19.7 14.4 17.1 15.8 L16.4 18.4 L17.4 20.3 L18 18.8 L19 20.5 L19.6 18.8 L20.7 20.3 L21.1 18.8 L22.3 19.9 Z"
        }
      }
      // The nose: lights up in the accent colour while the tunnel is up.
      ShapePath {
        fillColor: root.noseColor
        strokeColor: "transparent"
        PathSvg { path: "M13.75 19.5 A1.75 1.75 0 1 0 10.25 19.5 A1.75 1.75 0 1 0 13.75 19.5 Z" }
      }
    }

    SequentialAnimation on opacity {
      running: root.pulsing
      loops: Animation.Infinite
      NumberAnimation { from: 1; to: 0.35; duration: 500 }
      NumberAnimation { from: 0.35; to: 1; duration: 500 }
      onRunningChanged: if (!running) art.opacity = 1
    }
  }
}
