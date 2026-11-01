import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Window
import "PreviewGrid.js" as PreviewGrid
import QtQuick.Effects
import QtQuick.Shapes
import QtMultimedia
import Qt.labs.folderlistmodel
import qs.Commons
import qs.Ui

Item {
  id: root

  // ------------------------------------------------------------------ state
  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string bgSourceTypeFile: stateHome + "/omarchy/current/bg-source-type"
  readonly property string bgSourcePathFile: stateHome + "/omarchy/current/bg-source-path"

  property bool opened: false

  // Plugin context (set by Service.qml): own IPC target + plugin dir for bins.
  property string ipcTarget: "io.github.avillagran.omarchy-animated-backgrounds"
  property string pluginDir: ""

  // The same carousel chooses for the background or for the screensaver.
  property bool pickingScreensaver: false
  property var categories: [ { id: "audio", label: "Screensaver", color: "#89dceb" } ]
  property int categoryIndex: 0
  property bool parallaxEnabled: true
  property bool amigaLoop: true
  property bool amigaMute: false

  property var currentItems: []
  property int selectedIndex: 0
  property bool itemsLoaded: false
  // When true, the next listProc result swaps items WITHOUT blanking the
  // selector (category transitions and live dir-watch refreshes). Only the
  // initial open uses the blanking path.
  property bool silentListReload: false
  property int parallaxResolution: 2
  property int audioResolution: 3

  // live ascii/audio effect previews — one daemon serves every visible slice
  property var fxCells: ({})
  property real fxVolume: 0
  property int receivedWindow: 0
  property int paintWindow: 0
  property real receivedFps: 0
  property real paintFps: 0
  property double measuredAt: Date.now()
  Timer {
    interval:1000;repeat:true;running:root.opened
    onTriggered: {
      var now=Date.now(),elapsed=Math.max(1,now-root.measuredAt)
      root.receivedFps=root.receivedWindow*1000/elapsed
      root.paintFps=root.paintWindow*1000/elapsed
      root.receivedWindow=0;root.paintWindow=0;root.measuredAt=now
    }
  }
  property var pixelGrid: ({})
  property var activePreviewCanvas: null
  property bool fxDaemonUp: false
  property int fxFramesRcvd: 0
  property string fxLastErr: ""
  property int fxLinesSeen: 0
  property int fxSubCount: 0
  property int fxTick: 0
  property int fxVisCount: 0

  // Live previews repaint every cell from JavaScript, so a slow machine trades
  // grid and frame rate for smoothness. A fast one never leaves the first level.
  readonly property var previewLevels: [
    { cols: 174, rows: 50, fps: 60 },
    { cols: 116, rows: 33, fps: 30 },
    { cols: 87, rows: 25, fps: 20 }
  ]
  readonly property int previewPaintBudgetMs: 40
  readonly property int previewSettlePaints: 6
  readonly property int previewSamplePaints: 12
  property int previewLevel: 0
  property real previewPaintMs: 0
  property var previewPaints: []
  function notePreviewPaint(ms) {
    root.previewPaints.push(ms)
    var paints = root.previewPaints.slice(root.previewSettlePaints)
    if (paints.length < root.previewSamplePaints) return
    paints.sort(function(a, b) { return a - b })
    root.previewPaintMs = paints[Math.floor(paints.length / 2)]
    root.previewPaints = []
    if (root.previewPaintMs > root.previewPaintBudgetMs && root.previewLevel < root.previewLevels.length - 1)
      root.previewLevel += 1
  }

  function fxLine(line) {
    root.fxLinesSeen += 1
    var d
    try { d = JSON.parse(line) } catch (e) {
      root.fxLastErr = line.substring(0, 60)
      return
    }
    if (d.cells !== undefined && d.fx !== undefined) {
      root.fxLastErr = ""
      root.fxFramesRcvd += 1
      root.receivedWindow += 1
      root.fxVolume = d.volume || 0
      // fresh object every frame — reassigning the same map reference would
      // not trigger change notifications
      var m = {}
      for (var k in root.fxCells) m[k] = root.fxCells[k]
      m[d.fx] = d.cells
      root.fxCells = m
    }
  }

  function fxSub(fx, cols, rows, fps) {
    root.fxSubCount += 1
    if (!fxDaemon.running) return
    fxDaemon.write(JSON.stringify({ cmd: "sub", fx: fx, cols: cols, rows: rows, fps: fps }) + "\n")
  }

  function fxUnsub(fx) {
    if (!fxDaemon.running) return
    fxDaemon.write(JSON.stringify({ cmd: "unsub", fx: fx }) + "\n")
  }

  property string originalType: ""
  property string originalPath: ""

  // Live-refresh: path the user had selected before a re-list, restored by
  // listProc when the refreshed items still contain it.
  property string keepSelectionPath: ""

  // Sequential category transition: collapse -> swap -> expand.
  property bool collapsing: false
  property int pendingCategory: -1

  // Visual language copied 1:1 from the Omarchy image picker.
  property bool showLabels: true
  property color dimColor: Color.background || "#101315"
  property color foreground: (Color.imagePicker && Color.imagePicker.text) || Color.foreground || "#e6edf3"
  property color scrim: (Color.imagePicker && Color.imagePicker.scrim) || "#90101315"
  property color selectedBorder: (Color.imagePicker && Color.imagePicker.selectedBorder) || Color.accent || "#89dceb"
  property color unselectedBorder: (Color.imagePicker && Color.imagePicker.unselectedBorder) || "#557b8b92"
  property int expandedWidth: 768
  property int expandedHeight: 475
  property int sliceWidth: 108
  property int sliceHeight: 432
  property int sliceSpacing: -30
  property int skewOffset: 28
  property int headerH: 34
  property int catSpacing: 8

  onOpenedChanged: { root.receivedWindow=0; root.paintWindow=0; root.measuredAt=Date.now(); if (!opened) root.resetSelection() }

  function fileUrl(path) {
    if (!path) return ""
    if (path.indexOf("://") !== -1) return path
    return "file://" + path
  }

  function resetSelection() {
    root.itemsLoaded = false
    root.currentItems = []
    root.selectedIndex = 0
    root.categoryIndex = 0
    root.collapsing = false
    root.pendingCategory = -1
  }

  function scriptPath(name) {
    return root.pluginDir + "/" + name
  }

  function open() {
    root.opened = true
    root.itemsLoaded = false
    root.currentItems = []
    root.originalType="audio"
    root.loadCategory(0)
    readPathProc.running = true


    categoryFallbackTimer.restart()
  }

  function toggleParallax() {
    root.parallaxEnabled = !root.parallaxEnabled
    Quickshell.execDetached(["omarchy-shell", "-q", root.ipcTarget, "toggleParallax"])
  }

  function amigaActive() { return root.categories[root.categoryIndex].id === "amiga" }
  function audioActive() { return root.categories[root.categoryIndex].id === "audio" }

  function toggleAmigaLoop() {
    if (!root.amigaActive()) return
    Quickshell.execDetached([root.home + "/.config/omarchy/plugins/io.github.avillagran.omarchy-amiga/bin/omarchy-amiga", "toggle-loop"])
    root.amigaLoop = !root.amigaLoop
  }

  function toggleAmigaMute() {
    if (!root.amigaActive()) return
    Quickshell.execDetached([root.home + "/.config/omarchy/plugins/io.github.avillagran.omarchy-amiga/bin/omarchy-amiga", "toggle-mute"])
    root.amigaMute = !root.amigaMute
  }

  // The arrows change how fine the selected scene is drawn. A background shows
  // it right away behind the carousel; Escape puts everything back.
  readonly property int maxResolutionSteps: 4
  property int resolutionSteps: 0
  property string resolutionItem: ""
  property bool resolutionChanged: false
  readonly property int minFps: 20
  readonly property int maxFps: 240
  readonly property int fpsStep: 10
  property int fpsLimit: minFps
  readonly property string resolutionLabel: resolutionSteps === 0 ? "auto" : (resolutionSteps > 0 ? "+" : "") + resolutionSteps
  property bool fpsCounter: false
  function toggleFpsCounter() {
    root.fpsCounter=!root.fpsCounter
    Quickshell.execDetached([root.home+"/.local/bin/omarchy-ambient-background-select","--fps-counter"])
  }
  function stepResolution(delta) {
    const item=root.currentItems[root.selectedIndex]
    if (!item || item.type !== "audio") return
    const next=Math.max(-root.maxResolutionSteps,Math.min(root.maxResolutionSteps,root.resolutionSteps+delta))
    if (next === root.resolutionSteps) return
    root.resolutionSteps=next
    root.resolutionItem=item.path
    resolutionApplyTimer.restart()
  }
  function stepFpsLimit(delta) {
    const item=root.currentItems[root.selectedIndex]
    if (!item || item.type !== "audio") return
    const next=Math.max(root.minFps,Math.min(root.maxFps,root.fpsLimit+delta))
    if (next === root.fpsLimit) return
    root.fpsLimit=next
    root.resolutionItem=item.path
    resolutionApplyTimer.restart()
  }
  function sendTuning() {
    root.resolutionChanged=true
    Quickshell.execDetached([root.home+"/.local/bin/omarchy-ambient-background-select","--tune",root.resolutionItem,String(root.resolutionSteps),String(root.fpsLimit)])
  }
  function flushResolution() {
    if (!resolutionApplyTimer.running) return
    resolutionApplyTimer.stop()
    root.sendTuning()
  }
  function readResolution() {
    root.flushResolution()
    const item=root.currentItems[root.selectedIndex]
    root.resolutionSteps=0
    root.fpsLimit=root.minFps
    if (!item || item.type !== "audio") return
    resolutionRead.command=[root.home+"/.local/bin/omarchy-ambient-background-select","--tune-get",item.path]
    resolutionRead.running=true
  }
  onSelectedIndexChanged: readResolution()
  onCurrentItemsChanged: readResolution()

  function close(restore) {
    if (!restore) { root.applyCurrent(); return }
    resolutionApplyTimer.stop()
    if (root.resolutionChanged) Quickshell.execDetached([root.home+"/.local/bin/omarchy-ambient-background-select","--tune-revert"])
    root.resolutionChanged=false
    root.opened=false
  }
  function applyCurrent() {
    const item=root.currentItems[root.selectedIndex]
    const pending=resolutionApplyTimer.running && item && root.resolutionItem === item.path
    resolutionApplyTimer.stop()
    root.resolutionChanged=false
    if (item) Quickshell.execDetached([root.home+"/.local/bin/omarchy-ambient-background-select","--apply-ascii",item.path].concat(pending ? [String(root.resolutionSteps),String(root.fpsLimit)] : []))
    root.opened=false
  }
  function loadCategory(idx, silent) {
    const prev = root.currentItems[root.selectedIndex]
    root.keepSelectionPath = prev ? (prev.applied || prev.path) : ""
    root.silentListReload = silent === true
    if (!root.silentListReload) {
      root.itemsLoaded = false
      root.currentItems = []
    }
    root.categoryIndex = idx
    root.selectedIndex = 0
    const cat = root.categories[idx].id
    listProc.command = ["bash", root.scriptPath("bin/list.sh"), cat]
    listProc.running = true
  }

  function moveItem(dir) {
    if (root.collapsing) return
    const count = root.currentItems.length
    if (count === 0) return
    root.selectedIndex = (root.selectedIndex + dir + count) % count
  }

  // Phase 2 (after compression): swap category SILENTLY — keep the old items
  // on screen until the new list is parsed; blanking itemsLoaded here made
  // the whole selector (and scrim) disappear for a frame = visible flicker.
  Timer {
    id: collapseTimer
    interval: 260
    onTriggered: {
      const cat = root.categories[root.pendingCategory].id
      root.silentListReload = true
      listProc.command = ["bash", root.scriptPath("bin/list.sh"), cat]
      listProc.running = true
      root.selectedIndex = 0
      root.categoryIndex = root.pendingCategory
      root.collapsing = false
      root.pendingCategory = -1
      Qt.callLater(() => { if (root.opened) keyHandler.forceActiveFocus() })
    }
  }

  // ------------------------------------------------------------------ procs
  Process {
    id: readTypeProc
    command: ["cat", root.bgSourceTypeFile]
    stdout: StdioCollector {
      onStreamFinished: {
        root.originalType = this.text.trim()
        // Open on the category that matches the CURRENT background type
        // instead of always landing on IMAGES.
        let idx = 0
        for (let i = 0; i < root.categories.length; i++) {
          if (root.categories[i].id === root.originalType) { idx = i; break }
        }
        categoryFallbackTimer.stop()
        root.loadCategory(idx)
      }
    }
  }

  // Live ascii/audio effect daemon. One instance while the switcher is open;
  // every visible audio slice subscribes to its effect and streams real,
  // audio-reactive frames into its Canvas. Pure Rust, in-process rendering:
  // the companion omarchy-audio-background binary runs its --preview-daemon
  // mode (native effects wave/bars/donut/fire/starfield/life always work).
  Process {
    id: fxDaemon
    command: ["python3",home+"/.local/share/omarchy-ambient/selector/run-preview.py"]
    stdinEnabled: true
    running: root.opened && root.categories[root.categoryIndex].id === "audio"
    onRunningChanged: {
      if (running) {
        root.fxDaemonUp = true
      } else {
        root.fxDaemonUp = false
        root.fxCells = ({})
      }
    }
    stdout: SplitParser {
      onRead: function(line) { root.fxLine(line) }
    }
  }

  // delegates are created lazily by the carousel and may outlive the daemon's
  // startup race — a fast heartbeat tops up any slice the pre-warm missed
  Timer {
    interval: 800
    repeat: true
    running: root.opened && root.categories[root.categoryIndex].id === "audio"
    onTriggered: root.fxTick += 1
  }

  // Select the item matching the CURRENTLY APPLIED background (by its
  // applied path), falling back to the first item.
  function selectCurrentItem() {
    if (!root.itemsLoaded || root.currentItems.length === 0) return
    const current = root.originalPath
    if (!current) { root.selectedIndex = 0; return }
    for (let i = 0; i < root.currentItems.length; i++) {
      const item = root.currentItems[i]
      const applied = item.applied || item.path
      if (applied === current) { root.selectedIndex = i; return }
    }
    root.selectedIndex = 0
  }

  Timer {
    id: resolutionApplyTimer
    interval: 300
    onTriggered: root.sendTuning()
  }

  Process {
    id: pickingForRead
    command: [root.home+"/.local/bin/omarchy-ambient-background-select","--picking-for"]
    running: root.opened
    stdout: StdioCollector {
      onStreamFinished: root.pickingScreensaver=this.text.trim()==="screensaver"
    }
  }

  Process {
    id: fpsCounterRead
    command: [root.home+"/.local/bin/omarchy-ambient-background-select","--fps-counter-get"]
    running: root.opened
    stdout: StdioCollector {
      onStreamFinished: root.fpsCounter=this.text.trim()==="1"
    }
  }

  Process {
    id: resolutionRead
    stdout: StdioCollector {
      onStreamFinished: {
        if (resolutionApplyTimer.running) return
        const tuning=this.text.trim().split(" ")
        root.resolutionSteps=parseInt(tuning[0])||0
        root.fpsLimit=parseInt(tuning[1])||root.minFps
      }
    }
  }

  Process {
    id: readPathProc
    command: [root.home+"/.local/bin/omarchy-ambient-background-select","--current-choice"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.originalPath = this.text.trim()
        // Fresh boot / theme switch: bg-source-path may be stale or empty,
        // fall back to the canonical background symlink.
        if (!root.originalPath) readlinkProc.running = true
        else root.selectCurrentItem()
      }
    }
  }

  Process {
    id: readlinkProc
    command: ["readlink", "-f", home + "/.local/state/omarchy/current/background"]
    stdout: StdioCollector {
      onStreamFinished: {
        if (!root.originalPath) {
          root.originalPath = this.text.trim()
          root.selectCurrentItem()
        }
      }
    }
  }

  Process {
    id: readParallaxProc
    command: ["cat", root.bgSourceTypeFile.replace("bg-source-type", "bg-parallax")]
    stdout: StdioCollector {
      onStreamFinished: {
        root.parallaxEnabled = this.text.trim() !== "off"
      }
    }
  }

  Process {
    id: readParallaxResolutionProc
    command: ["cat", root.bgSourceTypeFile.replace("bg-source-type", "bg-parallax-resolution")]
    stdout: StdioCollector {
      onStreamFinished: {
        root.parallaxResolution = Math.max(1, Math.min(8, parseInt(this.text.trim()) || 2))
      }
    }
  }

  Process {
    id: readAudioResolutionProc
    command: ["cat", root.home + "/.local/state/omarchy/audio-background/state.json"]
    running: root.opened && root.audioActive()
    stdout: StdioCollector {
      onStreamFinished: {
        var m = /"resolution":\s*(\d+)/.exec(this.text)
        if (m) root.audioResolution = Math.max(1, Math.min(8, parseInt(m[1]) || 3))
      }
    }
  }

  Process {
    id: readAmigaLoopProc
    command: ["cat", root.home + "/.local/state/omarchy/amiga/loop"]
    running: root.opened && root.amigaActive()
    stdout: StdioCollector { onStreamFinished: root.amigaLoop = this.text.trim() !== "off" }
  }

  Process {
    id: readAmigaMuteProc
    command: ["cat", root.home + "/.local/state/omarchy/amiga/mute"]
    running: root.opened && root.amigaActive()
    stdout: StdioCollector { onStreamFinished: root.amigaMute = this.text.trim() === "on" }
  }

  // If the type read stalls (missing state file), still land on IMAGES.
  Timer {
    id: categoryFallbackTimer
    interval: 600
    repeat: false
    onTriggered: { if (!root.itemsLoaded) root.loadCategory(0) }
  }

  Process {
    id: listProc
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = this.text.split("\n").filter(l => l.trim().length > 0)
        const items = []
        for (const line of lines) {
          const parts = line.split("\t")
          if (parts.length >= 4) items.push({
            type: parts[0], path: parts[1], name: parts[2],
            preview: parts[3], media: parts[4] || "",
            applied: parts[5] || ""
          })
        }
        root.currentItems = items
        root.itemsLoaded = true
        // the expanded slice's live effect spawns via fxSync — nothing else
        // to pre-warm now that collapsed items show the static poster
        if (root.keepSelectionPath) {
          const keep = root.keepSelectionPath
          root.keepSelectionPath = ""
          root.selectedIndex = 0
          for (let i = 0; i < items.length; i++) {
            if ((items[i].applied || items[i].path) === keep) { root.selectedIndex = i; break }
          }
        } else {
          root.selectCurrentItem()
        }
        Qt.callLater(() => { if (root.opened) keyHandler.forceActiveFocus() })
      }
    }
  }

  // Live refresh: re-list the open category when its source dir changes
  // (user added/removed scenes while the panel is still open).
  readonly property string watchDir: {
    const cat = root.categories[root.categoryIndex].id
    if (cat === "animated") return home + "/Wallpapers/Animated"
    if (cat === "retro") return home + "/Wallpapers/Retro"
    if (cat === "amiga") return home + "/Wallpapers/Amiga"
    if (cat === "video") return home + "/Wallpapers/Videos"
    if (cat === "image") return home + "/Wallpapers/Images"
    return home + "/.config/omarchy/animated"
  }

  FolderListModel {
    id: dirWatcher
    folder: "file://" + root.watchDir
    showDirs: true
    showFiles: true
    onCountChanged: dirRefreshTimer.restart()
  }

  Timer {
    id: dirRefreshTimer
    interval: 500
    repeat: false
    onTriggered: {
      if (root.opened && root.itemsLoaded && !root.collapsing)
        root.loadCategory(root.categoryIndex, true)
    }
  }

  // The single IpcHandler for the whole plugin lives in Service.qml (target
  // = plugin id); it delegates toggle() here.
  function toggle() {
    if (root.opened) { root.close(true) } else { root.open() }
  }

  // ------------------------------------------------------------------ layer
  PanelWindow {
    id: panel
    visible: root.opened
    color: "transparent"

    anchors { top: true; bottom: true; left: true; right: true }

    WlrLayershell.namespace: "omarchy-ambient-selector"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened && root.itemsLoaded ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      visible: root.opened && root.itemsLoaded
      color: root.scrim

      MouseArea {
        anchors.fill: parent
        onClicked: root.close(true)
      }
    }

    // keyboard capture: ImagePicker-style priority handling
    Item {
      id: keyHandler
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.close(true)
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.applyCurrent()
          event.accepted = true
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab) {
          root.moveItem(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
          root.moveItem(1)
          event.accepted = true
        } else if (event.key === Qt.Key_Up) {
          root.stepResolution(1)
          event.accepted = true
        } else if (event.key === Qt.Key_Down) {
          root.stepResolution(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_F) {
          root.toggleFpsCounter()
          event.accepted = true
        } else if (root.amigaActive() && event.key === Qt.Key_L) {
          root.toggleAmigaLoop()
          event.accepted = true
        } else if (root.amigaActive() && event.key === Qt.Key_M) {
          root.toggleAmigaMute()
          event.accepted = true
        } else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal || event.key === Qt.Key_Asterisk) {
          // Shift on + and - types another key on many layouts.
          root.stepFpsLimit(root.fpsStep * (event.key === Qt.Key_Asterisk || (event.modifiers & Qt.ShiftModifier) ? 2 : 1))
          event.accepted = true
        } else if (event.key === Qt.Key_Minus || event.key === Qt.Key_Underscore) {
          root.stepFpsLimit(-root.fpsStep * (event.key === Qt.Key_Underscore || (event.modifiers & Qt.ShiftModifier) ? 2 : 1))
          event.accepted = true
        }
      }
    }

    // ------------------------------------------------------------ selector
    Column {
      id: selector
      visible: root.opened && root.itemsLoaded
      anchors.centerIn: parent
      spacing: root.catSpacing

      Repeater {
        model: root.categories

        delegate: Column {
          id: catDelegate
          required property int index
          required property var modelData
          readonly property bool active: root.categoryIndex === index

          spacing: 6

          // ---- category header (always visible, fixed width)
          Item {
            width: catCarousel.width
            height: root.headerH

            Text {
              anchors.centerIn: parent
              text: root.pickingScreensaver ? "Screensaver" : "Background"
              color: catDelegate.active ? catDelegate.modelData.color : Util.alpha(root.foreground, 0.6)
              font.family: Style.font.display
              font.pixelSize: catDelegate.active ? 18 : 15
              font.bold: catDelegate.active
              style: Text.Outline
              styleColor: Util.alpha(root.dimColor, 0.7)

              Behavior on color { ColorAnimation { duration: 200 } }
            }
          }

          // ---- items carousel (compress/expand around the category swap)
          Item {
            width: catCarousel.width
            height: catDelegate.active && !root.collapsing ? root.expandedHeight : 0
            clip: true

            Behavior on height {
              NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
            }

            // Exact ImagePicker slice mechanics.
            Item {
              id: catCarousel
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.verticalCenter: parent.verticalCenter
              width: root.expandedWidth + 13 * (root.sliceWidth + root.sliceSpacing)
              height: root.expandedHeight
              visible: catDelegate.active
              clip: false

              readonly property real itemStep: root.sliceWidth + root.sliceSpacing
              readonly property real previewX: (width - root.expandedWidth) / 2

              Repeater {
                model: catDelegate.active ? root.currentItems.length : 0

                delegate: Item {
                  id: slice
                  required property int index

                  readonly property var itemData: root.currentItems[index]
                  readonly property int relativeIndex: index - root.selectedIndex
                  readonly property bool selected: index === root.selectedIndex
                  readonly property bool nearby: Math.abs(relativeIndex) <= 16
                  readonly property bool liveMedia: !!slice.itemData && slice.itemData.media !== ""
                  property bool sourceActivated: nearby
                  onNearbyChanged: if (nearby) sourceActivated = true

                  visible: nearby
                  x: selected ? catCarousel.previewX : (relativeIndex < 0
                    ? catCarousel.previewX + relativeIndex * catCarousel.itemStep
                    : catCarousel.previewX + root.expandedWidth + root.sliceSpacing + (relativeIndex - 1) * catCarousel.itemStep)
                  width: selected ? root.expandedWidth : root.sliceWidth
                  height: selected ? root.expandedHeight : root.sliceHeight
                  y: selected ? 0 : (root.expandedHeight - root.sliceHeight) / 2
                  z: selected ? 100 : 50 - Math.min(Math.abs(relativeIndex), 40)

                  readonly property real skAbs: Math.abs(root.skewOffset)
                  readonly property real topLeft: root.skewOffset >= 0 ? skAbs : 0
                  readonly property real topRight: root.skewOffset >= 0 ? width : width - skAbs
                  readonly property real bottomRight: root.skewOffset >= 0 ? width - skAbs : width
                  readonly property real bottomLeft: root.skewOffset >= 0 ? 0 : skAbs

                  // skew mask
                  Item {
                    id: maskShape
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true

                    Shape {
                      anchors.fill: parent
                      antialiasing: true
                      preferredRendererType: Shape.CurveRenderer
                      ShapePath {
                        fillColor: "white"
                        strokeColor: "transparent"
                        startX: slice.topLeft; startY: 0
                        PathLine { x: slice.topRight; y: 0 }
                        PathLine { x: slice.bottomRight; y: slice.height }
                        PathLine { x: slice.bottomLeft; y: slice.height }
                        PathLine { x: slice.topLeft; y: 0 }
                      }
                    }
                  }

                  // preview content (masked)
                  Item {
                    anchors.fill: parent
                    layer.enabled: true
                    layer.smooth: false
                    layer.effect: MultiEffect {
                      maskEnabled: true
                      maskSource: maskShape
                      maskThresholdMin: 0.3
                      maskSpreadAtMin: 0.3
                    }

                    // static preview (thumb/poster) stays visible UNDER the
                    // live media so there is no black gap while it buffers.
                    Image {
                      id: staticPreview
                      anchors.fill: parent
                      visible: true
                      source: {
                        if (!slice.sourceActivated || !slice.itemData) return ""
                        return root.fileUrl(slice.itemData.preview)
                      }
                      fillMode: Image.PreserveAspectCrop
                      asynchronous: false
                      cache: true
                      smooth: true
                    }

                    // live video / animated playback, slightly oversized so the
                    // skew mask clips it and the real stroke draws on top.
                    // Only the slices that fit on screen play (expanded ± 3):
                    // each live MediaPlayer spins up a GStreamer pipeline, and
                    // 33 at once made the grid take many seconds to appear.
                    // Off-screen slices keep their static poster.
                    VideoOutput {
                      id: liveOut
                      visible: Math.abs(slice.relativeIndex) <= 3 && !!slice.itemData && slice.itemData.media !== "" && slice.itemData.type !== "audio"
                      x: -8; y: -8
                      width: parent.width + 16
                      height: parent.height + 16
                      // explicit skew mask on the video layer itself — some
                      // graphics backends composite video ABOVE the parent's
                      // masked layer, which would draw a rectangle over the
                      // slice shape
                      layer.enabled: true
                      layer.smooth: false
                      layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: maskShape
                        maskThresholdMin: 0.3
                        maskSpreadAtMin: 0.3
                      }

                      onVisibleChanged: if (!visible) slicePlayer.stop()

                      MediaPlayer {
                        id: slicePlayer
                        loops: MediaPlayer.Infinite
                        videoOutput: liveOut
                        // Previews are silent: do not create an audio device.
                        // Even a zero-volume AudioOutput synchronously probes
                        // PipeWire and can stall the whole shell if it hangs.
                        activeAudioTrack: -1
                        // Qt reselects track 0 as the source finishes loading.
                        onMediaStatusChanged: if (mediaStatus === MediaPlayer.LoadedMedia) activeAudioTrack = -1
                        source: (liveOut.visible && slice.itemData)
                          ? root.fileUrl(slice.itemData.media) : ""
                        onSourceChanged: if (source.toString() !== "") play()
                      }
                    }

                    // LIVE ascii/audio effect: real wrapper process per slice
                    // (audio-reactive), streamed from the fxlive daemon and
                    // drawn on a Canvas sized to the slice's own grid.
                    Item {
                      id: fxLive
                      // only the expanded slice animates live — collapsed neighbors show the
                      // static poster (last frame) below
                      visible: !!slice.itemData && slice.itemData.type === "audio" && slice.selected
                      anchors.fill: parent

                      // single shared grid — every slice for the same effect
                      // consumes one session, so resizing per-slice would
                      // desync the collapsed copies. 174x50 is one resolution
                      // step coarser than 232x66 (cells x4/3, like desktop
                      // res 3->4): bigger glyphs, half the render work. Below
                      // 232 cols the wordmark falls back to fractional sampling.
                      readonly property var fxLevel: root.previewLevels[root.previewLevel]
                      readonly property int fxCols: fxLevel.cols
                      readonly property int fxRows: fxLevel.rows
                      property bool subbed: false
                      property string subbedFx: ""
                      property string lastCells: ""
                      property double lastFrameAt: 0
                      property string fxName: (slice.itemData && slice.itemData.path) || ""

                      onFxNameChanged: {
                        if (subbed && subbedFx) { root.fxUnsub(subbedFx); subbed = false; subbedFx = "" }
                        fxSync()
                      }
                      onFxLevelChanged: {
                        if (subbed && subbedFx) { root.fxUnsub(subbedFx); subbed = false; subbedFx = "" }
                        lastCells = ""
                        fxSync()
                      }
                      onVisibleChanged: {
                        root.fxVisCount += visible ? 1 : -1
                        if (!visible) lastCells = ""
                        fxSync()
                      }

                      function fxSync() {
                        if (visible && root.fxDaemonUp && fxName) {
                          if (!subbed) {
                            root.fxSub(fxName, fxCols, fxRows, fxLevel.fps)
                            subbed = true
                            subbedFx = fxName
                          }
                        } else if (subbed && subbedFx) {
                          root.fxUnsub(subbedFx)
                          subbed = false
                          subbedFx = ""
                        }
                      }

                      Component.onCompleted: fxSync()
                      Component.onDestruction: if (subbed && subbedFx) root.fxUnsub(subbedFx)

                      Connections {
                        target: root
                        function onFxTickChanged() {
                          // watchdog: a live slice that stopped receiving
                          // frames lost its daemon session — re-subscribe
                          if (fxLive.subbed && fxLive.visible && Date.now() - fxLive.lastFrameAt > 2000) {
                            root.fxUnsub(fxLive.subbedFx)
                            fxLive.subbed = false
                            fxLive.subbedFx = ""
                            fxLive.fxSync()
                          } else {
                            fxLive.fxSync()
                          }
                        }
                        function onFxCellsChanged() {
                          if (!fxLive.visible) return
                          var d = root.fxCells[fxLive.fxName]
                          if (d === fxLive.lastCells) return
                          fxLive.lastCells = d || ""
                          fxLive.lastFrameAt = Date.now()
                          fxCanvas.requestPaint()
                        }
                      }

                      Canvas {
                        id: fxCanvas
                        smooth: false
                        antialiasing: false
                        property real previewDpr: Screen.devicePixelRatio
                        anchors.fill: parent
                        onPaint: {
                          root.paintWindow += 1
                          var ctx = getContext("2d")
                          ctx.reset()
                          ctx.fillStyle = "#07070d"
                          ctx.fillRect(0, 0, width, height)
                          var data = fxLive.lastCells
                          if (!data) return
                          var paintBegan = Date.now()
                          var cols = fxLive.fxCols, rows = fxLive.fxRows
                          // draw the grid slightly smaller than the box (same
                          // cell count, more breathing room around the band).
                          // Keep it close to 1.0: glyph size derives from the
                          // cell size, so aggressive scaling kills legibility.
                          var origin=fxCanvas.mapToItem(null,0,0)
                          var grid=PreviewGrid.metrics(width,height,cols,rows,previewDpr,origin.x,origin.y)
                          var cw=grid.cw,chh=grid.ch,x0=grid.x,y0=grid.y
                          root.activePreviewCanvas=fxCanvas
                          if(root.pixelGrid.cw!==grid.pixelWidth || root.pixelGrid.ch!==grid.pixelHeight || root.pixelGrid.dpr!==previewDpr)
                            root.pixelGrid={cw:grid.pixelWidth,ch:grid.pixelHeight,dpr:previewDpr,cols:cols,rows:rows}
                          ctx.imageSmoothingEnabled=false
                          ctx.font="bold "+grid.font+"px monospace"
                          ctx.textBaseline = "alphabetic"
                          ctx.globalAlpha=(fxLive.fxName==="matrix-reactive"||fxLive.fxName==="eye-reactive"||fxLive.fxName==="tunnel-reactive"||["neon-city","vector-highway","circuit-run","sunset-drive","live-terminal","data-globe","aquarium","jellyfish","cockpit","sand-clock","sand-clock-chladni","sand-clock-dunes","sand-clock-galaxy"].indexOf(fxLive.fxName)>=0)?1:0.78+Math.min(1,root.fxVolume*3)*0.22
                          var cells = data.split(";"), style = ""
                          for (var i = 0; i < cells.length; i++) {
                            var p = cells[i].split(",")
                            if (p.length < 4) continue
                            if (p[3] !== style) ctx.fillStyle = style = p[3]
                            if(p[2]==="█")ctx.fillRect(x0+parseInt(p[0])*cw,y0+parseInt(p[1])*chh,cw,chh)
                            else ctx.fillText(p[2], x0 + parseInt(p[0]) * cw, y0 + (parseInt(p[1]) + 0.82) * chh)
                          }
                          root.notePreviewPaint(Date.now() - paintBegan)
                        }
                      }
                    }

                    // audio glyph on collapsed neighbor slices
                    Text {
                      anchors.centerIn: parent
                      visible: !slice.selected && slice.itemData && slice.itemData.type === "audio" &&
                               (!slice.itemData.preview || slice.itemData.preview === slice.itemData.name)
                      text: "♪"
                      color: Util.alpha(root.foreground, 0.75)
                      font.pixelSize: 26
                      font.family: Style.font.display
                    }

                    // live parallax drift for static animated sources (SVG
                    // artwork): the slice breathes so the preview feels alive.
                    Image {
                      id: parallaxPreview
                      visible: slice.selected && !!slice.itemData &&
                               slice.itemData.type === "animated" && !slice.liveMedia &&
                               root.parallaxEnabled
                      width: parent.width * 1.2
                      height: parent.height * 1.2
                      source: visible && slice.itemData ? root.fileUrl(slice.itemData.preview) : ""
                      fillMode: Image.PreserveAspectCrop
                      asynchronous: false
                      smooth: true
                      property real t: 0
                      x: (parent.width - width) / 2 + Math.sin(t) * width * 0.035
                      y: (parent.height - height) / 2 + Math.cos(t * 0.83) * height * 0.03
                      NumberAnimation on t {
                        from: 0; to: Math.PI * 2
                        duration: 6000; loops: Animation.Infinite
                      }
                    }

                    // item label on expanded slice
                    Text {
                      visible: slice.selected && root.showLabels
                      anchors.bottom: parent.bottom
                      anchors.bottomMargin: 14
                      anchors.horizontalCenter: parent.horizontalCenter
                      width: parent.width - 40
                      text: slice.itemData ? slice.itemData.name : ""
                      color: root.foreground
                      style: Text.Outline
                      styleColor: Util.alpha(root.dimColor, 0.7)
                      font.pixelSize: Style.font.display
                      font.weight: Font.DemiBold
                      horizontalAlignment: Text.AlignHCenter
                      elide: Text.ElideRight
                    }

                    // dim unselected
                    Rectangle {
                      anchors.fill: parent
                      color: Util.alpha(root.dimColor, slice.selected ? 0 : 0.42)
                    }
                  }

                  // border stroke (skew shape) drawn on top of everything
                  Shape {
                    anchors.fill: parent
                    antialiasing: true
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                      fillColor: "transparent"
                      strokeColor: slice.selected ? root.selectedBorder : root.unselectedBorder
                      strokeWidth: slice.selected ? 3 : 1
                      startX: slice.topLeft; startY: 0
                      PathLine { x: slice.topRight; y: 0 }
                      PathLine { x: slice.bottomRight; y: slice.height }
                      PathLine { x: slice.bottomLeft; y: slice.height }
                      PathLine { x: slice.topLeft; y: 0 }
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: slice.selected ? root.applyCurrent() : root.selectedIndex = index
                  }
                }
              }
            }
          }
        }
      }
    }

    // ---------------------------------------------------------- hints bar
    Rectangle {
      visible: root.opened && root.itemsLoaded
      anchors {
        horizontalCenter: parent.horizontalCenter
        bottom: parent.bottom; bottomMargin: 40
      }
      width: hintsRow.width + 44
      height: 36
      radius: 18
      color: Util.alpha(root.dimColor, 0.85)
      border.width: 1
      border.color: Util.alpha(root.foreground, 0.12)

      Row {
        id: hintsRow
        anchors.centerIn: parent
        spacing: 18

        Text { color: root.foreground; font.pixelSize: 12; font.family: Style.font.display; text: "← → item" }
        Text {
          color: root.categories[root.categoryIndex].color
          font.pixelSize: 12; font.bold: true; font.family: Style.font.display
          text: "⏎ apply"
        }
        Text {
          visible: root.audioActive()
          color: root.foreground
          font.pixelSize: 12; font.family: Style.font.display
          text: "↑ ↓ resolution " + root.resolutionLabel
        }
        Text {
          visible: root.audioActive()
          color: root.foreground
          font.pixelSize: 12; font.family: Style.font.display
          text: "+ − limit " + root.fpsLimit + " fps · shift ×2"
        }
        Text {
          color: root.fpsCounter ? root.categories[root.categoryIndex].color : Util.alpha(root.foreground, 0.45)
          font.pixelSize: 12; font.family: Style.font.display
          text: "F fps " + (root.fpsCounter ? "on" : "off")
        }
        Text {
          color: (root.audioActive() || root.parallaxEnabled) ? root.foreground : Util.alpha(root.foreground, 0.4)
          font.pixelSize: 12; font.family: Style.font.display
          text: "live preview"
        }
        Text {
          visible: root.amigaActive()
          color: root.amigaLoop ? root.categories[root.categoryIndex].color : Util.alpha(root.foreground, 0.45)
          font.pixelSize: 12; font.family: Style.font.display
          text: "L loop " + (root.amigaLoop ? "on" : "off")
        }
        Text {
          visible: root.amigaActive()
          color: root.amigaMute ? Util.alpha(root.foreground, 0.45) : root.categories[root.categoryIndex].color
          font.pixelSize: 12; font.family: Style.font.display
          text: "M mute " + (root.amigaMute ? "on" : "off")
        }
        Text { color: root.foreground; font.pixelSize: 12; font.family: Style.font.display; text: "esc cancel" }
      }
    }
  }
}
