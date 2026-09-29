import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Account tab: number (masked until revealed), expiry, devices, vouchers,
// login/logout. The number is never written anywhere by this plugin.
Flickable {
  id: root

  property var panel: null
  readonly property var p: panel
  readonly property var svc: panel ? panel.svc : null
  readonly property var account: svc ? svc.account : ({ loggedIn: false })
  property bool reveal: false

  contentHeight: body.implicitHeight + Style.spacing.panelPadding
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

  Column {
    id: body
    x: Style.spacing.panelPadding
    width: root.width - Style.spacing.panelPadding * 2
    spacing: Style.spacing.lg

    // ---------------------------------------- logged in
    Column {
      width: parent.width
      spacing: Style.spacing.lg
      visible: root.account.loggedIn

      PanelSectionHeader { text: "ACCOUNT"; foreground: p.fg; fontFamily: p.font }
      Item {
        width: parent.width
        height: Math.max(numberText.implicitHeight, numberActions.height)
        Text {
          textFormat: Text.PlainText
          id: numberText
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: p.privacy ? "•••• •••• •••• ••••" : (root.reveal ? Model.groupAccount(root.account.number) : Model.maskAccount(root.account.number))
          color: p.fg
          font.family: p.font
          font.pixelSize: Style.font.title
          font.bold: true
        }
        Row {
          id: numberActions
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xs
          PanelActionButton {
            iconText: root.reveal ? "" : ""
            tooltipText: p.privacy ? "Hidden in privacy mode" : (root.reveal ? "Hide" : "Show")
            enabled: !p.privacy
            foreground: p.fg
            onClicked: root.reveal = !root.reveal
          }
          PanelActionButton { iconText: ""; tooltipText: "Copy account number"; foreground: p.fg; onClicked: svc.copyAccount() }
        }
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.Wrap
        text: {
          var d = svc ? svc.daysLeft : NaN
          if (!isFinite(d)) return "Paid until " + (root.account.expiry || "unknown")
          if (d < 0) return "Expired - add time to keep using Mullvad"
          return "Paid until " + root.account.expiry.slice(0, 10) + "  ·  " + d + (d === 1 ? " day" : " days") + " left"
        }
        color: svc && svc.expiringSoon ? p.urgent : p.fg
        font.family: p.font
        font.pixelSize: Style.font.body
      }
      Text {
        textFormat: Text.PlainText
        text: "This device: " + (root.account.deviceName || "-")
        color: p.dim
        font.family: p.font
        font.pixelSize: Style.font.body
      }

      Row {
        spacing: Style.spacing.md
        Button {
          text: "Add time"
          iconText: ""
          bordered: true
          active: svc && svc.expiringSoon
          foreground: p.fg; fontFamily: p.font
          tooltipText: "Opens mullvad.net/account in your browser"
          onClicked: svc.openAccountPage()
        }
        Button {
          text: "Log out"
          iconText: ""
          bordered: true
          foreground: p.fg; fontFamily: p.font
          onClicked: p.confirm("Log out and remove this device from the account?", "Log out", function() { svc.logout() })
        }
      }

      PanelSeparator { width: parent.width; foreground: p.fg }
      PanelSectionHeader { text: "VOUCHERS"; foreground: p.fg; fontFamily: p.font }
      Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.Wrap
        text: "Redeem vouchers on your mullvad.net account page. The plugin does not redeem them itself: the mullvad CLI only takes a voucher as a command-line argument, which other programs on this computer can read."
        color: p.dim
        font.family: p.font
        font.pixelSize: Style.font.caption
      }
      Button {
        text: "Open mullvad.net"
        iconText: "\uf08e"
        bordered: true
        foreground: p.fg; fontFamily: p.font
        onClicked: svc.openAccountPage()
      }

      PanelSeparator { width: parent.width; foreground: p.fg }
      PanelSectionHeader { text: "DEVICES (" + (svc ? svc.devices.length : 0) + " OF 5)"; foreground: p.fg; fontFamily: p.font }
      Repeater {
        model: svc ? svc.devices : []
        delegate: Item {
          id: deviceRow
          required property var modelData
          readonly property bool current: modelData.name === root.account.deviceName
          width: body.width
          height: Style.space(40)
          Column {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text {
              textFormat: Text.PlainText
              text: modelData.name + (deviceRow.current ? "  ·  this device" : "")
              color: deviceRow.current ? p.accent : p.fg
              font.family: p.font
              font.pixelSize: Style.font.body
            }
            Text {
              textFormat: Text.PlainText
              text: "Added " + String(modelData.created).slice(0, 10)
              color: p.dim
              font.family: p.font
              font.pixelSize: Style.font.caption
            }
          }
          PanelActionButton {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: !deviceRow.current
            iconText: ""
            tooltipText: "Revoke " + modelData.name
            foreground: p.fg
            hoverColor: p.urgent
            onClicked: p.confirm("Revoke " + modelData.name + "? It will be logged out of Mullvad.", "Revoke", function() { svc.revokeDevice(modelData.id || modelData.name) })
          }
        }
      }
    }

    // ---------------------------------------- not read yet
    Text {
      textFormat: Text.PlainText
      width: parent.width
      visible: svc && svc.installed && root.account.unknown === true
      wrapMode: Text.Wrap
      text: svc && svc.daemonUp ? "Checking your account…" : "Your account shows here once the Mullvad daemon is running."
      color: p.dim
      font.family: p.font
      font.pixelSize: Style.font.body
    }

    // ---------------------------------------- logged out
    Column {
      width: parent.width
      spacing: Style.spacing.lg
      visible: svc && svc.installed && !root.account.loggedIn && !root.account.unknown

      PanelSectionHeader { text: "LOG IN"; foreground: p.fg; fontFamily: p.font }
      // Revoked: removed from the account elsewhere. The daemon still knows
      // the number, so logging back in is one press.
      Text {
        textFormat: Text.PlainText
        width: parent.width
        visible: root.account.revoked === true
        wrapMode: Text.Wrap
        text: "This device was removed from your Mullvad account, so it cannot connect. Log in again to add it back."
        color: p.urgent
        font.family: p.font
        font.pixelSize: Style.font.body
      }
      Button {
        visible: root.account.revoked === true && !!root.account.number
        text: "Log in again"
        iconText: "\uf090"
        bordered: true
        active: true
        foreground: p.fg; fontFamily: p.font
        tooltipText: p.privacy ? "" : "As " + Model.maskAccount(root.account.number)
        onClicked: svc.login(root.account.number)
      }
      Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.Wrap
        text: "Enter your 16-digit Mullvad account number. It is sent to the Mullvad daemon only, never written to disk by this plugin."
        color: p.dim
        font.family: p.font
        font.pixelSize: Style.font.caption
      }
      Row {
        width: parent.width
        spacing: Style.spacing.md
        TextField {
          id: accountField
          width: parent.width - loginButton.width - Style.spacing.md
          placeholderText: "0000 0000 0000 0000"
          password: true
          foreground: p.fg
          font.family: p.font
          validator: RegularExpressionValidator { regularExpression: /^[\d ]{0,19}$/ }
          onAccepted: loginButton.clicked()
        }
        Button {
          id: loginButton
          text: "Log in"
          bordered: true
          foreground: p.fg; fontFamily: p.font
          onClicked: { svc.login(accountField.text); accountField.text = "" }
        }
      }
      Button {
        text: "Create a new account"
        bordered: true
        foreground: p.fg; fontFamily: p.font
        onClicked: p.confirm("Create a new Mullvad account and log in to it?", "Create", function() { svc.createAccount() })
      }
    }
  }
}
