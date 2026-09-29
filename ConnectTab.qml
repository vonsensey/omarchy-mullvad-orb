import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Connect tab: live status, exit + entry location pickers (synced with the
// globe), multihop and custom lists.
Flickable {
  id: root

  property var panel: null
  readonly property var p: panel
  readonly property var svc: panel ? panel.svc : null
  readonly property var tunnel: panel.tunnel
  readonly property var prefs: panel.prefs
  readonly property var world: panel.world

  contentHeight: body.implicitHeight + Style.spacing.panelPadding
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

  function countryOptions(filter) {
    var out = [{ value: "any", label: "Any country" }]
    for (var i = 0; i < world.countries.length; i++) {
      var c = world.countries[i], n = 0
      for (var j = 0; j < c.cities.length; j++) n += Model.matchingRelays(c.cities[j], filter).length
      out.push({ value: c.code, label: c.name, description: n + (n === 1 ? " server" : " servers") })
    }
    return out
  }
  function cityOptions(code, filter) {
    var out = [{ value: "any", label: "Any city" }]
    var c = Model.findCountry(world, code)
    if (!c) return out
    for (var i = 0; i < c.cities.length; i++) {
      var n = Model.matchingRelays(c.cities[i], filter).length
      out.push({ value: c.cities[i].code, label: c.cities[i].name, description: n + (n === 1 ? " server" : " servers") })
    }
    return out
  }
  function serverOptions() {
    var out = [{ value: "any", label: "Any server" }]
    var city = Model.findCity(world, p.selCountry, p.selCity)
    if (!city) return out
    for (var i = 0; i < city.relays.length; i++) {
      var r = city.relays[i], tags = [r.owned ? "owned" : "rented", r.provider]
      if (r.daita) tags.push("DAITA")
      if (r.quic) tags.push("QUIC")
      if (r.lwo) tags.push("LWO")
      if (!Model.relayMatches(r, p.exitFilter)) tags.push("filtered out")
      out.push({ value: r.hostname, label: r.hostname, description: tags.join(" · ") })
    }
    return out
  }

  readonly property var exitCity: svc ? svc.exitCity() : null
  readonly property bool live: tunnel.state === "connected" || tunnel.state === "connecting"
  readonly property string filterSummary: {
    var bits = []
    if (prefs.ownership !== "any") bits.push(prefs.ownership === "owned" ? "Mullvad-owned only" : "rented only")
    if (prefs.providers.length) bits.push(prefs.providers.length + " providers")
    if (p.exitFilter.daita) bits.push("DAITA servers")
    if (p.exitFilter.obfuscation) bits.push(p.exitFilter.obfuscation.toUpperCase() + " servers")
    return bits.join(" · ")
  }

  Column {
    id: body
    x: Style.spacing.panelPadding
    width: root.width - Style.spacing.panelPadding * 2
    spacing: Style.spacing.xxl

    // ---------------------------------------- status card
    Rectangle {
      width: parent.width
      height: statusCol.implicitHeight + Style.spacing.xxl * 2
      radius: Style.cornerRadius
      color: Util.alpha(p.stateColor, 0.07)
      border.color: Util.alpha(p.stateColor, 0.3)
      border.width: 1

      Column {
        id: statusCol
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.spacing.xxl }
        spacing: Style.spacing.md

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: {
            if (root.live && root.exitCity) return root.exitCity.name + ", " + root.exitCity.countryName
            if (root.live) return tunnel.location && tunnel.location.city ? tunnel.location.city + ", " + tunnel.location.country : "Finding a server…"
            if (tunnel.state === "daemon-offline") return "The mullvad-daemon service is not running"
            if (svc && svc.account.revoked) return "This device was removed from your Mullvad account. Log in again on the Account tab"
            if (tunnel.state === "error") return tunnel.error || "Tunnel error"
            if (svc && !svc.installed && svc.checked) return "Install the mullvad-vpn package to use the orb"
            return "Not connected"
          }
          wrapMode: Text.Wrap
          color: p.fg
          font.family: p.font
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: text !== ""
          text: {
            if (!root.live || !tunnel.hostname) return ""
            return tunnel.hostname + (tunnel.entryHostname ? "  via  " + tunnel.entryHostname : "")
          }
          color: p.fg
          font.family: p.font
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: text !== ""
          text: {
            var loc = tunnel.location
            if (!loc || !loc.ipv4) return tunnel.state === "disconnected" && tunnel.lockedDown ? "Lockdown mode is blocking all traffic" : ""
            var who = loc.mullvadExit ? "Mullvad IP " : "Your IP "
            if (p.privacy) return who + "hidden (privacy mode)"
            return who + loc.ipv4 + (loc.ipv6 ? "  ·  " + loc.ipv6 : "")
          }
          color: p.dim
          font.family: p.font
          font.pixelSize: Style.font.caption
          elide: Text.ElideMiddle
        }

        Flow {
          width: parent.width
          spacing: Style.spacing.sm
          visible: root.live && tunnel.features.length > 0
          Repeater {
            model: root.live ? tunnel.features : []
            delegate: Rectangle {
              required property string modelData
              width: chip.implicitWidth + Style.spacing.lg * 2
              height: chip.implicitHeight + Style.spacing.sm * 2
              radius: height / 2
              color: Util.alpha(p.accent, 0.14)
              Text {
                textFormat: Text.PlainText
                id: chip
                anchors.centerIn: parent
                text: modelData
                color: p.fg
                font.family: p.font
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        Flow {
          width: parent.width
          spacing: Style.spacing.md
          topPadding: Style.spacing.sm
          // Nothing to press until Mullvad is installed and its daemon is up.
          visible: svc !== null && svc.installed && svc.daemonUp

          Button {
            readonly property string where: Model.describeLocation(world, p.selectionLoc, prefs.customLists)
            text: {
              if (tunnel.state === "connected" || tunnel.state === "connecting")
                return p.selectionPending ? "Switch to " + where : "Disconnect"
              return p.selCountry ? "Connect to " + where : "Connect"
            }
            iconText: text === "Disconnect" ? "" : ""
            bordered: true
            active: text !== "Disconnect"
            foreground: p.fg
            fontFamily: p.font
            enabled: svc && svc.installed && svc.daemonUp
            onClicked: text === "Disconnect" ? svc.disconnect() : p.connectSelection()
          }
          Button {
            text: "New server"
            iconText: ""
            tooltipText: "Reconnect to another matching server (R)"
            bordered: true
            foreground: p.fg
            fontFamily: p.font
            visible: root.live
            onClicked: svc.reconnect()
          }
          Button {
            text: "Disconnect"
            iconText: ""
            bordered: true
            foreground: p.fg
            fontFamily: p.font
            visible: root.live && p.selectionPending
            onClicked: svc.disconnect()
          }
        }
      }
    }

    // ---------------------------------------- exit location
    Column {
      width: parent.width
      spacing: Style.spacing.lg

      PanelSectionHeader { text: prefs.multihop ? "EXIT LOCATION" : "LOCATION"; foreground: p.fg; fontFamily: p.font }

      SearchableDropdown {
        width: parent.width
        label: "Country"
        placeholderText: "Search countries…"
        options: root.countryOptions(p.exitFilter)
        value: p.selCountry || "any"
        foreground: p.fg
        fontFamily: p.font
        onChanged: function(v) { p.selectCountry(v) }
      }
      SearchableDropdown {
        width: parent.width
        label: "City"
        placeholderText: "Search cities…"
        enabled: p.selCountry !== ""
        opacity: enabled ? 1 : 0.5
        options: root.cityOptions(p.selCountry, p.exitFilter)
        value: p.selCity || "any"
        foreground: p.fg
        fontFamily: p.font
        onChanged: function(v) { p.selectCity(p.selCountry, v) }
      }
      SearchableDropdown {
        width: parent.width
        label: "Server"
        placeholderText: "Search servers…"
        enabled: p.selCity !== ""
        opacity: enabled ? 1 : 0.5
        options: root.serverOptions()
        value: p.selHost || "any"
        foreground: p.fg
        fontFamily: p.font
        onChanged: function(v) { p.selectHost(p.selCountry, p.selCity, v) }
      }
      Text {
        textFormat: Text.PlainText
        width: parent.width
        visible: root.filterSummary !== ""
        text: "Filtered: " + root.filterSummary + ". Change in Settings."
        wrapMode: Text.Wrap
        color: p.dim
        font.family: p.font
        font.pixelSize: Style.font.caption
      }
    }

    // ---------------------------------------- multihop
    Column {
      width: parent.width
      spacing: Style.spacing.lg

      PanelSeparator { width: parent.width; foreground: p.fg }

      Toggle {
        width: parent.width
        label: "Multihop"
        description: "Route through an entry server in one place and exit in another."
        checked: prefs.multihop
        foreground: p.fg
        fontFamily: p.font
        onClicked: svc.setMultihop(!prefs.multihop)
      }

      SearchableDropdown {
        width: parent.width
        visible: prefs.multihop
        label: "Entry country"
        placeholderText: "Search countries…"
        options: root.countryOptions(p.entryFilter)
        value: prefs.entry.kind === "list" ? "any" : (p.entryCountry || "any")
        foreground: p.fg
        fontFamily: p.font
        onChanged: function(v) { p.entryCountry = v === "any" ? "" : v; p.entryCity = "" }
      }
      SearchableDropdown {
        width: parent.width
        visible: prefs.multihop
        enabled: p.entryCountry !== ""
        opacity: enabled ? 1 : 0.5
        label: "Entry city"
        placeholderText: "Search cities…"
        options: root.cityOptions(p.entryCountry, p.entryFilter)
        value: p.entryCity || "any"
        foreground: p.fg
        fontFamily: p.font
        onChanged: function(v) { p.entryCity = v === "any" ? "" : v }
      }
      Text {
        textFormat: Text.PlainText
        width: parent.width
        visible: prefs.multihop && prefs.daita && !prefs.daitaDirectOnly
        wrapMode: Text.Wrap
        text: "DAITA smart routing is on, so Mullvad picks a DAITA entry server itself. Turn on \"DAITA: direct only\" in Settings to use the entry chosen here."
        color: p.dim
        font.family: p.font
        font.pixelSize: Style.font.caption
      }
    }

    // ---------------------------------------- custom lists
    Column {
      width: parent.width
      spacing: Style.spacing.lg
      visible: prefs.customLists.length > 0

      PanelSeparator { width: parent.width; foreground: p.fg }
      PanelSectionHeader { text: "CUSTOM LISTS"; foreground: p.fg; fontFamily: p.font }

      Flow {
        width: parent.width
        spacing: Style.spacing.md
        Repeater {
          model: prefs.customLists
          delegate: Button {
            required property var modelData
            text: modelData.name + "  (" + modelData.locations.length + ")"
            iconText: ""
            bordered: true
            selected: prefs.exit.kind === "list" && prefs.exit.listId === modelData.id
            foreground: p.fg
            fontFamily: p.font
            tooltipText: "Connect to the fastest server in " + modelData.name
            onClicked: svc.connectToList(modelData.name)
          }
        }
      }
      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: "Manage lists in Advanced."
        color: p.dim
        font.family: p.font
        font.pixelSize: Style.font.caption
      }
    }
  }
}
