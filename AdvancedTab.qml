import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Advanced tab: tunnel internals, custom lists, split tunnelling, API access,
// server IP overrides, app version and resets.
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

  Column {
    id: body
    x: Style.spacing.panelPadding
    width: root.width - Style.spacing.panelPadding * 2
    spacing: Style.spacing.lg

    // ---------------------------------------- tunnel
    PanelSectionHeader { text: "TUNNEL"; foreground: p.fg; fontFamily: p.font }
    Text { text: "IP version"; color: p.dim; font.family: p.font; font.pixelSize: Style.font.caption; font.bold: true }
    ButtonGroup {
      options: [{ value: "any", label: "Automatic" }, { value: "v4", label: "IPv4" }, { value: "v6", label: "IPv6" }]
      value: prefs.ipVersion
      foreground: p.fg; background: p.bg; fontFamily: p.font; fontSize: Style.font.bodySmall
      onChanged: function(v) { svc.setIpVersion(v) }
    }
    Row {
      width: parent.width
      spacing: Style.spacing.md
      TextField {
        id: mtuField
        width: parent.width - mtuSave.width - Style.spacing.md
        placeholderText: "MTU: automatic (1280-1420)"
        text: prefs.mtu ? String(prefs.mtu) : ""
        foreground: p.fg
        font.family: p.font
        validator: IntValidator { bottom: 1280; top: 1420 }
        onAccepted: mtuSave.clicked()
      }
      Button {
        id: mtuSave
        text: "Set MTU"
        bordered: true
        foreground: p.fg; fontFamily: p.font
        onClicked: svc.setMtu(mtuField.text ? Number(mtuField.text) : 0)
      }
    }
    Dropdown {
      width: parent.width
      label: "WireGuard key rotation"
      options: [
        { value: "", label: "Default" },
        { value: "24", label: "Every day" },
        { value: "72", label: "Every 3 days" },
        { value: "168", label: "Every week" },
        { value: "336", label: "Every 2 weeks" },
        { value: "720", label: "Every 30 days" }
      ]
      value: prefs.rotationHours ? String(prefs.rotationHours) : ""
      foreground: p.fg; fontFamily: p.font
      onChanged: function(v) { svc.setRotation(v ? Number(v) : 0) }
    }
    Button {
      text: "Rotate WireGuard key now"
      iconText: ""
      bordered: true
      foreground: p.fg; fontFamily: p.font
      onClicked: svc.rotateKey()
    }

    // ---------------------------------------- custom lists
    PanelSeparator { width: parent.width; foreground: p.fg }
    PanelSectionHeader { text: "CUSTOM LISTS"; foreground: p.fg; fontFamily: p.font }
    Text {
      width: parent.width
      wrapMode: Text.Wrap
      text: "Group locations and connect to the best one in the group. \"Add\" uses the location picked on the globe."
      color: p.dim; font.family: p.font; font.pixelSize: Style.font.caption
    }
    Repeater {
      model: prefs.customLists
      delegate: Rectangle {
        id: listCard
        required property var modelData
        readonly property string listName: modelData.name
        width: body.width
        height: listCol.implicitHeight + Style.spacing.lg * 2
        radius: Style.cornerRadius
        color: "transparent"
        border.color: p.faint
        border.width: 1
        Column {
          id: listCol
          anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.spacing.lg }
          spacing: Style.spacing.md
          Item {
            width: parent.width
            height: listActions.height
            Text {
              anchors.left: parent.left
              anchors.right: listActions.left
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.name
              elide: Text.ElideRight
              color: p.fg; font.family: p.font; font.pixelSize: Style.font.body; font.bold: true
            }
            Row {
              id: listActions
              anchors.right: parent.right
              spacing: Style.spacing.xs
              PanelActionButton {
                iconText: ""
                tooltipText: p.selCountry ? "Add " + Model.describeLocation(p.world, p.selectionLoc, prefs.customLists) : "Pick a location on the globe first"
                enabled: p.selCountry !== ""
                foreground: p.fg
                onClicked: svc.listAdd(modelData.name, p.selection)
              }
              PanelActionButton {
                iconText: ""
                tooltipText: "Use as entry (multihop)"
                visible: prefs.multihop
                foreground: p.fg
                onClicked: svc.setEntryList(modelData.name)
              }
              PanelActionButton {
                iconText: ""
                tooltipText: "Delete list"
                foreground: p.fg
                hoverColor: p.urgent
                onClicked: p.confirm("Delete the custom list \"" + modelData.name + "\"?", "Delete", function() { svc.listDelete(modelData.name) })
              }
            }
          }
          Flow {
            width: parent.width
            spacing: Style.spacing.sm
            Repeater {
              model: modelData.locations
              delegate: Rectangle {
                required property var modelData
                readonly property var loc: modelData
                width: chipRow.implicitWidth + Style.spacing.lg * 2
                height: chipRow.implicitHeight + Style.spacing.sm * 2
                radius: height / 2
                color: Util.alpha(p.fg, 0.08)
                Row {
                  id: chipRow
                  anchors.centerIn: parent
                  spacing: Style.spacing.sm
                  Text {
                    text: Model.describeLocation(p.world, loc)
                    color: p.fg; font.family: p.font; font.pixelSize: Style.font.caption
                  }
                  Text {
                    text: ""
                    color: p.dim; font.family: p.font; font.pixelSize: Style.font.caption
                    MouseArea {
                      anchors.fill: parent
                      anchors.margins: -4
                      cursorShape: Qt.PointingHandCursor
                      onClicked: svc.listRemove(listCard.listName, loc)
                    }
                  }
                }
              }
            }
            Text {
              visible: modelData.locations.length === 0
              text: "Empty - pick a location and press +"
              color: p.dim; font.family: p.font; font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
    Row {
      width: parent.width
      spacing: Style.spacing.md
      TextField {
        id: listName
        width: parent.width - listCreate.width - Style.spacing.md
        placeholderText: "New list name"
        foreground: p.fg
        font.family: p.font
        onAccepted: listCreate.clicked()
      }
      Button {
        id: listCreate
        text: "Create"
        bordered: true
        foreground: p.fg; fontFamily: p.font
        onClicked: {
          var n = listName.text.trim()
          if (!n) return
          svc.listNew(n)
          listName.text = ""
        }
      }
    }

    // ---------------------------------------- split tunnelling
    PanelSeparator { width: parent.width; foreground: p.fg }
    PanelSectionHeader { text: "SPLIT TUNNELING"; foreground: p.fg; fontFamily: p.font }
    Text {
      width: parent.width
      wrapMode: Text.Wrap
      text: "Apps launched here (and everything they start) bypass the VPN. Handy for local games, banking apps or LAN tools."
      color: p.dim; font.family: p.font; font.pixelSize: Style.font.caption
    }
    Row {
      width: parent.width
      spacing: Style.spacing.md
      TextField {
        id: excludeCmd
        width: parent.width - excludeGo.width - Style.spacing.md
        placeholderText: "Command, e.g. steam or firefox -P banking"
        foreground: p.fg
        font.family: p.font
        onAccepted: excludeGo.clicked()
      }
      Button {
        id: excludeGo
        text: "Launch"
        bordered: true
        foreground: p.fg; fontFamily: p.font
        onClicked: { svc.launchExcluded(excludeCmd.text); excludeCmd.text = "" }
      }
    }
    Repeater {
      model: svc ? svc.splitProcesses : []
      delegate: Item {
        required property var modelData
        width: body.width
        height: Style.space(26)
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.name + "  ·  PID " + modelData.pid
          color: p.fg; font.family: p.font; font.pixelSize: Style.font.body
        }
        PanelActionButton {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          iconText: ""
          tooltipText: "Route through the VPN again"
          foreground: p.fg
          hoverColor: p.urgent
          onClicked: svc.splitRemove(modelData.pid)
        }
      }
    }
    Row {
      spacing: Style.spacing.md
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: svc && svc.splitProcesses.length ? svc.splitProcesses.length + " excluded" : "No excluded apps running"
        color: p.dim; font.family: p.font; font.pixelSize: Style.font.caption
      }
      Button {
        visible: svc && svc.splitProcesses.length > 0
        text: "Clear all"
        bordered: true
        foreground: p.fg; fontFamily: p.font
        onClicked: svc.splitClear()
      }
    }

    // ---------------------------------------- API access
    PanelSeparator { width: parent.width; foreground: p.fg }
    PanelSectionHeader { text: "API ACCESS"; foreground: p.fg; fontFamily: p.font }
    Text {
      width: parent.width
      wrapMode: Text.Wrap
      text: "How the app reaches Mullvad's API (login, server list, keys) when direct access is blocked. In use: " + (svc && svc.apiCurrent ? svc.apiCurrent : "-")
      color: p.dim; font.family: p.font; font.pixelSize: Style.font.caption
    }
    Repeater {
      model: prefs.apiMethods
      delegate: Item {
        required property var modelData
        width: body.width
        height: Style.space(30)
        Text {
          anchors.left: parent.left
          anchors.right: apiRow.left
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.name + (svc && svc.apiCurrent === modelData.name ? "  ·  in use" : "")
          elide: Text.ElideRight
          color: p.fg; font.family: p.font; font.pixelSize: Style.font.body
        }
        Row {
          id: apiRow
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.sm
          PanelActionButton { iconText: ""; tooltipText: "Test"; foreground: p.fg; onClicked: svc.apiTest(modelData.id, modelData.name) }
          PanelActionButton { iconText: ""; tooltipText: "Use now"; foreground: p.fg; enabled: modelData.enabled; onClicked: svc.apiUse(modelData.id) }
          ToggleSwitch {
            anchors.verticalCenter: parent.verticalCenter
            checked: modelData.enabled
            foreground: p.fg
            onToggled: svc.apiSetEnabled(modelData.id, !checked)
          }
        }
      }
    }

    // ---------------------------------------- server IP overrides
    PanelSeparator { width: parent.width; foreground: p.fg }
    PanelSectionHeader { text: "SERVER IP OVERRIDES"; foreground: p.fg; fontFamily: p.font }
    Text {
      width: parent.width
      wrapMode: Text.Wrap
      text: "Where Mullvad's server IPs are blocked, Mullvad support can give you a JSON patch of working IPs. " + (svc ? svc.overrideCount : 0) + " override(s) active."
      color: p.dim; font.family: p.font; font.pixelSize: Style.font.caption
    }
    TextField {
      id: patchPath
      width: parent.width
      placeholderText: "Path, e.g. ~/Downloads/mullvad-overrides.json"
      foreground: p.fg
      font.family: p.font
    }
    Row {
      spacing: Style.spacing.md
      Button {
        text: "Import"
        bordered: true
        foreground: p.fg; fontFamily: p.font
        enabled: patchPath.text.trim() !== ""
        onClicked: svc.importOverrides(p.expandHome(patchPath.text.trim()))
      }
      Button {
        text: "Export"
        bordered: true
        foreground: p.fg; fontFamily: p.font
        enabled: patchPath.text.trim() !== ""
        onClicked: svc.exportOverrides(p.expandHome(patchPath.text.trim()))
      }
      Button {
        text: "Clear all"
        bordered: true
        foreground: p.fg; fontFamily: p.font
        visible: svc && svc.overrideCount > 0
        onClicked: p.confirm("Remove every server IP override?", "Clear", function() { svc.clearOverrides() })
      }
    }

    // ---------------------------------------- app
    PanelSeparator { width: parent.width; foreground: p.fg }
    PanelSectionHeader { text: "APP"; foreground: p.fg; fontFamily: p.font }
    Text {
      width: parent.width
      wrapMode: Text.Wrap
      text: {
        var v = svc ? svc.version : {}
        if (!v.current) return "Version unknown"
        var line = "Mullvad " + v.current + (v.supported ? "" : " (no longer supported)")
        if (v.upgrade && v.upgrade !== v.current && v.upgrade !== "none") line += "  ·  " + v.upgrade + " available: sudo pacman -Syu"
        return line
      }
      color: svc && svc.version.supported === false ? p.urgent : p.fg
      font.family: p.font; font.pixelSize: Style.font.body
    }
    Toggle {
      width: parent.width
      label: "Beta program"
      description: "Get notified about beta releases."
      checked: prefs.beta
      foreground: p.fg; fontFamily: p.font
      onClicked: svc.setBeta(!prefs.beta)
    }
    Button {
      text: "Update server list"
      iconText: ""
      bordered: true
      foreground: p.fg; fontFamily: p.font
      onClicked: svc.updateRelays()
    }

    // ---------------------------------------- reset
    PanelSeparator { width: parent.width; foreground: p.fg }
    PanelSectionHeader { text: "RESET"; foreground: p.fg; fontFamily: p.font }
    Row {
      spacing: Style.spacing.md
      Button {
        text: "Reset settings"
        bordered: true
        foreground: p.urgent; fontFamily: p.font
        onClicked: p.confirm("Reset every Mullvad setting to its default? You stay logged in.", "Reset", function() { svc.resetSettings() })
      }
      Button {
        text: "Factory reset"
        bordered: true
        foreground: p.urgent; fontFamily: p.font
        onClicked: p.confirm("Factory reset logs this device out and erases all Mullvad settings, caches and logs. Continue?", "Erase", function() { svc.factoryReset() })
      }
    }
  }
}
