import QtQuick
import Quickshell
import Quickshell.Io
Item {
 id: root
 readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
 BackgroundSwitcher { id: switcher; pluginDir: root.pluginDir; ipcTarget: "avillagran.ambient-selector" }
 IpcHandler {
  target: "avillagran.ambient-selector"
  function toggle(): void { switcher.toggle() }
  function select(effect: string): void { for(var i=0;i<switcher.currentItems.length;i++) if(switcher.currentItems[i].path===effect) {switcher.selectedIndex=i;return;} }
  function savePreview(path: string): bool { return switcher.activePreviewCanvas ? switcher.activePreviewCanvas.save(path) : false }
  function close(): void { switcher.close(true) }
  function state(): string { return JSON.stringify({opened:switcher.opened,items:switcher.currentItems.length,selected:switcher.currentItems[switcher.selectedIndex],frames:switcher.fxFramesRcvd,receivedFps:switcher.receivedFps,paintFps:switcher.paintFps,previewLevel:switcher.previewLevel,resolutionSteps:switcher.resolutionSteps,fpsCounter:switcher.fpsCounter,fpsLimit:switcher.fpsLimit,previewPaintMs:switcher.previewPaintMs,pixelGrid:switcher.pixelGrid,daemon:switcher.fxDaemonUp,error:switcher.fxLastErr}) }
 }
}
