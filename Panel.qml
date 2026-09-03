import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "fruffel.brew-update"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property var status: Model.emptyStatus()
  property bool startupHandled: false

  readonly property int count: Model.packageCount(status)
  readonly property bool checking: status.checking === true || statusProc.running
  readonly property bool updating: status.updating === true || quietUpgradeProc.running
  readonly property string statusError: String(status.error || "")
  readonly property bool includeCasks: setting("includeCasks", true) !== false
  readonly property bool greedyCasks: setting("greedyCasks", false) === true
  readonly property bool upgradeOnStart: setting("upgradeOnStart", true) !== false
  readonly property int pollMinutes: {
    var n = parseInt(String(setting("pollMinutes", 30)), 10)
    if (!isFinite(n)) n = 30
    if (n < 15) n = 15
    if (n > 1440) n = 1440
    return n
  }

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property color contentUrgent: bar ? bar.urgent : Color.urgent
  readonly property color contentDim: Qt.darker(contentForeground, 1.55)
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string statusScript: pluginDir + "/scripts/brew-status"
  readonly property string upgradeScript: pluginDir + "/scripts/brew-upgrade"
  readonly property string removeScript: pluginDir + "/scripts/brew-remove"
  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy/brew-update.json"

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function applyStatus(raw) {
    root.status = Model.parseStatus(raw)
  }

  function withFlags(command) {
    return command.concat(Model.scriptFlags(root.includeCasks, root.greedyCasks))
  }

  property int spinFrame: 0
  readonly property var spinFrames: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
  property bool showInstalled: false
  property string pendingRemove: ""
  readonly property bool removing: removeProc.running

  function refresh() {
    if (statusProc.running || quietUpgradeProc.running) return
    statusProc.command = withFlags(["bash", root.statusScript])
    statusProc.running = true
  }

  function upgradeQuiet() {
    if (quietUpgradeProc.running) return
    quietUpgradeProc.command = withFlags(["bash", root.upgradeScript, "--quiet", "--notify"])
    quietUpgradeProc.running = true
  }

  function runUpgrade() {
    if (quietUpgradeProc.running) return
    quietUpgradeProc.command = withFlags(["bash", root.upgradeScript, "--quiet", "--notify", "--report"])
    quietUpgradeProc.running = true
  }

  function removeApp(entry) {
    var name = String((entry && entry.name) || "").trim()
    if (name === "" || removeProc.running) return
    pendingRemove = name
    var args = ["bash", root.removeScript, name]
    if (entry && entry.kind === "cask") args.push("--cask")
    removeProc.command = args
    removeProc.running = true
  }

  function notify(head, body) {
    notifyProc.command = ["omarchy-notification-send", "-g", Model.icon(), "--app-name", "Homebrew", String(head || ""), String(body || "")]
    notifyProc.running = true
  }

  function handleStartup() {
    if (root.startupHandled) return
    root.startupHandled = true
    if (root.upgradeOnStart) root.upgradeQuiet()
    else root.refresh()
  }

  onOpenedChanged: if (opened) {
    stateFile.reload()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyStatus(text())
    onLoadFailed: { /* first run has no file yet */ }
  }

  Process {
    id: statusProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.count === 0 && root.statusError === "")
        root.applyStatus(JSON.stringify({ ok: false, error: "Homebrew check failed", formulae: [], casks: [] }))
      stateFile.reload()
    }
  }

  Process {
    id: quietUpgradeProc
    stdout: StdioCollector { waitForEnd: true }
    onExited: function() {
      stateFile.reload()
    }
  }

  Process {
    id: removeProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      var label = root.pendingRemove !== "" ? root.pendingRemove : "Package"
      root.pendingRemove = ""
      if (exitCode === 0) root.notify(label + " removed", "")
      else root.notify(label + " could not be removed", "Run brew uninstall by hand to see why.")
      root.refresh()
    }
  }

  Process {
    id: notifyProc
    stdout: StdioCollector { waitForEnd: true }
  }

  // Braille spinner frames while checking or upgrading.
  Timer {
    id: spinTimer
    interval: 80
    running: root.updating || root.checking
    repeat: true
    onTriggered: root.spinFrame = (root.spinFrame + 1) % root.spinFrames.length
  }

  // Let the session settle before the first brew process.
  Timer {
    id: startupTimer
    interval: 45000
    running: true
    repeat: false
    onTriggered: root.handleStartup()
  }

  Timer {
    id: pollTimer
    interval: root.pollMinutes * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: false
    onTriggered: root.refresh()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onActivateRequested: root.runUpgrade()
      onReturnRequested: root.runUpgrade()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
        else if (t === "u" || t === "U") root.runUpgrade()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: content
          // Keep bordered controls off the Flickable clip edge so the
          // left stroke of the first button is not sheared off.
          x: 1
          width: panelFlick.width - 2
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "Homebrew"
            meta: Model.formatCheckedAt(root.status.checkedAt)
            detail: root.count > 0 ? (root.count + (root.count === 1 ? " update" : " updates")) : (root.statusError !== "" ? "Error" : "Current")
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            iconComponent: Component {
              Text {
                text: Model.icon()
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Text {
            visible: root.statusError !== ""
            width: parent.width
            text: root.statusError
            color: root.contentUrgent
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.statusError === "" && root.count === 0 && !root.updating
            width: parent.width
            text: "All Homebrew packages are current."
            color: root.contentDim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          PackageSection {
            visible: root.status.formulae.length > 0
            title: "FORMULAE"
            packages: root.status.formulae
          }

          PackageSection {
            visible: root.status.casks.length > 0
            title: "CASKS"
            packages: root.status.casks
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Button {
              visible: root.count > 0
              text: root.updating ? "Updating" : "Update all"
              iconText: root.updating ? root.spinFrames[root.spinFrame] : Model.icon()
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              bordered: true
              enabled: root.count > 0 && !root.checking && !root.updating && !root.removing
              opacity: (root.checking || root.updating || root.removing) ? 0.45 : 1
              onClicked: root.runUpgrade()
            }

            Button {
              text: root.checking ? "Checking" : "Check now"
              iconText: root.checking ? root.spinFrames[root.spinFrame] : ""
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              bordered: true
              enabled: !root.checking && !root.updating && !root.removing
              opacity: (root.checking || root.updating || root.removing) ? 0.45 : 1
              onClicked: root.refresh()
            }
          }

          Column {
            visible: root.status.installed.length > 0
            width: parent.width
            spacing: Style.space(8)

            Row {
              width: parent.width
              spacing: Style.space(8)

              PanelSectionHeader {
                width: parent.width - toggleInstalledButton.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                text: "INSTALLED (" + root.status.installed.length + ")"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
              }

              Button {
                id: toggleInstalledButton
                text: root.showInstalled ? "Hide" : "Show"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                bordered: true
                onClicked: root.showInstalled = !root.showInstalled
              }
            }

            PackageSection {
              visible: root.showInstalled
              title: ""
              packages: root.status.installed
              showRemove: true
            }
          }
        }
      }
    }
  }

  component PackageSection: Column {
    id: sectionRoot
    property string title: ""
    property var packages: []
    property bool showRemove: false

    width: parent ? parent.width : implicitWidth
    spacing: Style.space(8)

    PanelSectionHeader {
      visible: title !== ""
      text: title
      foreground: root.contentForeground
      fontFamily: root.contentFontFamily
    }

    Repeater {
      model: packages

      delegate: Item {
        id: entryRow
        required property var modelData
        property bool armed: false
        width: parent ? parent.width : 0
        implicitHeight: row.implicitHeight

        Timer {
          id: disarmTimer
          interval: 3000
          repeat: false
          onTriggered: entryRow.armed = false
        }

        Row {
          id: row
          width: parent.width
          spacing: Style.space(8)

          Text {
            id: nameText
            width: Math.max(60, parent.width * 0.42)
            anchors.verticalCenter: parent.verticalCenter
            text: String(modelData.name || "")
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Text {
            width: Math.max(60, parent.width - nameText.width - (sectionRoot.showRemove ? removeButton.width + Style.space(8) : 0) - Style.space(8))
            anchors.verticalCenter: parent.verticalCenter
            text: Model.versionLine(modelData) + (modelData.pinned ? " (pinned)" : "")
            color: root.contentDim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignRight
          }

          Button {
            id: removeButton
            visible: sectionRoot.showRemove
            text: entryRow.armed ? "Sure?" : "Remove"
            foreground: entryRow.armed ? root.contentUrgent : root.contentForeground
            fontFamily: root.contentFontFamily
            bordered: true
            enabled: !root.checking && !root.updating && !root.removing
            opacity: (root.checking || root.updating || root.removing) ? 0.45 : 1
            onClicked: {
              if (entryRow.armed) {
                entryRow.armed = false
                root.removeApp(modelData)
              } else {
                entryRow.armed = true
                disarmTimer.restart()
              }
            }
          }
        }
      }
    }
  }
}
