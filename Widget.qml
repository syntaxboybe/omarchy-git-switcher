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
  property int maxConfigBytes: 65536
  property int maxAccounts: 64
  property int maxFieldLength: 256
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

  function utf8ByteLength(value) {
    var bytes = 0
    for (var i = 0; i < value.length; i++) {
      var code = value.charCodeAt(i)
      if (code >= 0xD800 && code <= 0xDBFF && i + 1 < value.length) {
        var low = value.charCodeAt(i + 1)
        if (low >= 0xDC00 && low <= 0xDFFF) {
          code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
          i++
        }
      }
      if (code <= 0x7F) bytes += 1
      else if (code <= 0x7FF) bytes += 2
      else if (code <= 0xFFFF) bytes += 3
      else bytes += 4
      if (bytes > root.maxConfigBytes) return bytes
    }
    return bytes
  }

  function parseAccounts(raw) {
    var list = []
    var rawText = String(raw || "")
    var text = rawText.trim()
    if (utf8ByteLength(rawText) > root.maxConfigBytes || text === "") {
      root.accounts = list
      root.matchActive()
      return
    }

    try {
      var data = JSON.parse(text)
      if (!data || !Array.isArray(data.accounts) || data.accounts.length > root.maxAccounts) {
        root.accounts = list
        root.matchActive()
        return
      }

      for (var i = 0; i < data.accounts.length; i++) {
        var a = data.accounts[i]
        if (!a || typeof a !== "object" || Array.isArray(a)) {
          list = []
          break
        }

        var fields = ["label", "name", "email"]
        var valid = true
        for (var j = 0; j < fields.length; j++) {
          var field = fields[j]
          if (a[field] !== undefined
              && (typeof a[field] !== "string" || a[field].length > root.maxFieldLength)) {
            valid = false
            break
          }
        }
        if (!valid) {
          list = []
          break
        }

        list.push({
          label: a.label || a.name || "",
          name: a.name || "",
          email: a.email || ""
        })
      }
    } catch (e) {
      list = []
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
    command: ["head", "-c", String(root.maxConfigBytes + 1), "--", root.accountsPath]
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
    contentWidth: Style.space(330)
    contentHeight: Style.space(340)

    readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
    readonly property color dim: Color.muted

    Column {
      anchors.fill: parent
      spacing: Style.space(12)

      RowLayout {
        width: parent.width
        spacing: Style.space(8)

        Text {
          text: "\uDB80\uDEA2" // md-git (U+F02A2)
          color: "#60a5fa"
          font.family: root.bar ? root.bar.fontFamily : "monospace"
          font.pixelSize: Style.font.title
          Layout.alignment: Qt.AlignVCenter
        }

        Text {
          Layout.fillWidth: true
          text: "Git Accounts"
          color: card.fg
          font.family: root.bar ? root.bar.fontFamily : "monospace"
          font.pixelSize: Style.font.title
          font.bold: true
          elide: Text.ElideRight
          Layout.alignment: Qt.AlignVCenter
        }

        Rectangle {
          Layout.alignment: Qt.AlignVCenter
          implicitWidth: countText.implicitWidth + Style.space(12)
          implicitHeight: Style.space(20)
          radius: Style.space(10)
          color: Qt.rgba(0.38, 0.65, 0.98, 0.15)
          border.width: 1
          border.color: "#60a5fa"

          Text {
            id: countText
            anchors.centerIn: parent
            text: root.accounts.length + (root.accounts.length === 1 ? " ACCOUNT" : " ACCOUNTS")
            color: "#60a5fa"
            font.family: root.bar ? root.bar.fontFamily : "monospace"
            font.pixelSize: Style.font.caption - 1
            font.bold: true
          }
        }
      }

      // active account hero banner
      Column {
        width: parent.width
        visible: root.currentName !== ""
        spacing: Style.space(4)

        Text {
          width: parent.width
          text: "ACTIVE ACCOUNT"
          color: card.dim
          font.family: root.bar ? root.bar.fontFamily : "monospace"
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.1
        }

        Rectangle {
          width: parent.width
          implicitHeight: Math.max(54,
            activeName.implicitHeight
            + (root.currentEmail !== "" ? activeEmail.implicitHeight + Style.space(2) : 0)
            + Style.space(18))
          radius: Style.cornerRadius + 2
          color: Qt.rgba(0.2, 0.6, 1.0, 0.08)
          border.width: 1
          border.color: Qt.rgba(0.2, 0.6, 1.0, 0.35)

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            anchors.topMargin: Style.space(8)
            anchors.bottomMargin: Style.space(8)
            spacing: Style.space(10)

            // Glowing indicator icon
            Rectangle {
              Layout.alignment: Qt.AlignVCenter
              Layout.preferredWidth: Style.space(32)
              Layout.preferredHeight: Style.space(32)
              radius: Style.space(16)
              color: Qt.rgba(0.2, 0.8, 0.4, 0.15)
              border.width: 1
              border.color: "#4ade80"

              Text {
                anchors.centerIn: parent
                text: "\uDB80\uDC04" // md-account
                color: "#4ade80"
                font.family: root.bar ? root.bar.fontFamily : "monospace"
                font.pixelSize: Style.font.body
              }
            }

            Column {
              Layout.fillWidth: true
              spacing: Style.space(2)

              Text {
                id: activeName
                width: parent.width
                text: (root.currentLabel !== "" ? root.currentLabel : root.currentName)
                  + (root.currentLabel !== "" && root.currentName !== ""
                    ? " (" + root.currentName + ")" : "")
                color: card.fg
                font.family: root.bar ? root.bar.fontFamily : "monospace"
                font.pixelSize: Style.font.body
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                id: activeEmail
                width: parent.width
                visible: root.currentEmail !== ""
                text: root.currentEmail
                color: card.dim
                font.family: root.bar ? root.bar.fontFamily : "monospace"
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            // ACTIVE badge pill
            Rectangle {
              Layout.alignment: Qt.AlignVCenter
              implicitWidth: activeBadgeText.implicitWidth + Style.space(12)
              implicitHeight: Style.space(20)
              radius: Style.space(10)
              color: Qt.rgba(0.2, 0.8, 0.4, 0.18)
              border.width: 1
              border.color: "#4ade80"

              Text {
                id: activeBadgeText
                anchors.centerIn: parent
                text: "● ACTIVE"
                color: "#4ade80"
                font.family: root.bar ? root.bar.fontFamily : "monospace"
                font.pixelSize: Style.font.caption - 1
                font.bold: true
              }
            }
          }
        }
      }

      // fallback when no identity is set
      Text {
        width: parent.width
        visible: root.currentName === ""
        text: "No global identity set"
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

        Text {
          width: parent.width
          text: "SWITCH ACCOUNT (" + root.accounts.length + ")"
          color: card.dim
          font.family: root.bar ? root.bar.fontFamily : "monospace"
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.1
        }

        Repeater {
          model: root.accounts

          AccountButton {
            required property var modelData
            width: parent.width
            label: modelData.label
            accountName: modelData.name
            active: root.currentLabel !== "" ? root.currentLabel === modelData.label : root.currentName === modelData.name
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

      // Add Account button with + icon
      Rectangle {
        width: parent.width
        implicitHeight: Style.space(36)
        radius: Style.cornerRadius
        color: addHoverArea.containsMouse ? Style.hoverFill : "transparent"
        border.width: 1
        border.color: Qt.rgba(card.fg.r, card.fg.g, card.fg.b, 0.2)

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          spacing: Style.space(8)

          Text {
            text: "+"
            color: card.fg
            font.bold: true
            font.pixelSize: Style.font.body
          }

          Text {
            Layout.fillWidth: true
            text: "Add Account"
            color: card.fg
            font.family: root.bar ? root.bar.fontFamily : "monospace"
            font.pixelSize: Style.font.bodySmall
          }
        }

        HoverHandler { id: addHoverArea }
        MouseArea {
          anchors.fill: parent
          onClicked: { if (root.bar) root.bar.run("omarchy-launch-editor " + Util.shellQuote(root.accountsPath)) }
        }
      }
    }
  }

  // ----- shared account row -----
  component AccountButton: Rectangle {
    property string label: ""
    property string accountName: ""
    property bool active: false
    signal clicked()

    implicitHeight: Math.max(40, nameText.implicitHeight + Style.space(16))
    radius: Style.cornerRadius
    color: active ? Qt.rgba(0.2, 0.8, 0.4, 0.12) : (hoverArea.containsMouse ? Style.hoverFill : "transparent")
    border.width: 1
    border.color: active ? "#4ade80" : (hoverArea.containsMouse ? Qt.rgba(card.fg.r, card.fg.g, card.fg.b, 0.2) : "transparent")

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      anchors.topMargin: Style.space(6)
      anchors.bottomMargin: Style.space(6)
      spacing: Style.space(10)

      // account icon
      Text {
        Layout.alignment: Qt.AlignVCenter
        text: "\uDB80\uDC04" // md-account
        color: active ? "#4ade80" : card.dim
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
        color: parent.parent.active ? "#4ade80" : card.fg
        font.family: root.bar ? root.bar.fontFamily : "monospace"
        font.pixelSize: Style.font.body
        font.bold: parent.parent.active
        elide: Text.ElideRight
      }

      // Checkmark for active account in list
      Text {
        visible: parent.parent.active
        text: "✓"
        color: "#4ade80"
        font.bold: true
        font.pixelSize: Style.font.body
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
