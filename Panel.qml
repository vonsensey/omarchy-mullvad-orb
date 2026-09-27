import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Mullvad Orb panel: the globe on the left, every Mullvad control on the
// right. Picking on the globe and picking in the dropdowns are the same
// selection; nothing touches the daemon until you press Connect.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null
  property bool opened: false

  readonly property string pluginId: "io.github.vonsensey.mullvad-orb"
  readonly property var svc: service
  readonly property var tunnel: svc ? svc.tunnel : Model.tunnelView(null)
  readonly property var prefs: svc ? svc.prefs : Model.settingsView({})
  readonly property var world: svc ? svc.world : ({ countries: [], providers: [] })
  readonly property bool privacy: svc ? svc.privacy : false

  readonly property var globe: globeLoader.item

  // ---- the selection shared by globe and dropdowns
  property string selCountry: ""
  property string selCity: ""
  property string selHost: ""
  property string entryCountry: ""
  property string entryCity: ""
  property string tab: "connect"

  readonly property var exitFilter: Model.relayFilter(prefs, "exit")
  readonly property var entryFilter: Model.relayFilter(prefs, "entry")
  readonly property var selection: selCountry ? { country: selCountry, city: selCity, hostname: selHost } : null
  readonly property var entrySelection: entryCountry ? { country: entryCountry, city: entryCity } : null

  function selectCountry(code) {
    if (code === "any") code = ""
    selCountry = code; selCity = ""; selHost = ""
    if (code && globe) globe.focusCountry(code)
  }
  function selectCity(country, city) {
    if (city === "any") city = ""
    if (selCountry !== country) { selCountry = country; if (globe) globe.focusCountry(country) }
    selCity = city; selHost = ""
    if (city && globe) globe.focusCity(country, city)
  }
  function selectHost(country, city, host) {
    selCountry = country; selCity = city
    selHost = host === "any" ? "" : host
  }

  // Seed the selection from the daemon's current constraint.
  function seedSelection() {
    var ex = prefs.exit
    selCountry = ex.country || ""
    selCity = ex.city || ""
    selHost = ex.hostname || ""
    var en = prefs.entry
    entryCountry = en.country || ""
    entryCity = en.city || ""
    if (!globe) return
    var target = svc && tunnel.state === "connected" ? svc.exitCity() : null
    if (target) showConnection()
    else if (selCity) globe.focusCity(selCountry, selCity)
    else if (selCountry) globe.focusCountry(selCountry)
  }

  // Relay commands a Connect would send; empty when nothing was changed.
  readonly property var plan: Model.connectPlan(prefs, selection, entrySelection)
  readonly property bool selectionPending: plan.length > 0

  function connectSelection() {
    if (svc) svc.connectWith(plan)
  }

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) {}
    opened = true
    if (payload.tab) tab = String(payload.tab)
    if (svc) svc.refreshAll()
    Qt.callLater(function() { seedSelection(); keyCatcher.forceActiveFocus() })
  }
  function close() { opened = false }

  // When a tunnel comes up while the orb is open, swing round to show it.
  readonly property string liveState: tunnel.state
  onLiveStateChanged: if (opened && liveState === "connected") Qt.callLater(showConnection)
  function showConnection() {
    if (!globe) return
    var exitP = pointFor(tunnel.hostname)
    var from = tunnel.entryHostname ? pointFor(tunnel.entryHostname) : (privacy || !svc ? null : svc.home)
    globe.focusRoute(from, exitP)
  }
  function dismiss() {
    close()
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
  }

  // IPC hooks (omarchy-shell shell call <id> <method> <arg>) - handy for
  // keybinds and for scripted screenshots.
  function focusOn(arg) {
    var parts = String(arg || "").split(/\s+/)
    if (!globe) return "closed"
    if (parts[0] === "world") globe.resetView()
    else if (parts[2]) { selectCity(parts[0], parts[1]); selHost = parts[2] }
    else if (parts[1]) selectCity(parts[0], parts[1])
    else if (parts[0]) selectCountry(parts[0])
    return "ok"
  }
  function showTab(name) { tab = String(name || "connect"); return "ok" }

  readonly property var selectionLoc: selHost ? { kind: "host", country: selCountry, city: selCity, hostname: selHost }
    : (selCity ? { kind: "city", country: selCountry, city: selCity }
    : (selCountry ? { kind: "country", country: selCountry } : { kind: "any" }))

  readonly property string homeDir: Quickshell.env("HOME") || ""
  function expandHome(path) {
    var s = String(path || "")
    return s.indexOf("~/") === 0 ? homeDir + s.slice(1) : s
  }

  // One shared confirmation for anything destructive or network-cutting.
  property var _confirmAction: null
  function confirm(message, confirmText, action) {
    confirmDialog.message = message
    confirmDialog.confirmText = confirmText || "Confirm"
    confirmDialog.selectedIndex = 0
    _confirmAction = action
    confirmDialog.opened = true
  }

  // ---- theme: every colour derives from the active Omarchy theme
  readonly property color bg: Color.menu.background
  readonly property color fg: Color.menu.text
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color dim: Util.alpha(fg, 0.6)
  readonly property color faint: Util.alpha(fg, 0.1)
  readonly property string font: Style.font.menuFamily
  readonly property bool lightTheme: 0.2126 * bg.r + 0.7152 * bg.g + 0.0722 * bg.b > 0.5
  // Ocean sits below the land in dark themes and above it in light ones, so
  // coastlines keep contrast whatever the palette; the accent tints the sea.
  readonly property color oceanColor: lightTheme
    ? Qt.tint(Qt.tint(bg, Util.alpha(fg, 0.2)), Util.alpha(accent, 0.12))
    : Qt.tint(Qt.darker(bg, 1.35), Util.alpha(accent, 0.08))

  readonly property color stateColor: {
    var s = tunnel.state
    if (s === "connected") return accent
    if (s === "connecting" || s === "disconnecting") return fg
    return urgent
  }
  readonly property string stateTitle: {
    switch (tunnel.state) {
    case "connected": return "SECURE CONNECTION"
    case "connecting": return "CONNECTING…"
    case "disconnecting": return "DISCONNECTING…"
    case "error": return tunnel.blocking ? "BLOCKED" : "ERROR"
    case "daemon-offline": return "DAEMON NOT RUNNING"
    case "unknown": return "CHECKING…"
    default: return tunnel.lockedDown ? "BLOCKED · LOCKDOWN" : "UNSECURED CONNECTION"
    }
  }

  PanelWindow {
    id: window
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-mullvad-orb"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: Color.menu.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

    Shortcut {
      enabled: root.opened
      sequence: "Escape"
      context: Qt.WindowShortcut
      onActivated: confirmDialog.opened ? confirmDialog.canceled() : root.dismiss()
    }

    BorderSurface {
      id: card
      width: Math.min(Style.space(1240), window.width - Style.gapsOut * 4)
      height: Math.min(Style.space(800), window.height - Style.gapsOut * 4)
      anchors.centerIn: parent
      color: root.bg
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.normalBorderWidth))
      radius: Style.cornerRadius

      MouseArea { anchors.fill: parent; onClicked: keyCatcher.forceActiveFocus() }

      // Keyboard: arrows spin, +/- zoom, 0 resets, Enter connects,
      // D disconnects, R reconnects, 1-4 switch tabs.
      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) {
          if (confirmDialog.handleKey(event)) { event.accepted = true; return }
          var k = event.key
          if (k === Qt.Key_Left) globe.nudge(-12, 0)
          else if (k === Qt.Key_Right) globe.nudge(12, 0)
          else if (k === Qt.Key_Up) globe.nudge(0, 8)
          else if (k === Qt.Key_Down) globe.nudge(0, -8)
          else if (k === Qt.Key_Plus || k === Qt.Key_Equal) globe.zoomBy(1.3)
          else if (k === Qt.Key_Minus) globe.zoomBy(1 / 1.3)
          else if (k === Qt.Key_0) globe.resetView()
          else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.connectSelection()
          else if (k === Qt.Key_D && root.svc) root.svc.disconnect()
          else if (k === Qt.Key_R && root.svc) root.svc.reconnect()
          else if (k >= Qt.Key_1 && k <= Qt.Key_4) root.tab = ["connect", "settings", "advanced", "account"][k - Qt.Key_1]
          else return
          event.accepted = true
        }
      }

      // ------------------------------------------------ header
      Item {
        id: header
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: Style.space(58)

        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.panelPadding
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xxl

          MoleIcon {
            anchors.verticalCenter: parent.verticalCenter
            iconSize: Style.space(26)
            color: root.fg
            noseColor: root.tunnel.state === "connected" ? root.accent : root.fg
            pulsing: root.tunnel.state === "connecting"
          }

          Text {
            text: "MULLVAD ORB"
            color: root.fg
            font.family: root.font
            font.pixelSize: Style.font.heading
            font.bold: true
            font.letterSpacing: 2
            anchors.verticalCenter: parent.verticalCenter
          }

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: stateRow.implicitWidth + Style.spacing.xxl * 2
            height: Style.space(24)
            radius: height / 2
            color: Util.alpha(root.stateColor, 0.14)
            border.color: Util.alpha(root.stateColor, 0.5)
            border.width: 1

            Row {
              id: stateRow
              anchors.centerIn: parent
              spacing: Style.spacing.md
              Rectangle {
                width: Style.space(7); height: width; radius: width / 2
                color: root.stateColor
                anchors.verticalCenter: parent.verticalCenter
                SequentialAnimation on opacity {
                  running: root.tunnel.state === "connecting" || root.tunnel.state === "disconnecting"
                  loops: Animation.Infinite
                  NumberAnimation { from: 1; to: 0.2; duration: 450 }
                  NumberAnimation { from: 0.2; to: 1; duration: 450 }
                  onRunningChanged: if (!running) parent.opacity = 1
                }
              }
              Text {
                text: root.stateTitle
                color: root.stateColor
                font.family: root.font
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1
              }
            }
          }
        }

        Row {
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.sm

          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.svc && root.svc.account.loggedIn && isFinite(root.svc.daysLeft) && (!root.privacy || root.svc.expiringSoon)
            text: root.svc && isFinite(root.svc.daysLeft) ? root.svc.daysLeft + " days left" : ""
            color: root.svc && root.svc.expiringSoon ? root.urgent : root.dim
            font.family: root.font
            font.pixelSize: Style.font.caption
            rightPadding: Style.spacing.lg
          }
          Button {
            iconText: ""
            tooltipText: "Close (Esc)"
            foreground: root.fg
            onClicked: root.dismiss()
          }
        }
      }

      PanelSeparator {
        id: headerRule
        anchors { left: parent.left; right: parent.right; top: header.bottom }
        foreground: root.fg
      }

      // ------------------------------------------------ globe
      Item {
        id: stage
        anchors { left: parent.left; top: headerRule.bottom; bottom: parent.bottom; right: sidebar.left }
        clip: true

        // The globe exists only while the panel is open: its two canvases are
        // tens of MB at 2x scale and are freed again on close.
        Loader {
          id: globeLoader
          anchors.fill: parent
          anchors.margins: Style.spacing.lg
          active: root.opened
          sourceComponent: Component {
            Globe {
              id: orb
              anchors.fill: parent
              shapes: countries.shapes
              world: root.world
              filter: root.exitFilter
              selectedCountry: root.selCountry
              selectedCity: root.selCity
              selectedHost: root.selHost
              tunnelState: root.tunnel.state
              exitPoint: root.tunnel.state === "connected" || root.tunnel.state === "connecting" ? root.pointFor(root.tunnel.hostname) : null
              entryPoint: root.tunnel.entryHostname ? root.pointFor(root.tunnel.entryHostname) : null
              homePoint: root.privacy || !root.svc ? null : root.svc.home
              sphereColor: root.oceanColor
              landColor: root.lightTheme ? Qt.tint(root.bg, Util.alpha(root.fg, 0.1)) : Qt.tint(root.bg, Util.alpha(root.fg, 0.2))
              servedColor: root.lightTheme ? Qt.tint(root.bg, Util.alpha(root.fg, 0.02)) : Qt.tint(root.bg, Util.alpha(root.fg, 0.33))
              lineColor: root.fg
              dotColor: root.fg
              accentColor: root.accent
              urgentColor: root.urgent
              textColor: root.fg
              panelColor: root.bg
              fontFamily: root.font
              fontSize: Style.font.bodySmall

              onCountryClicked: function(code) {
                if (Model.findCountry(root.world, code)) root.selectCountry(code)
              }
              onCityClicked: function(country, city) {
                if (root.selCountry === country && root.selCity === city) orb.focusCity(country, city)
                else {
                  var switching = root.selCountry !== country
                  root.selCountry = country; root.selCity = city; root.selHost = ""
                  if (switching) orb.focusCountry(country)
                }
              }
              onServerClicked: function(country, city, host) { root.selectHost(country, city, host) }
              onCityActivated: function(country, city) {
                root.selCountry = country; root.selCity = city; root.selHost = ""
                root.connectSelection()
              }
            }
          }
        }

        // Where the globe is pointing, bottom-left.
        Text {
          anchors { left: parent.left; bottom: parent.bottom; margins: Style.spacing.panelPadding }
          text: {
            if (!root.selCountry) return "Drag to spin · scroll to zoom · click a dot to pick · double-click to connect"
            var loc = Model.describeLocation(root.world, root.selHost ? { kind: "host", country: root.selCountry, city: root.selCity, hostname: root.selHost }
              : (root.selCity ? { kind: "city", country: root.selCountry, city: root.selCity } : { kind: "country", country: root.selCountry }))
            return loc + (root.selectionPending ? "  ·  press Enter to connect" : "")
          }
          color: root.dim
          font.family: root.font
          font.pixelSize: Style.font.caption
        }

        Column {
          anchors { right: parent.right; bottom: parent.bottom; margins: Style.spacing.panelPadding }
          spacing: Style.spacing.sm
          Button { iconText: ""; tooltipText: "Zoom in (+)"; bordered: true; foreground: root.fg; onClicked: globe.zoomBy(1.5) }
          Button { iconText: ""; tooltipText: "Zoom out (-)"; bordered: true; foreground: root.fg; onClicked: globe.zoomBy(1 / 1.5) }
          Button { iconText: ""; tooltipText: "Whole world (0)"; bordered: true; foreground: root.fg; onClicked: globe.resetView() }
          Button {
            iconText: ""
            tooltipText: "Show my connection"
            bordered: true
            foreground: root.fg
            visible: root.globe !== null && root.globe.exitPoint !== null
            onClicked: root.showConnection()
          }
        }

        Text {
          anchors { right: parent.right; top: parent.top; margins: Style.spacing.panelPadding }
          text: root.world.countries.length + " countries · " + root.cityCount + " cities · " + root.relayCount + " servers"
          color: root.dim
          font.family: root.font
          font.pixelSize: Style.font.caption
        }
      }

      // ------------------------------------------------ sidebar
      Rectangle {
        id: sidebar
        anchors { right: parent.right; top: headerRule.bottom; bottom: parent.bottom }
        width: Math.min(Style.space(420), card.width * 0.4)
        color: "transparent"

        Rectangle {
          anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
          width: 1
          color: root.faint
        }

        ButtonGroup {
          id: tabs
          anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.spacing.panelPadding }
          options: [
            { value: "connect", label: "Connect" },
            { value: "settings", label: "Settings" },
            { value: "advanced", label: "Advanced" },
            { value: "account", label: "Account" }
          ]
          value: root.tab
          foreground: root.fg
          background: root.bg
          fontFamily: root.font
          fontSize: Style.font.bodySmall
          onChanged: function(v) { root.tab = v }
        }

        Loader {
          id: tabLoader
          anchors { left: parent.left; right: parent.right; top: tabs.bottom; bottom: toast.top; topMargin: Style.spacing.lg }
          sourceComponent: root.tab === "settings" ? settingsTab
            : root.tab === "advanced" ? advancedTab
            : root.tab === "account" ? accountTab : connectTab
        }

        // Command feedback: last error (urgent) or notice.
        Rectangle {
          id: toast
          anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: Style.spacing.md }
          readonly property string message: root.svc ? (root.svc.lastError || root.svc.lastNotice) : ""
          readonly property bool isError: root.svc && root.svc.lastError !== ""
          height: message ? toastText.implicitHeight + Style.spacing.lg * 2 : 0
          visible: height > 0
          radius: Style.cornerRadius
          color: Util.alpha(isError ? root.urgent : root.fg, 0.12)
          border.color: Util.alpha(isError ? root.urgent : root.fg, 0.35)
          border.width: 1
          Text {
            id: toastText
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: Style.spacing.lg }
            text: toast.message
            wrapMode: Text.Wrap
            color: toast.isError ? root.urgent : root.fg
            font.family: root.font
            font.pixelSize: Style.font.caption
          }
        }
      }

      ConfirmDialog {
        id: confirmDialog
        anchors.fill: parent
        z: 10
        background: root.bg
        foreground: root.fg
        selectedText: root.accent
        fontFamily: root.font
        onCanceled: { opened = false; root._confirmAction = null; keyCatcher.forceActiveFocus() }
        onConfirmed: {
          opened = false
          var action = root._confirmAction
          root._confirmAction = null
          if (action) action()
          keyCatcher.forceActiveFocus()
        }
        onOpenedChanged: if (opened) keyCatcher.forceActiveFocus()
      }
    }
  }

  readonly property int cityCount: {
    var n = 0
    for (var i = 0; i < world.countries.length; i++) n += world.countries[i].cities.length
    return n
  }
  readonly property int relayCount: {
    var n = 0
    for (var i = 0; i < world.countries.length; i++) n += world.countries[i].relayCount
    return n
  }

  function pointFor(hostname) {
    var relay = Model.findRelay(world, hostname)
    var city = relay ? Model.findCity(world, relay.country, relay.city) : null
    return city ? { lat: city.lat, lon: city.lon } : null
  }

  FileView {
    id: countries
    property var shapes: []
    path: Qt.resolvedUrl("assets/countries.json").toString().replace(/^file:\/\//, "")
    printErrors: false
    onLoaded: { try { shapes = JSON.parse(text()) } catch (e) { shapes = [] } }
  }

  Component { id: connectTab; ConnectTab { panel: root } }
  Component { id: settingsTab; SettingsTab { panel: root } }
  Component { id: advancedTab; AdvancedTab { panel: root } }
  Component { id: accountTab; AccountTab { panel: root } }
}
