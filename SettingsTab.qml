import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Settings tab: the everyday Mullvad options. Every control shows the
// daemon's real value (settings.json) and writes through the CLI.
Flickable {
  id: root

  property var panel: null
  readonly property var p: panel
  readonly property var svc: panel ? panel.svc : null
  readonly property var prefs: panel.prefs

  contentHeight: body.implicitHeight + Style.spacing.panelPadding
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

  readonly property var portModes: ["wireguard-port", "udp2tcp", "shadowsocks", "lwo"]

  Column {
    id: body
    x: Style.spacing.panelPadding
    width: root.width - Style.spacing.panelPadding * 2
    spacing: Style.spacing.lg

    // ---------------------------------------- connection
    PanelSectionHeader { text: "CONNECTION"; foreground: p.fg; fontFamily: p.font }
    Toggle {
      width: parent.width
      label: "Auto-connect"
      description: "Connect as soon as the Mullvad daemon starts."
      checked: prefs.autoConnect
      foreground: p.fg; fontFamily: p.font
      onClicked: svc.setAutoConnect(!prefs.autoConnect)
    }
    Toggle {
      width: parent.width
      label: "Lockdown mode"
      description: "Block all traffic whenever the VPN is not connected - even after you press Disconnect."
      checked: prefs.lockdown
      foreground: p.fg; fontFamily: p.font
      onClicked: {
        if (prefs.lockdown) svc.setLockdown(false)
        else p.confirm("Lockdown blocks ALL internet traffic whenever Mullvad is disconnected, until you turn it off here. Turn it on?",
                       "Turn on", function() { svc.setLockdown(true) })
      }
    }
    Toggle {
      width: parent.width
      label: "Local network sharing"
      description: "Reach printers, NAS and other devices on your LAN while connected."
      checked: prefs.allowLan
      foreground: p.fg; fontFamily: p.font
      onClicked: svc.setLan(!prefs.allowLan)
    }

    // ---------------------------------------- privacy
    PanelSeparator { width: parent.width; foreground: p.fg }
    PanelSectionHeader { text: "PRIVACY"; foreground: p.fg; fontFamily: p.font }
    Toggle {
      width: parent.width
      label: "DAITA"
      description: "Defence against AI-guided traffic analysis: pads and reshapes packets so your traffic pattern gives less away. Uses more data and battery."
      checked: prefs.daita
      foreground: p.fg; fontFamily: p.font
      onClicked: svc.setDaita(!prefs.daita)
    }
    Toggle {
      width: parent.width
      visible: prefs.daita
      label: "DAITA: direct only"
      description: "Only connect to DAITA servers. Off lets Mullvad hop through a DAITA server to reach any exit."
      checked: prefs.daitaDirectOnly
      foreground: p.fg; fontFamily: p.font
      onClicked: svc.setDaitaDirectOnly(!prefs.daitaDirectOnly)
    }
    Toggle {
      width: parent.width
      label: "Quantum-resistant tunnel"
      description: "Adds a post-quantum key exchange on top of WireGuard."
      checked: prefs.quantum !== "off"
      foreground: p.fg; fontFamily: p.font
      onClicked: svc.setQuantum(prefs.quantum === "off")
    }
    Toggle {
      width: parent.width
      label: "IPv6 in the tunnel"
      description: "Route IPv6 through the VPN as well. Off blocks IPv6 while connected."
      checked: prefs.ipv6
      foreground: p.fg; fontFamily: p.font
      onClicked: svc.setIpv6(!prefs.ipv6)
    }

    // ---------------------------------------- DNS
    PanelSeparator { width: parent.width; foreground: p.fg }
    PanelSectionHeader { text: "DNS CONTENT BLOCKERS"; foreground: p.fg; fontFamily: p.font }
    Text {
      textFormat: Text.PlainText
      width: parent.width
      wrapMode: Text.Wrap
      color: p.dim
      font.family: p.font
      font.pixelSize: Style.font.caption
      text: prefs.dns.custom ? "Unavailable while custom DNS servers are in use." : "Mullvad's DNS drops these domains before they load."
    }
    Grid {
      width: parent.width
      columns: 2
      columnSpacing: Style.spacing.lg
      rowSpacing: Style.spacing.md
      enabled: !prefs.dns.custom
      opacity: enabled ? 1 : 0.45
      Repeater {
        model: Model.dnsBlockers
        delegate: Item {
          required property var modelData
          width: (body.width - Style.spacing.lg) / 2
          height: sw.height
          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: sw.left
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.label
            elide: Text.ElideRight
            color: p.fg
            font.family: p.font
            font.pixelSize: Style.font.body
          }
          ToggleSwitch {
            id: sw
            anchors.right: parent.right
            checked: prefs.dns.blockers[modelData.key] === true
            foreground: p.fg
            onToggled: svc.setBlocker(modelData.key, !checked)
          }
        }
      }
    }

    Toggle {
      width: parent.width
      label: "Custom DNS servers"
      description: "Use your own resolvers inside the tunnel instead of Mullvad's."
      checked: prefs.dns.custom
      foreground: p.fg; fontFamily: p.font
      onClicked: {
        var list = dnsField.text.split(/[\s,]+/).filter(function(x) { return x !== "" })
        if (prefs.dns.custom) svc.setCustomDns(false)
        else if (list.length) svc.setCustomDns(true, list)
        else dnsField.forceActiveFocus()
      }
    }
    Row {
      width: parent.width
      spacing: Style.spacing.md
      TextField {
        id: dnsField
        width: parent.width - dnsSave.width - Style.spacing.md
        placeholderText: "9.9.9.9, 2620:fe::fe"
        text: prefs.dns.addresses.join(", ")
        foreground: p.fg
        font.family: p.font
        onAccepted: dnsSave.clicked()
      }
      Button {
        id: dnsSave
        text: "Use"
        bordered: true
        foreground: p.fg; fontFamily: p.font
        onClicked: {
          var list = dnsField.text.split(/[\s,]+/).filter(function(x) { return x !== "" })
          if (list.length) svc.setCustomDns(true, list)
        }
      }
    }

    // ---------------------------------------- anti-censorship
    PanelSeparator { width: parent.width; foreground: p.fg }
    PanelSectionHeader { text: "ANTI-CENSORSHIP"; foreground: p.fg; fontFamily: p.font }
    Text { textFormat: Text.PlainText; width: parent.width; wrapMode: Text.Wrap; color: p.dim; font.family: p.font; font.pixelSize: Style.font.caption; text: "Disguise WireGuard traffic when a network blocks or throttles VPNs." }
    Dropdown {
      width: parent.width
      label: "Method"
      options: [
        { value: "auto", label: "Automatic" },
        { value: "off", label: "Off" },
        { value: "wireguard-port", label: "WireGuard port" },
        { value: "udp2tcp", label: "UDP-over-TCP" },
        { value: "shadowsocks", label: "Shadowsocks" },
        { value: "quic", label: "QUIC" },
        { value: "lwo", label: "LWO (lightweight obfuscation)" }
      ]
      value: prefs.obfuscation.mode
      foreground: p.fg; fontFamily: p.font
      onChanged: function(v) { svc.setObfuscation(v) }
    }
    Row {
      width: parent.width
      spacing: Style.spacing.md
      visible: root.portModes.indexOf(prefs.obfuscation.mode) !== -1
      TextField {
        id: portField
        width: parent.width - portSave.width - Style.spacing.md
        placeholderText: prefs.obfuscation.mode === "wireguard-port" ? "Port, e.g. 51820 or 53" : "Port or any"
        text: {
          var v = prefs.obfuscation.ports[prefs.obfuscation.mode]
          return v && v !== "any" ? v : ""
        }
        foreground: p.fg
        font.family: p.font
        validator: RegularExpressionValidator { regularExpression: /^(any|\d{1,5})?$/ }
        onAccepted: portSave.clicked()
      }
      Button {
        id: portSave
        text: "Set port"
        bordered: true
        foreground: p.fg; fontFamily: p.font
        onClicked: svc.setObfuscationPort(prefs.obfuscation.mode, portField.text || "any")
      }
    }
    Text {
      textFormat: Text.PlainText
      width: parent.width
      wrapMode: Text.Wrap
      color: p.dim
      font.family: p.font
      font.pixelSize: Style.font.caption
      visible: prefs.obfuscation.mode === "quic" || prefs.obfuscation.mode === "lwo"
      text: "Only servers that support " + prefs.obfuscation.mode.toUpperCase() + " are offered on the Connect tab."
    }

    // ---------------------------------------- filters
    PanelSeparator { width: parent.width; foreground: p.fg }
    PanelSectionHeader { text: "SERVER FILTERS"; foreground: p.fg; fontFamily: p.font }
    ButtonGroup {
      options: [
        { value: "any", label: "Any" },
        { value: "owned", label: "Mullvad-owned" },
        { value: "rented", label: "Rented" }
      ]
      value: prefs.ownership
      foreground: p.fg
      background: p.bg
      fontFamily: p.font
      fontSize: Style.font.bodySmall
      onChanged: function(v) { svc.setOwnership(v) }
    }
    MultiSelect {
      width: parent.width
      label: "Hosting providers"
      noSelectionText: "All providers"
      options: p.world.providers
      values: prefs.providers
      foreground: p.fg; fontFamily: p.font
      onChanged: function(values) { svc.setProviders(values) }
    }
  }
}
