import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Mullvad Orb bar widget: the mole tells the tunnel state at a glance.
//   connected      mole with its nose lit in the accent (+ country/city/server)
//   connecting     blinking, nose lit
//   disconnected   dimmed mole
//   error/blocked  urgent - traffic is being blocked
// Click opens the orb, right click connects/disconnects, middle click picks
// a new server.
BarWidget {
  id: root
  moduleName: "io.github.vonsensey.mullvad-orb"

  readonly property string pluginId: "io.github.vonsensey.mullvad-orb"
  readonly property var svc: bar && bar.shell ? bar.shell.serviceFor(pluginId) : null

  function pushSettings() { if (svc) svc.settings = settings }
  Component.onCompleted: pushSettings()
  onSettingsChanged: pushSettings()
  onSvcChanged: pushSettings()

  readonly property var tunnel: svc ? svc.tunnel : Model.tunnelView(null)
  readonly property string tunnelState: tunnel.state
  readonly property bool live: tunnelState === "connected" || tunnelState === "connecting"
  readonly property var exitCity: svc && live ? svc.exitCity() : null
  readonly property bool alarm: tunnelState === "error" || (tunnel.blocking && tunnelState === "disconnected")
    || (svc !== null && svc.expiringSoon && svc.daysLeft <= 1)
  readonly property color barFg: bar ? bar.barForeground : Color.foreground
  readonly property color bodyColor: alarm ? (bar ? bar.urgent : Color.urgent) : barFg

  readonly property string label: {
    if (!live || root.vertical) return ""
    var mode = String(setting("barLabel", "Country"))
    if (mode === "Country") return exitCity ? exitCity.country.toUpperCase() : ""
    if (mode === "City") return exitCity ? exitCity.name : ""
    if (mode === "Server") return tunnel.hostname
    return ""
  }

  function press(mouseButton) {
    if (!svc) return
    if (mouseButton === Qt.RightButton) svc.toggle()
    else if (mouseButton === Qt.MiddleButton) svc.reconnect()
    else if (bar && bar.shell) bar.shell.toggle(pluginId, "{}")
  }

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  Row {
    id: row
    anchors.fill: parent

    BarIconButton {
      id: icon
      bar: root.bar
      dimmed: root.tunnelState === "disconnected" && !root.alarm
      tooltipText: root.tooltip()
      iconComponent: Component {
        Item {
          MoleIcon {
            anchors.centerIn: parent
            iconSize: Math.round(Style.bar.iconCanvas * 1.15)
            color: root.bodyColor
            noseColor: root.live && !root.alarm ? Color.accent : root.bodyColor
            pulsing: root.tunnelState === "connecting" || root.tunnelState === "disconnecting"
          }
        }
      }
      onPressed: function(mouseButton) { root.press(mouseButton) }
    }

    WidgetButton {
      bar: root.bar
      visible: root.label !== ""
      text: root.label
      horizontalMargin: 2
      tooltipText: root.tooltip()
      onPressed: function(mouseButton) { root.press(mouseButton) }
    }
  }

  function tooltip() {
    if (!svc || !svc.checked) return "Mullvad"
    if (!svc.installed) return "Mullvad is not installed (package: mullvad-vpn)"
    var t = tunnel
    var lines = []
    if (t.state === "connected") {
      lines.push("Secured · " + (exitCity ? exitCity.name + ", " + exitCity.countryName : t.hostname))
      lines.push(t.hostname + (t.entryHostname ? " via " + t.entryHostname : ""))
      if (t.location && t.location.ipv4 && !svc.privacy) lines.push(t.location.ipv4)
    } else if (t.state === "connecting") lines.push("Connecting… traffic is blocked until the tunnel is up")
    else if (t.state === "error") lines.push("Error: " + t.error)
    else if (t.state === "daemon-offline") lines.push("Mullvad daemon is not running")
    else lines.push(t.lockedDown ? "Disconnected · lockdown is blocking traffic" : "Unsecured connection")
    if (svc.expiringSoon) lines.push("Account expires in " + svc.daysLeft + " days")
    lines.push("Click: open · Right: " + (t.state === "disconnected" ? "connect" : "disconnect") + " · Middle: new server")
    return lines.join("\n")
  }
}
