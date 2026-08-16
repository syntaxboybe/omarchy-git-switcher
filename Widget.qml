import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Git Switcher: shows the active global Git identity in the bar. Left click
// opens a popup listing every configured account; clicking one runs
// `git config --global user.name` / `user.email` for it. Accounts live in
// ~/.config/omarchy/git-switcher.json (see README for the shape).

BarWidget {
  id: root
  moduleName: "syntaxboybe.git-switcher"

  property string accountsPath: Quickshell.env("HOME") + "/.config/omarchy/git-switcher.json"
  property var accounts: []
  property string currentName: ""
  property string currentEmail: ""
  property string currentLabel: ""

  // Panel lifecycle contract for shell summon/hide/toggle routing.
  readonly property bool opened: card.open
  readonly property bool popoutSwitchClosing: false

  function open() { root.refresh(); card.open = true }
  function close() { card.open = false }
  function toggle() { if (card.open) card.open = false; else root.open() }
  function closeForPopoutSwitch() { card.open = false }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ----- accounts (config file) -----
  function loadAccounts() {
    accountsProc.running = true
  }

  function parseAccounts(raw) {
    var list = []
    var text = String(raw || "").trim()
    if (text !== "") {
      try {
        var data = JSON.parse(text)
        if (data && Array.isArray(data.accounts)) {
          for (var i = 0; i < data.accounts.length; i++) {
            var a = data.accounts[i] || {}
            list.push({
              label: String(a.label || a.name || ""),
              name: String(a.name || ""),
              email: String(a.email || "")
            })
          }
        }
      } catch (e) {
        list = []
      }
    }
    root.accounts = list
    root.matchActive()
  }

  // ----- identity (git config) -----
  function refresh() {
    root.loadAccounts()
    identityProc.running = true
  }

  function matchActive() {
    root.currentLabel = ""
    for (var i = 0; i < root.accounts.length; i++) {
      var a = root.accounts[i]
      if (a.email !== "" && a.email === root.currentEmail) { root.currentLabel = a.label; return }
    }
    for (var j = 0; j < root.accounts.length; j++) {
      var b = root.accounts[j]
      if (b.name !== "" && b.name === root.currentName) { root.currentLabel = b.label; return }
    }
  }

  function switchTo(account) {
    if (!account) return
    var name = String(account.name || "")
    var email = String(account.email || "")
    // Pass values as argv ($1/$2) so quotes in names/emails can't break the shell.
    switchProc.command = ["bash", "-c",
      'git config --global user.name "$1" && git config --global user.email "$2"',
      "git-switcher", name, email]
    switchProc.running = true
    card.open = false
  }

  // ----- processes -----
  Process {
    id: identityProc
    command: ["bash", "-c", 'git config --global user.name; git config --global user.email']
    stdout: StdioCollector {
      id: identityOut
      waitForEnd: true
    }
    onExited: function(exitCode, exitStatus) {
      var lines = String(identityOut.text || "").split("\n")
      root.currentName = (lines[0] || "").trim()
      root.currentEmail = (lines[1] || "").trim()
      root.matchActive()
    }
  }

  Process {
    id: switchProc
    onExited: function(exitCode, exitStatus) { root.refresh() }
  }

  // ----- accounts reader -----
  Process {
    id: accountsProc
    command: ["cat", root.accountsPath]
    stdout: StdioCollector {
      id: accountsOut
      waitForEnd: true
    }
    onExited: function(exitCode, exitStatus) {
      root.parseAccounts(accountsOut.text)
    }
  }

  Component.onCompleted: root.refresh()

  // ----- bar icon -----
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uDB80\uDEA2" // md-git (U+F02A2) — surrogate pair for the supplementary-plane glyph
    tooltipText: root.currentName !== ""
      ? "Git: " + (root.currentLabel !== "" ? root.currentLabel : root.currentName)
        + (root.currentLabel !== "" && root.currentName !== "" ? " (" + root.currentName + ")" : "")
      : "Git Switcher"
    onPressed: function(b) {
      if (b === Qt.RightButton) root.refresh()
      else root.toggle()
    }
  }

  IpcHandler {
    target: "syntaxboybe.git-switcher"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function refresh(): void { root.refresh() }
  }

  // ----- popup -----
  PopupCard {
    id: card
    anchorItem: button
    bar: root.bar
    owner: root
    contentWidth: Style.space(320)
    contentHeight: Style.space(320)

    readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
    readonly property color dim: Color.muted

    Column {
      anchors.fill: parent
      spacing: Style.space(10)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          text: "\uDB80\uDEA2" // md-git (U+F02A2)
          color: card.fg
          font.family: root.bar ? root.bar.fontFamily : "monospace"
          font.pixelSize: Style.font.title
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          width: parent.width
          text: "Git Accounts"
          color: card.fg
          font.family: root.bar ? root.bar.fontFamily : "monospace"
          font.pixelSize: Style.font.title
          elide: Text.ElideRight
        }
      }

      Text {
        width: parent.width
        text: root.currentName !== ""
          ? "Active: " + root.currentName + (root.currentEmail !== "" ? " <" + root.currentEmail + ">" : "")
          : "No global identity set"
        color: card.dim
        font.family: root.bar ? root.bar.fontFamily : "monospace"
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      // account list
      Column {
        width: parent.width
        visible: root.accounts.length > 0
        spacing: Style.space(6)

        Repeater {
          model: root.accounts

          AccountButton {
            required property var modelData
            width: parent.width
            label: modelData.label
            accountName: modelData.name
            active: root.currentLabel !== "" && root.currentLabel === modelData.label
            onClicked: root.switchTo(modelData)
          }
        }
      }

      // hint when no accounts configured
      Text {
        width: parent.width
        visible: root.accounts.length === 0
        text: "No accounts configured. Add entries to ~/.config/omarchy/git-switcher.json"
        color: card.dim
        font.family: root.bar ? root.bar.fontFamily : "monospace"
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      AccountButton {
        width: parent.width
        label: "Add Account"
        onClicked: { if (root.bar) root.bar.run("omarchy-launch-editor " + Util.shellQuote(root.accountsPath)) }
      }
    }
  }

  // ----- shared account row -----
  component AccountButton: Rectangle {
    property string label: ""
    property string accountName: ""
    property bool active: false
    signal clicked()

    implicitHeight: Math.max(38, nameText.implicitHeight + Style.space(16))
    radius: Style.cornerRadius
    color: active ? Style.selectedAccentFill : (hoverArea.containsMouse ? Style.hoverFill : "transparent")
    border.width: Style.spacing.hairline
    border.color: active ? "transparent" : Style.normalBorderColor

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      anchors.topMargin: Style.space(6)
      anchors.bottomMargin: Style.space(6)
      spacing: Style.space(8)

      // green dot marks the active account (opacity keeps alignment stable)
      Rectangle {
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: Style.space(8)
        Layout.preferredHeight: Style.space(8)
        radius: Style.space(4)
        color: "#4ade80"
        opacity: parent.parent.active ? 1 : 0
      }

      // account icon
      Text {
        Layout.alignment: Qt.AlignVCenter
        text: "\uDB80\uDC04" // md-account (U+F0004)
        color: card.dim
        font.family: root.bar ? root.bar.fontFamily : "monospace"
        font.pixelSize: Style.font.heading
      }

      Text {
        id: nameText
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        text: (parent.parent.label !== "" ? parent.parent.label : parent.parent.accountName)
          + (parent.parent.label !== "" && parent.parent.accountName !== ""
            ? " (" + parent.parent.accountName + ")" : "")
        color: card.fg
        font.family: root.bar ? root.bar.fontFamily : "monospace"
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }
    }

    HoverHandler {
      id: hoverArea
    }

    MouseArea {
      anchors.fill: parent
      onClicked: parent.clicked()
    }
  }
}
