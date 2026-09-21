import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "martinh.weather-globe"
  ipcTarget: "martinh.weather-globe"

  readonly property string home: Quickshell.env("HOME")
  readonly property string pkgDir: home + "/.config/omarchy/weather-globe"
  readonly property string stateDir: home + "/.local/state/omarchy/weather-globe"
  readonly property string scriptPath: pkgDir + "/render.sh"
  readonly property string setProjectionPath: pkgDir + "/set-projection.sh"
  readonly property string setZoomPath: pkgDir + "/set-zoom.sh"
  readonly property string setTemperaturePath: pkgDir + "/set-temperature.sh"
  readonly property string logPath: stateDir + "/render.log"
  readonly property string projectionPath: stateDir + "/projection"
  readonly property string zoomPath: stateDir + "/zoom-location"
  readonly property string temperaturePath: stateDir + "/show-temperature"

  readonly property var projectionOptions: [
    { value: "", label: "Classic (default)" },
    { value: "orthographic", label: "Orthographic (globe)" },
    { value: "rectangular", label: "Rectangular (flat map)" },
    { value: "mercator", label: "Mercator" },
    { value: "mollweide", label: "Mollweide" },
    { value: "peters", label: "Peters" },
    { value: "azimuthal", label: "Azimuthal" },
    { value: "lambert", label: "Lambert" },
    { value: "polyconic", label: "Polyconic" },
    { value: "bonne", label: "Bonne (heart-shaped)" },
    { value: "hemisphere", label: "Hemisphere" },
    { value: "gnomonic", label: "Gnomonic" },
    { value: "tsc", label: "TSC (cube faces)" },
    { value: "ancient", label: "Ancient (flat earth)" },
    { value: "equal_area", label: "Equal area" }
  ]

  property bool refreshing: false
  property string projection: ""
  property bool zoomLocation: false
  property bool showTemperature: false
  property real lastEpoch: 0
  property string lastLine: ""
  property string nowLabel: "never run"

  function refresh() {
    if (refreshProc.running) return
    root.refreshing = true
    refreshProc.running = true
  }

  function setProjection(value) {
    if (value === root.projection) return
    root.projection = value
    setProjectionProc.command = [root.setProjectionPath, value]
    setProjectionProc.running = true
  }

  function setZoom(value) {
    if (value === root.zoomLocation) return
    root.zoomLocation = value
    setZoomProc.command = [root.setZoomPath, value ? "1" : "0"]
    setZoomProc.running = true
  }

  function setTemperature(value) {
    if (value === root.showTemperature) return
    root.showTemperature = value
    setTemperatureProc.command = [root.setTemperaturePath, value ? "1" : "0"]
    setTemperatureProc.running = true
  }

  function parseLog(text) {
    var lines = String(text || "").split("\n")
    var ts = null
    var status = ""
    for (var i = 0; i < lines.length; i++) {
      var m = lines[i].match(/^=== (.+) ===$/)
      if (m) {
        ts = m[1]
        status = ""
      } else if (/^(OK|ERROR|WARN):/.test(lines[i])) {
        status = lines[i]
      }
    }
    root.lastEpoch = ts ? Date.parse(ts) : 0
    root.lastLine = status
    root.updateNowLabel()
  }

  function updateNowLabel() {
    if (!root.lastEpoch) {
      root.nowLabel = "never run"
      return
    }
    var diffMin = Math.max(0, Math.round((Date.now() - root.lastEpoch) / 60000))
    if (diffMin < 1) root.nowLabel = "just now"
    else if (diffMin < 60) root.nowLabel = diffMin + "m ago"
    else root.nowLabel = Math.floor(diffMin / 60) + "h " + (diffMin % 60) + "m ago"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  FileView {
    id: logFile
    path: root.logPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parseLog(text())
  }

  FileView {
    id: projectionFile
    path: root.projectionPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.projection = text().trim()
    onLoadFailed: root.projection = ""
  }

  FileView {
    id: zoomFile
    path: root.zoomPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.zoomLocation = text().trim() === "1"
    onLoadFailed: root.zoomLocation = false
  }

  FileView {
    id: temperatureFile
    path: root.temperaturePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.showTemperature = text().trim() === "1"
    onLoadFailed: root.showTemperature = false
  }

  Process {
    id: refreshProc
    command: [root.scriptPath]
    onExited: function(exitCode) {
      root.refreshing = false
      logFile.reload()
      if (root.bar) {
        root.bar.run(exitCode === 0
          ? "omarchy-notification-send 'Weather Globe' 'Background updated'"
          : "omarchy-notification-send -u critical 'Weather Globe' 'Render failed, see render.log'")
      }
    }
  }

  Process {
    id: setProjectionProc
    onExited: function() { root.refresh() }
  }

  Process {
    id: setZoomProc
    onExited: function() { root.refresh() }
  }

  Process {
    id: setTemperatureProc
    onExited: function() { root.refresh() }
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: root.updateNowLabel()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.refreshing ? "" : ""
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: "Weather Globe — updated " + root.nowLabel
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(290))
    contentHeight: panel.fittedContentHeight(col.implicitHeight, Style.space(480))

    Column {
      id: col
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.space(10)

      Text {
        textFormat: Text.PlainText
        text: "Weather Globe"
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }

      Text {
        textFormat: Text.PlainText
        text: (root.refreshing ? "Refreshing…" : "Updated " + root.nowLabel)
          + (root.lastLine ? ("\n" + root.lastLine) : "")
        color: Qt.darker(root.bar.foreground, 1.3)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
        width: parent.width
      }

      PanelSeparator {
        width: parent.width
        foreground: root.bar.foreground
      }

      Dropdown {
        width: parent.width
        label: "Projection"
        value: root.projection
        options: root.projectionOptions
        onChanged: function(v) { root.setProjection(v) }
      }

      Toggle {
        width: parent.width
        label: "Zoom to location"
        description: "Centers and zooms on your weather location. Crops Rectangular/Azimuthal to that region; other projections fall back to the classic globe while on."
        foreground: root.bar.foreground
        checked: root.zoomLocation
        onClicked: root.setZoom(!root.zoomLocation)
      }

      Toggle {
        width: parent.width
        label: "Show temperature"
        description: "Adds a temperature label for your location and nearby cities. Only visible while Zoom to location is also on."
        foreground: root.bar.foreground
        checked: root.showTemperature
        onClicked: root.setTemperature(!root.showTemperature)
      }

      Button {
        width: parent.width
        text: root.refreshing ? "Refreshing…" : "Refresh now"
        fontFamily: root.bar.fontFamily
        foreground: root.bar.foreground
        bordered: true
        onClicked: root.refresh()
      }
    }
  }
}
