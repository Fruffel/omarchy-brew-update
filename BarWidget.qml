import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "fruffel.brew-update"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  readonly property int count: panelLoader.item ? panelLoader.item.count : 0
  readonly property bool checking: panelLoader.item ? panelLoader.item.checking === true : false
  readonly property bool updating: panelLoader.item ? panelLoader.item.updating === true : false
  readonly property bool busy: checking || updating
  readonly property string statusError: panelLoader.item ? String(panelLoader.item.statusError || "") : ""

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function runUpgrade() {
    if (panelLoader.item && panelLoader.item.runUpgrade) panelLoader.item.runUpgrade()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  // Always occupy a status slot, even when Homebrew is current.
  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "fruffel.brew-update"

    function refresh(): void { root.broadcast("refresh") }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function upgrade(): void { root.runUpgrade() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󱄖"
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    active: root.count > 0 || root.statusError !== ""
    tooltipText: {
      if (root.statusError !== "") return root.statusError
      if (root.updating) return "Upgrading Homebrew packages…"
      if (root.checking) return "Checking Homebrew…"
      if (root.count === 1) return "1 Homebrew package can be updated"
      if (root.count > 1) return root.count + " Homebrew packages can be updated"
      return "Homebrew is up to date"
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.refresh()
      else if (buttonCode === Qt.MiddleButton) root.runUpgrade()
      else root.toggle()
    }
  }
}
