import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.hunterseeker101.alienfx"
  ipcTarget: "io.github.hunterseeker101.alienfx"
  manageIpc: false

  // ---- State -------------------------------------------------------------
  // Zone mapping (fixed here and everywhere below):
  //   QML zoneA -> daemon zone "left"   (shown as ZONE A)
  //   QML zoneB -> daemon zone "right"  (shown as ZONE B)
  // Which physical light each one drives on this Aurora R7 is not confirmed
  // yet; the pairing only has to stay consistent, which it does.
  //
  // alienfx-lightd is write-only: it applies commands but has no query for
  // current hardware state (and the old sysfs reads are stale -- verified:
  // they report black while the lights are actually lit). So everything the
  // panel shows is CLIENT-SIDE state, never a read-back: it starts from the
  // seed below and is then whatever the user last picked, persisted to a
  // state file so it survives bar reloads. See README.md.
  //
  // Seed (UI 0-15 scale) = this machine's verified lights at rewrite time:
  // zoneA/left = AlienFX Blue (0,8,15) = #0088FF, zoneB/right = Magenta
  // (15,0,10) = #FF00AA, brightness 10. Only alienfx-lightd changes the
  // lights on this machine, so the seed is accurate until the first send,
  // after which the state file is the source of truth. Edit the seed here if
  // your lights start out different.
  property var zoneA: ({ r: 0, g: 8, b: 15 })
  property var zoneB: ({ r: 15, g: 0, b: 10 })
  property int brightness: 10

  // Set when a send fails (daemon not running, alienfx-gui not on PATH, or
  // the daemon rejected the payload); cleared by the next successful send.
  property bool sendFailed: false

  // True between "a send was started" and "that send finished or failed".
  // Used to tell a normal exit from a process that never started at all
  // (quickshell does not emit exited() when the binary is missing).
  property bool attemptInFlight: false

  // Dirty flags: state that changed since the last send actually left.
  // quickshell's Process.running cannot be set true again while already
  // running, so without these a rapid second click would be silently dropped
  // and the panel would show a color the lights never received. Anything
  // marked while a send is in flight is picked up by the next pump.
  property bool zoneADirty: false
  property bool zoneBDirty: false
  property bool brightnessDirty: false

  // ---- Persistence -------------------------------------------------------
  // Same convention as other Omarchy plugins (e.g. crashdesk): XDG state
  // dir, created on startup, JSON file written atomically by FileView.
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy-alienfx"

  function isChan(v) {
    return typeof v === "number" && v === Math.round(v) && v >= 0 && v <= 15
  }

  function isColor(c) {
    return !!c && isChan(c.r) && isChan(c.g) && isChan(c.b)
  }

  function persistState() {
    stateFile.setText(JSON.stringify({ zoneA: zoneA, zoneB: zoneB, brightness: brightness }))
  }

  function adoptState(text) {
    var s = null
    try { s = JSON.parse(String(text || "")) } catch (e) { s = null }
    if (!s || !isColor(s.zoneA) || !isColor(s.zoneB) || !isChan(s.brightness)) {
      if (String(text || "").trim().length > 0)
        console.log("io.github.hunterseeker101.alienfx: state file invalid, keeping built-in defaults")
      return
    }
    zoneA = { r: s.zoneA.r, g: s.zoneA.g, b: s.zoneA.b }
    zoneB = { r: s.zoneB.r, g: s.zoneB.g, b: s.zoneB.b }
    brightness = s.brightness
  }

  // ---- Actions -----------------------------------------------------------
  function setZone(zoneId, r, g, b) {
    if (zoneId === "zoneA") {
      zoneA = { r: r, g: g, b: b }
      zoneADirty = true
    } else {
      zoneB = { r: r, g: g, b: b }
      zoneBDirty = true
    }
    persistState()
    root.sendNext()
  }

  function setBrightness(v) {
    var iv = Math.max(0, Math.min(15, Math.round(v)))
    brightness = iv
    brightnessDirty = true
    persistState()
    root.sendNext()
  }

  // alienfx-lightd REQUIRES both "zones" (non-empty) and "brightness" in
  // every request, and always applies brightness -- verified against the
  // daemon source, its byte-identical installed copy, and three live
  // rejection probes. Zones may be a subset, though: absent zones are left
  // alone by the hardware. So:
  //   - a zone change sends just that zone, plus current brightness;
  //   - a brightness change sends both zones' current values (a no-op for
  //     the lights as long as this widget is the only writer), plus the new
  //     brightness.
  // Anything that piled up while a previous send was in flight is coalesced
  // into the next one.
  function sendNext() {
    if (sendProc.running) return
    if (!zoneADirty && !zoneBDirty && !brightnessDirty) return
    var zones = {}
    if (brightnessDirty) {
      zones.left = Model.toDaemonColor(zoneA.r, zoneA.g, zoneA.b)
      zones.right = Model.toDaemonColor(zoneB.r, zoneB.g, zoneB.b)
    } else {
      if (zoneADirty) zones.left = Model.toDaemonColor(zoneA.r, zoneA.g, zoneA.b)
      if (zoneBDirty) zones.right = Model.toDaemonColor(zoneB.r, zoneB.g, zoneB.b)
    }
    var payload = { zones: zones, brightness: brightness }
    zoneADirty = false
    zoneBDirty = false
    brightnessDirty = false
    // No shell involved: each argument is its own argv entry, so the JSON
    // payload needs no quoting. alienfx-gui is expected on $PATH
    // (~/.local/bin, standard on Omarchy).
    attemptInFlight = true
    sendProc.command = ["alienfx-gui", "--send", JSON.stringify(payload)]
    sendProc.running = true
  }

  IpcHandler {
    target: "io.github.hunterseeker101.alienfx"
    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    running: true
    command: ["mkdir", "-p", root.stateDir]
  }

  FileView {
    id: stateFile
    path: root.stateDir + "/state.json"
    watchChanges: false
    atomicWrites: true
    printErrors: false // a missing file on first run is expected
    onLoaded: root.adoptState(String(text() || ""))
    onSaveFailed: console.log("io.github.hunterseeker101.alienfx: could not write state file")
  }

  Process {
    id: sendProc
    // Both channels must have a parser: quickshell closes a process's read
    // channel when no parser is attached, and alienfx-gui writes its reply
    // to stdout -- a closed pipe would kill it mid-reply (SIGPIPE) and every
    // send would look like a failure even when the daemon applied it.
    // Buffers reset on each start, so these hold only the latest run's text.
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: sendStderr; waitForEnd: true }

    onExited: function(exitCode, exitStatus) {
      root.attemptInFlight = false
      root.sendFailed = exitCode !== 0
      if (exitCode !== 0) {
        console.log("io.github.hunterseeker101.alienfx: alienfx-gui --send failed, exit " + exitCode
          + ": " + String(sendStderr.text || "").trim())
      }
      // Pump anything that changed while this send was running. Deferred one
      // event-loop turn (Qt.callLater) so quickshell has finished emitting
      // exited()/runningChanged() for this run before the next one starts.
      Qt.callLater(function() { root.sendNext() })
    }

    // quickshell does not emit exited() when the binary fails to start at
    // all (FailedToStart: it only logs a warning and clears running). The
    // running flag dropping while an attempt is still marked in flight means
    // exactly that case -- surface it instead of failing silently.
    onRunningChanged: {
      if (!sendProc.running && root.attemptInFlight) {
        root.attemptInFlight = false
        root.sendFailed = true
        console.log("io.github.hunterseeker101.alienfx: alienfx-gui failed to start -- is it on PATH?")
      }
    }
  }

  readonly property var blendedColor: Model.average(root.zoneA, root.zoneB)

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: Style.bar.iconSlot
    tooltipText: "AlienFX"
    onPressed: function(b) { root.toggle() }

    iconComponent: Component {
      Rectangle {
        width: Style.space(12)
        height: Style.space(12)
        radius: width / 2
        anchors.centerIn: parent
        color: Qt.rgba(root.blendedColor.r / 15, root.blendedColor.g / 15, root.blendedColor.b / 15, 1)
        opacity: 0.35 + 0.65 * (root.brightness / 15)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.25)
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        Text {
          text: "AlienFX Lighting"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          width: parent.width
        }

        Text {
          visible: root.sendFailed
          text: "The last lighting command failed — check that alienfx-lightd is running and alienfx-gui is on your PATH, then try again (details in this plugin's README)."
          color: root.bar.foreground
          opacity: 0.75
          wrapMode: Text.WordWrap
          width: parent.width
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        PanelSeparator { foreground: root.bar.foreground }

        ZoneSection {
          label: "ZONE A"
          current: root.zoneA
          onPicked: function(r, g, b) { root.setZone("zoneA", r, g, b) }
        }

        ZoneSection {
          label: "ZONE B"
          current: root.zoneB
          onPicked: function(r, g, b) { root.setZone("zoneB", r, g, b) }
        }

        PanelSeparator { foreground: root.bar.foreground }

        Column {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader { text: "BRIGHTNESS"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

          Row {
            width: parent.width
            spacing: Style.space(10)

            PanelSlider {
              id: brightSlider
              width: parent.width - brightLabel.width - parent.spacing
              anchors.verticalCenter: parent.verticalCenter
              bar: root.bar
              minimum: 0
              maximum: 15
              step: 1
              integer: true
              value: root.brightness
              onReleased: function(v) { root.setBrightness(v) }
            }

            Text {
              id: brightLabel
              text: root.brightness + " / 15"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }

        Text {
          text: "Swatches are 16 steps per channel, scaled to the daemon's full 0–255 range. Zone A sends to the daemon's left zone, Zone B to right — which physical light each drives isn't confirmed yet. What's shown is this widget's own remembered state (saved between sessions): the daemon can't be read back, so the panel can't display what's actually lit."
          color: root.bar.foreground
          opacity: 0.5
          wrapMode: Text.WordWrap
          width: parent.width
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }

  component ZoneSection: Column {
    id: sectionRoot
    property string label: ""
    property var current: ({ r: 0, g: 0, b: 0 })
    signal picked(int r, int g, int b)

    width: parent.width
    spacing: Style.space(8)

    PanelSectionHeader { text: sectionRoot.label; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

    Row {
      spacing: Style.space(8)

      Repeater {
        model: Model.presets
        Rectangle {
          id: swatch
          required property var modelData
          readonly property bool active: Model.sameColor(sectionRoot.current, modelData)
          readonly property var previewColor: modelData.swatch || modelData

          width: Style.space(26)
          height: Style.space(26)
          radius: Style.space(6)
          color: Qt.rgba(previewColor.r / 15, previewColor.g / 15, previewColor.b / 15, 1)
          border.width: active ? 2 : 1
          border.color: active ? root.bar.foreground : Qt.rgba(1, 1, 1, 0.2)

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: sectionRoot.picked(swatch.modelData.r, swatch.modelData.g, swatch.modelData.b)
          }
        }
      }
    }
  }
}
