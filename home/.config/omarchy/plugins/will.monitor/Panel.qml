import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

// Version étendue du widget Display d'Omarchy, inspirée des paramètres
// d'affichage de Windows : mode de projection (Win+P), disposition libre des
// écrans par glisser-déposer (les bords s'aimantent pour des jonctions
// exactes), et une carte de réglages indépendante par écran.
// Les changements passent par `display-ctl` (même dossier), qui les mémorise
// dans ~/.config/hypr/display.lua.
Panel {
  id: root
  moduleName: "omarchy.monitor"
  ipcTarget: "omarchy.monitor"
  manageIpc: false

  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the brightness + state methods below.
  property int brightnessPercent: 0
  property int pendingBrightnessPercent: 0
  property bool brightnessSetQueued: false
  property bool brightnessAvailable: false
  property string focusedMonitor: ""

  // ---- Disposition des écrans (display-ctl state) ----
  readonly property string ctl: Quickshell.env("HOME") + "/.config/omarchy/plugins/will.monitor/display-ctl"
  property string layoutMode: "extend"
  property bool hasExternal: false
  property var outputs: []
  property int minOverlap: 64
  // Écran mis en avant dans le schéma (clic, survol d'une carte, clavier).
  property string selectedOutput: ""
  // Position déposée en attente du retour de display-ctl, pour que l'écran
  // ne saute pas à son ancienne place pendant l'application.
  property var placementPreview: null
  // Fenêtre « Conserver ces modifications ? » : échéance (horloge du script)
  // et décalage avec l'horloge locale pour un compte à rebours juste.
  property real pendingDeadline: 0
  property real clockOffset: 0
  property real nowTick: Date.now() / 1000
  readonly property int keepSecondsLeft: pendingDeadline > 0
    ? Math.max(0, Math.ceil(pendingDeadline - (nowTick + clockOffset))) : 0
  property var queuedCommand: null

  // Carry sub-notch touchpad deltas between wheel events.
  property real wheelAccumulator: 0

  readonly property var projectionOptions: [
    { value: "pc", label: "Écran PC seul", icon: "󰌢" },
    { value: "duplicate", label: "Dupliquer", icon: "󰆏" },
    { value: "extend", label: "Étendre", icon: "󰍺" },
    { value: "second", label: "Second écran seul", icon: "󰍹" }
  ]
  readonly property var orientationOptions: [
    { value: "0", label: "Paysage" },
    { value: "1", label: "Portrait" },
    { value: "2", label: "Paysage (retourné)" },
    { value: "3", label: "Portrait (retourné)" }
  ]
  readonly property var scalePresets: ["1", "1.25", "1.5", "1.6", "2", "3"]

  // Écrans réglables : allumés (un écran en miroir reste réglable).
  readonly property var targets: {
    var list = []
    for (var i = 0; i < outputs.length; i++)
      if (outputs[i].enabled) list.push(outputs[i])
    return list
  }
  function outputByName(name) {
    for (var i = 0; i < outputs.length; i++)
      if (outputs[i].name === name) return outputs[i]
    return null
  }
  function outputNumber(name) {
    for (var i = 0; i < outputs.length; i++)
      if (outputs[i].name === name) return i + 1
    return 0
  }
  function outputTitle(o) {
    return o.internal ? "Écran du portable" : o.label
  }

  // ---- Réglages d'un écran (tout est calculé à partir de l'objet écran) ----
  // "2560x1440@359.98" -> { w, h, r }
  function parseMode(mode) {
    var m = /^(\d+)x(\d+)@([\d.]+)/.exec(String(mode || ""))
    return m ? { w: parseInt(m[1]), h: parseInt(m[2]), r: parseFloat(m[3]) } : null
  }
  function modeOf(o) { return o ? parseMode(o.saved.mode) : null }

  function resolutionOptions(o) {
    if (!o) return []
    var seen = {}
    var list = []
    for (var i = 0; i < o.modes.length; i++) {
      var m = parseMode(o.modes[i])
      if (!m) continue
      var key = m.w + "x" + m.h
      if (seen[key]) continue
      seen[key] = true
      list.push({ value: key, label: m.w + " × " + m.h + (list.length === 0 ? "  (recommandé)" : "") })
    }
    return list
  }
  function resolutionValue(o) {
    var m = modeOf(o)
    return m ? m.w + "x" + m.h : ""
  }
  function refreshOptions(o, resolution) {
    if (!o) return []
    var list = []
    for (var i = 0; i < o.modes.length; i++) {
      var m = parseMode(o.modes[i])
      if (m && m.w + "x" + m.h === resolution)
        list.push({ value: o.modes[i], label: (Math.round(m.r * 100) / 100) + " Hz" })
    }
    return list
  }
  function refreshValue(o) {
    var cur = modeOf(o)
    if (!cur) return ""
    var options = refreshOptions(o, resolutionValue(o))
    var best = ""
    var bestDist = 1e9
    for (var i = 0; i < options.length; i++) {
      var d = Math.abs(parseMode(options[i].value).r - cur.r)
      if (d < bestDist) { bestDist = d; best = options[i].value }
    }
    return best
  }
  function scaleValues(o) {
    var m = modeOf(o)
    return m ? Model.availableScales(scalePresets, m.w, m.h) : scalePresets
  }
  function activeScaleIndex(o) {
    var m = modeOf(o)
    if (!m) return -1
    return Model.matchingScaleIndex(scaleValues(o), o.saved.scale, m.w, m.h)
  }
  function effectiveScale(o, scale) {
    var m = modeOf(o)
    return m ? Model.cleanScale(scale, m.w, m.h) : Model.normalizeScale(scale)
  }
  function outputSummary(o) {
    var m = modeOf(o)
    if (!m) return o.name
    return o.name + (o.inches ? "  ·  " + o.inches + "\"" : "") + "  ·  " + m.w + "×" + m.h + "  ·  " + Math.round(m.r) + " Hz"
      + (o.mirrorOf !== "none" ? "  ·  miroir" : "")
  }

  // Rectangles logiques des écrans étendus (schéma « Disposition »).
  readonly property var layoutRects: {
    var list = []
    for (var i = 0; i < outputs.length; i++) {
      var o = outputs[i]
      if (!o.enabled || o.mirrorOf !== "none" || !o.width) continue
      var s = o.scale || 1
      var w = Math.round(o.width / s)
      var h = Math.round(o.height / s)
      if (o.transform % 2 === 1) { var t = w; w = h; h = t }
      list.push({ name: o.name, x: o.x, y: o.y, w: w, h: h, n: i + 1, internal: o.internal, inches: o.inches || 0 })
    }
    return list
  }
  // Schéma visible dès que plusieurs écrans sont côte à côte (Étendre, ou
  // Second écran seul avec plusieurs externes).
  readonly property bool showLayout: hasExternal && layoutRects.length > 1

  // ---- Curseur clavier ----
  // Chaque section est une ligne : j/k change de section, h/l se déplace
  // dans la ligne (ou bouge un curseur), Entrée valide / ouvre la liste.
  // Les sections d'un écran sont nommées "<type>@<écran>".
  property string focusSection: "projection"
  property int selectedIndex: 0
  property bool cursorActive: false
  property var dropdownRefs: ({})
  // Exposés pour les composants inline (qui ne voient pas les ids du panneau).
  readonly property bool layoutDragging: diagram.dragging
  function refocusKeys() { keyCatcher.forceActiveFocus() }
  property int openPopups: 0

  readonly property var textSizeStops: [9, 10, 11, 12, 14, 16, 20]
  property int textSizePreviewIndex: -1

  // A text-size change reflows the whole panel, which slides rows under a
  // stationary pointer and fires synthetic hover. While true, hover is not
  // allowed to hijack the keyboard focus section.
  property bool reflowingText: false
  function markReflowing() {
    root.reflowingText = true
    reflowSettle.restart()
  }

  readonly property var visibleSections: {
    var list = []
    if (pendingDeadline > 0) list.push("keep")
    if (brightnessAvailable) list.push("brightness")
    list.push("textsize")
    if (hasExternal) list.push("projection")
    if (showLayout) list.push("layout")
    for (var i = 0; i < targets.length; i++) {
      var n = targets[i].name
      list.push("resolution@" + n)
      list.push("refresh@" + n)
      list.push("orientation@" + n)
      list.push("scale@" + n)
    }
    return list
  }

  function sectionKind(section) { return String(section).split("@")[0] }
  function sectionOutput(section) { return outputByName(String(section).split("@")[1] || "") }

  function sectionCount(section) {
    var kind = sectionKind(section)
    if (kind === "keep") return 2
    if (kind === "projection") return projectionOptions.length
    if (kind === "layout") return layoutRects.length
    if (kind === "scale") return scaleValues(sectionOutput(section)).length
    if (kind === "resolution" || kind === "refresh" || kind === "orientation") return 1
    return 0
  }

  function sectionFirstIndex(section) {
    var kind = sectionKind(section)
    if (kind === "brightness" || kind === "textsize") return -1
    if (kind === "projection") return Math.max(0, indexOfValue(projectionOptions, layoutMode))
    if (kind === "layout") {
      for (var i = 0; i < layoutRects.length; i++) if (layoutRects[i].name === selectedOutput) return i
      return 0
    }
    if (kind === "scale") return Math.max(0, activeScaleIndex(sectionOutput(section)))
    return 0
  }

  function indexOfValue(options, value) {
    for (var i = 0; i < options.length; i++) if (options[i].value === value) return i
    return -1
  }

  function setFocus(section, index) {
    focusSection = section
    selectedIndex = index
    var o = sectionOutput(section)
    if (o) selectedOutput = o.name
    if (sectionKind(section) === "layout" && index >= 0 && index < layoutRects.length)
      selectedOutput = layoutRects[index].name
  }

  function moveCursor(delta) {
    var sections = visibleSections
    if (!sections || sections.length === 0) return
    var sIdx = sections.indexOf(focusSection)
    var next = sIdx < 0 ? 0 : Math.max(0, Math.min(sections.length - 1, sIdx + delta))
    setFocus(sections[next], sectionFirstIndex(sections[next]))
  }

  function moveCursorH(delta) {
    var kind = sectionKind(focusSection)
    if (kind === "brightness") { adjustBrightness(delta * 5); return }
    if (kind === "textsize") { adjustTextSize(delta); return }
    var count = sectionCount(focusSection)
    if (count <= 1) return
    setFocus(focusSection, Math.max(0, Math.min(count - 1, selectedIndex + delta)))
  }

  function adjustBrightness(delta) {
    if (!brightnessAvailable) return
    setBrightness(root.brightnessPercent + delta)
  }

  function activateCursor() {
    var i = selectedIndex
    var kind = sectionKind(focusSection)
    var o = sectionOutput(focusSection)
    if (kind === "keep") { i === 0 ? keepChanges() : revertChanges(); return }
    if (kind === "projection" && i >= 0 && i < projectionOptions.length) { setMode(projectionOptions[i].value); return }
    if (kind === "scale" && o) {
      var values = scaleValues(o)
      if (i >= 0 && i < values.length) setScale(o, values[i])
      return
    }
    var dd = dropdownRefs[focusSection]
    if (dd) dd.open()
  }

  function clampCursor() {
    var sections = visibleSections
    if (!sections || !sections.length) return
    if (sections.indexOf(focusSection) < 0) {
      setFocus(sections[0], sectionFirstIndex(sections[0]))
      return
    }
    var kind = sectionKind(focusSection)
    if (kind === "brightness" || kind === "textsize") { selectedIndex = -1; return }
    var count = sectionCount(focusSection)
    if (selectedIndex > count - 1) selectedIndex = count - 1
    if (selectedIndex < 0) selectedIndex = 0
  }

  function hoverSection(section, index) {
    if (root.reflowingText) return
    root.cursorActive = true
    setFocus(section, index)
  }

  // Keep the keyboard-focused row inside the viewport when the panel grows
  // taller than its allotted height.
  function ensureCursorVisible(item) {
    if (!item || !scrollArea) return
    var flick = scrollArea.contentItem
    if (!flick || flick.contentY === undefined) return
    var pt = item.mapToItem(flick.contentItem || flick, 0, 0)
    var top = pt.y
    var bottom = top + (item.height || 0)
    var viewTop = flick.contentY
    var viewBottom = viewTop + flick.height
    var margin = 6
    if (top < viewTop + margin) flick.contentY = Math.max(0, top - margin)
    else if (bottom > viewBottom - margin)
      flick.contentY = bottom + margin - flick.height
  }

  function brightnessIpc(percent) {
    var value = Number(percent)
    root.setBrightness(value)
    return "got " + root.pendingBrightnessPercent
  }

  function stateIpc() {
    return JSON.stringify({
      brightness: root.brightnessPercent,
      brightnessAvailable: root.brightnessAvailable,
      focusedMonitor: root.focusedMonitor,
      mode: root.layoutMode,
      outputs: root.outputs
    })
  }

  IpcHandler {
    target: "omarchy.monitor"

    function brightness(percent: string): string { return root.brightnessIpc(percent) }
    function state(): string { return root.stateIpc() }
    // omarchy-shell omarchy.monitor projection <pc|duplicate|extend|second|next>
    function projection(mode: string): string {
      if (mode === "next") {
        var i = root.indexOfValue(root.projectionOptions, root.layoutMode)
        mode = root.projectionOptions[(i + 1) % root.projectionOptions.length].value
      }
      root.setMode(mode)
      return mode
    }
    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function show() { root.open() }
    function hide() { root.close() }
  }

  function refresh() {
    if (!stateProc.running) stateProc.running = true
    if (!layoutProc.running) layoutProc.running = true
  }

  function setBrightness(value) {
    var percent = Model.clampBrightness(value)
    root.brightnessPercent = percent
    root.pendingBrightnessPercent = percent

    if (setBrightnessProc.running) {
      root.brightnessSetQueued = true
      return
    }

    root.brightnessSetQueued = false
    setBrightnessProc.command = ["omarchy-brightness-display", "--no-osd", "--monitor", root.focusedMonitor, percent + "%"]
    setBrightnessProc.running = true
  }

  function previewBrightness(value) {
    root.brightnessPercent = Model.clampBrightness(value)
    brightnessDebounce.restart()
  }

  function showBrightnessOsd(percent) {
    if (!bar || !bar.shell) return
    bar.shell.summon("omarchy.osd", JSON.stringify({
      icon: "brightness",
      value: percent
    }))
  }

  function brightnessName(percent) {
    return Model.brightnessName(percent)
  }

  // ---- Actions écran (toutes via display-ctl, sérialisées) ----
  function runCtl(args) {
    var command = [root.ctl].concat(args)
    if (actionProc.running) { root.queuedCommand = command; return }
    actionProc.command = command
    actionProc.running = true
  }

  function setMode(mode) {
    if (!root.hasExternal && mode !== "pc") return
    root.layoutMode = mode
    runCtl(["mode", mode])
  }

  // Envoie la disposition complète ({ écran: {x, y} }, px logiques).
  // display-ctl recolle les écrans et décale le tout en coordonnées positives.
  function placeLayout(layout) {
    var args = ["place"]
    for (var i = 0; i < layoutRects.length; i++) {
      var r = layoutRects[i]
      var p = layout[r.name] || r
      args.push(r.name, String(Math.round(p.x)), String(Math.round(p.y)))
    }
    // Garde la nouvelle disposition affichée pendant l'application.
    root.placementPreview = layout
    runCtl(args)
  }

  // Déplacement au clavier (H/J/K/L) : pousse l'écran d'un huitième de sa
  // taille puis le recolle au bord le plus proche.
  function nudgeSelected(dx, dy) {
    for (var i = 0; i < layoutRects.length; i++) {
      var r = layoutRects[i]
      if (r.name !== selectedOutput) continue
      var layout = Model.layoutAfterDrag(layoutRects, r.name, r.x + dx * r.w / 8, r.y + dy * r.h / 8, 0, minOverlap)
      if (layout[r.name].x !== r.x || layout[r.name].y !== r.y) placeLayout(layout)
      return
    }
  }

  // Résolution / fréquence / orientation : à confirmer, sinon retour en 15 s.
  function confirmSetting(o, setting) {
    if (!o) return
    runCtl(["confirm", o.name, setting])
  }

  function setResolution(o, resolution) {
    // Garde la fréquence actuelle si elle existe, sinon la plus élevée.
    var options = refreshOptions(o, resolution)
    if (!options.length) return
    var cur = modeOf(o)
    var chosen = options[0].value
    for (var i = 0; i < options.length; i++) {
      if (cur && Math.abs(parseMode(options[i].value).r - cur.r) < 0.5) { chosen = options[i].value; break }
    }
    confirmSetting(o, "mode=" + chosen)
  }

  function setScale(o, scale) {
    if (!o) return
    runCtl(["set", o.name, "scale=" + scale])
  }

  function keepChanges() {
    root.pendingDeadline = 0
    runCtl(["keep"])
  }

  function revertChanges() {
    root.pendingDeadline = 0
    runCtl(["revert"])
  }

  function applyLayout(raw) {
    var data
    try { data = JSON.parse(String(raw || "{}")) } catch (e) { return }
    root.layoutMode = data.mode || "extend"
    root.hasExternal = !!data.hasExternal
    root.minOverlap = data.minOverlap || 64
    root.outputs = data.outputs || []
    // L'aperçu de disposition reste affiché tant que display-ctl applique.
    if (!actionProc.running && !root.queuedCommand) root.placementPreview = null
    root.pendingDeadline = data.pendingDeadline || 0
    root.clockOffset = (data.now || Date.now() / 1000) - Date.now() / 1000
    root.nowTick = Date.now() / 1000

    if (!root.outputByName(root.selectedOutput) || !root.outputByName(root.selectedOutput).enabled) {
      root.selectedOutput = ""
      for (var j = 0; j < root.targets.length; j++)
        if (root.targets[j].focused) root.selectedOutput = root.targets[j].name
      if (!root.selectedOutput && root.targets.length) root.selectedOutput = root.targets[0].name
    }
  }

  // ---- Text size (shell base font + GTK text-scaling, via one CLI) ----
  function nearestTextStop(px) {
    var best = 0
    var bestDist = 1e9
    for (var i = 0; i < textSizeStops.length; i++) {
      var d = Math.abs(textSizeStops[i] - px)
      if (d < bestDist) { bestDist = d; best = i }
    }
    return best
  }

  function currentTextIndex() {
    return textSizePreviewIndex >= 0 ? textSizePreviewIndex : nearestTextStop(Style.font.baseSize)
  }

  function displayedTextPx() {
    return textSizePreviewIndex >= 0 ? textSizeStops[textSizePreviewIndex] : Style.font.baseSize
  }

  function setTextSize(px) {
    textScaleProc.command = ["omarchy-display-text-size", String(px)]
    if (!textScaleProc.running) textScaleProc.running = true
  }

  function adjustTextSize(deltaSteps) {
    var idx = currentTextIndex() + deltaSteps
    if (idx < 0) idx = 0
    if (idx > textSizeStops.length - 1) idx = textSizeStops.length - 1
    markReflowing()
    textSizePreviewIndex = idx
    setTextSize(textSizeStops[idx])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  onOpenedChanged: {
    if (opened) {
      refresh()
      var first = hasExternal ? "projection" : (brightnessAvailable ? "brightness" : "textsize")
      setFocus(first, sectionFirstIndex(first))
      cursorActive = false
    }
  }

  onBrightnessAvailableChanged: clampCursor()
  onOutputsChanged: clampCursor()
  onVisibleSectionsChanged: clampCursor()

  Timer {
    interval: 5000
    running: root.opened && !diagram.dragging
    repeat: true
    onTriggered: root.refresh()
  }

  // Compte à rebours de la confirmation ; le script rétablit lui-même à zéro.
  Timer {
    interval: 1000
    running: root.pendingDeadline > 0
    repeat: true
    onTriggered: {
      root.nowTick = Date.now() / 1000
      if (root.keepSecondsLeft <= 0) {
        root.pendingDeadline = 0
        refreshAfterRevert.restart()
      }
    }
  }

  Timer {
    id: refreshAfterRevert
    interval: 1500
    onTriggered: root.refresh()
  }

  Process {
    id: stateProc
    command: ["omarchy-monitor-state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        var brightness = String(lines[0] || "").trim()
        root.brightnessAvailable = brightness !== "unavailable" && brightness !== ""
        root.brightnessPercent = root.brightnessAvailable ? Math.max(0, Math.min(100, parseInt(brightness, 10))) : 0
        root.focusedMonitor = String(lines[5] || "").trim()
      }
    }
  }

  Process {
    id: layoutProc
    command: [root.ctl, "state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyLayout(text)
    }
  }

  Timer {
    id: brightnessDebounce
    interval: 180
    repeat: false
    onTriggered: root.setBrightness(root.brightnessPercent)
  }

  Process {
    id: setBrightnessProc
    stdout: StdioCollector { waitForEnd: true }
    // Do NOT call refresh() after a brightness set completes (see upstream
    // omarchy.monitor): re-reading races the driver and bounces to zero.
    onRunningChanged: {
      if (running) return
      if (root.brightnessSetQueued) {
        root.setBrightness(root.pendingBrightnessPercent)
      }
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var msg = String(text || "").trim()
        if (msg) Quickshell.execDetached(["omarchy-notification-send", "-g", "󰍹", msg])
      }
    }
    onRunningChanged: {
      if (running) return
      if (root.queuedCommand) {
        actionProc.command = root.queuedCommand
        root.queuedCommand = null
        actionProc.running = true
        return
      }
      root.refresh()
    }
  }

  Process {
    id: textScaleProc
    stdout: StdioCollector { waitForEnd: true }
  }

  Timer {
    id: reflowSettle
    interval: 300
    repeat: false
    onTriggered: root.reflowingText = false
  }

  Connections {
    target: Style
    function onFontBaseSizeChanged() {
      root.markReflowing()
      if (root.textSizePreviewIndex >= 0
          && root.nearestTextStop(Style.font.baseSize) === root.textSizePreviewIndex)
        root.textSizePreviewIndex = -1
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Quickshell.screens.length > 1 ? "󰍺" : "󰍹"
    onPressed: function(b) { root.toggle() }
    onWheelMoved: function(delta) {
      if (!root.brightnessAvailable) return
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      root.setBrightness(root.brightnessPercent + wheel.steps * 5)
      root.showBrightnessOsd(root.brightnessPercent)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.openPopups > 0
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.moveCursorH(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      // Maj+H/J/K/L dans la section Disposition : déplace l'écran sélectionné.
      onTextKey: function(t) {
        if (root.sectionKind(root.focusSection) !== "layout") return
        if (t === "H") root.nudgeSelected(-1, 0)
        else if (t === "L") root.nudgeSelected(1, 0)
        else if (t === "K") root.nudgeSelected(0, -1)
        else if (t === "J") root.nudgeSelected(0, 1)
      }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          // Pas de défilement pendant qu'on fait glisser un écran.
          value: panelColumn.implicitHeight > scrollArea.height && !diagram.dragging
        }

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          // ---------- Hero ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

            Text {
              id: heroIcon
              textFormat: Text.PlainText
              text: root.hasExternal ? "󰍺" : "󰍹"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "Affichage"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                textFormat: Text.PlainText
                text: {
                  if (root.hasExternal) {
                    var i = root.indexOfValue(root.projectionOptions, root.layoutMode)
                    return (i >= 0 ? root.projectionOptions[i].label : "").toUpperCase()
                  }
                  if (root.brightnessAvailable)
                    return root.brightnessName(brightnessSlider.dragging ? brightnessSlider.liveValue : root.brightnessPercent).toUpperCase()
                  return "LUMINOSITÉ FIXE"
                }
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
                width: parent.width
              }
            }
          }

          // ---------- Conserver ces modifications ? ----------
          Rectangle {
            visible: root.pendingDeadline > 0
            width: parent.width
            implicitHeight: keepColumn.implicitHeight + Style.space(20)
            radius: Style.cornerRadius
            color: Style.selectedFillFor(root.bar.foreground, Color.accent)

            Column {
              id: keepColumn
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(10)
              spacing: Style.space(8)

              Text {
                width: parent.width
                text: "Conserver ces paramètres d'affichage ?"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                wrapMode: Text.WordWrap
              }
              Text {
                width: parent.width
                text: "Retour aux paramètres précédents dans " + root.keepSecondsLeft + " s."
                color: Qt.darker(root.bar.foreground, 1.3)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
              Grid {
                id: keepRow
                width: parent.width
                columns: 2
                spacing: Style.spacing.xs
                readonly property real cellWidth: (width - spacing) / 2

                Repeater {
                  model: [{ label: "Conserver", icon: "󰄬" }, { label: "Rétablir", icon: "󰕌" }]
                  Button {
                    required property var modelData
                    required property int index
                    width: keepRow.cellWidth
                    text: modelData.label
                    iconText: modelData.icon
                    fontSize: Style.font.caption
                    foreground: root.bar.foreground
                    fontFamily: root.bar.fontFamily
                    bordered: true
                    active: index === 0
                    hasCursor: root.cursorActive && root.focusSection === "keep" && root.selectedIndex === index
                    onClicked: index === 0 ? root.keepChanges() : root.revertChanges()
                    onHovered: function(h) { if (h) root.hoverSection("keep", index) }
                  }
                }
              }
            }
          }

          // ---------- Luminosité ----------
          PanelSeparator {
            visible: root.brightnessAvailable
            foreground: root.bar.foreground
          }

          Column {
            visible: root.brightnessAvailable
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: Math.max(brightnessHeader.implicitHeight, brightnessPercentText.implicitHeight)

              PanelSectionHeader {
                id: brightnessHeader
                text: "LUMINOSITÉ"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: brightnessPercentText
                textFormat: Text.PlainText
                text: Math.round(brightnessSlider.dragging ? brightnessSlider.liveValue : root.brightnessPercent) + "%"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            CursorSurface {
              id: brightnessRow
              width: parent.width
              height: brightnessSlider.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.focusSection === "brightness"
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(brightnessRow)
              foreground: root.bar.foreground
              outline: true

              PanelSlider {
                id: brightnessSlider
                bar: root.bar
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                minimum: 1
                maximum: 100
                step: 1
                value: root.brightnessPercent
                integer: true
                onMoved: function(v) { root.previewBrightness(v) }
                onReleased: function(v) {
                  brightnessDebounce.stop()
                  root.setBrightness(v)
                }
              }

              HoverHandler {
                onHoveredChanged: if (hovered) root.hoverSection("brightness", -1)
              }
            }
          }

          // ---------- Taille du texte (globale) ----------
          PanelSeparator {
            foreground: root.bar.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: Math.max(textSizeHeader.implicitHeight, textSizePx.implicitHeight)

              PanelSectionHeader {
                id: textSizeHeader
                text: "TAILLE DU TEXTE · TOUS LES ÉCRANS"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: textSizePx
                textFormat: Text.PlainText
                text: (textSizeSlider.dragging
                       ? root.textSizeStops[Math.round(textSizeSlider.liveValue)]
                       : root.displayedTextPx()) + "px"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            CursorSurface {
              id: textSizeRow
              width: parent.width
              height: textSizeSlider.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.focusSection === "textsize"
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(textSizeRow)
              foreground: root.bar.foreground
              outline: true

              PanelSlider {
                id: textSizeSlider
                bar: root.bar
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                minimum: 0
                maximum: root.textSizeStops.length - 1
                step: 1
                integer: true
                tickCount: root.textSizeStops.length
                value: root.currentTextIndex()
                onReleased: function(v) { root.setTextSize(root.textSizeStops[Math.round(v)]) }
              }

              HoverHandler {
                onHoveredChanged: if (hovered) root.hoverSection("textsize", -1)
              }
            }
          }

          // ---------- Projection (Win+P) ----------
          PanelSeparator {
            visible: root.hasExternal
            foreground: root.bar.foreground
          }

          Column {
            visible: root.hasExternal
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "PROJECTION"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Grid {
              id: projectionGrid
              width: parent.width
              columns: 2
              spacing: Style.spacing.xs
              readonly property real cellWidth: (width - spacing) / 2

              Repeater {
                model: root.projectionOptions
                Button {
                  required property var modelData
                  required property int index
                  width: projectionGrid.cellWidth
                  text: modelData.label
                  iconText: modelData.icon
                  fontSize: Style.font.caption
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  horizontalPadding: Style.spacing.sm
                  verticalPadding: Style.spacing.controlPaddingY
                  bordered: true
                  selected: modelData.value === root.layoutMode
                  hasCursor: root.cursorActive && root.focusSection === "projection" && root.selectedIndex === index
                  onClicked: root.setMode(modelData.value)
                  onHovered: function(h) { if (h) root.hoverSection("projection", index) }
                }
              }
            }
          }

          // ---------- Disposition : glisser-déposer ----------
          PanelSeparator {
            visible: root.showLayout
            foreground: root.bar.foreground
          }

          Column {
            visible: root.showLayout
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "DISPOSITION"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            CursorSurface {
              id: layoutSurface
              width: parent.width
              height: Style.space(170)
              hasCursor: root.cursorActive && root.focusSection === "layout"
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(layoutSurface)
              foreground: root.bar.foreground
              outline: true

              HoverHandler {
                onHoveredChanged: if (hovered && !diagram.dragging) root.hoverSection("layout", root.sectionFirstIndex("layout"))
              }

              // Schéma à l'échelle des écrans. L'écran attrapé suit la souris
              // au pixel près ; un contour montre où il va se poser (collé au
              // bord le plus proche, aligné haut/centre/bas). Lâché par-dessus
              // d'autres écrans, il s'insère et les autres s'écartent : on peut
              // ainsi le mettre au milieu de deux écrans.
              Item {
                id: diagram
                anchors.fill: parent
                anchors.margins: Style.space(6)

                property bool dragging: false
                property string dragName: ""
                // Position brute (sous la souris) de l'écran attrapé.
                property real rawX: 0
                property real rawY: 0
                // Disposition calculée en direct : { écran: {x, y} }.
                property var dragLayout: ({})
                property var frozenView: null

                // Cadre de vue : les écrans + une marge. `extra` agrandit la
                // marge pendant un glisser pour que les écrans écartés restent
                // visibles.
                function computeView(rects, extraW, extraH) {
                  if (!rects.length) return { x: 0, y: 0, f: 1, ox: 0, oy: 0 }
                  var x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9, big = 0
                  for (var i = 0; i < rects.length; i++) {
                    var r = rects[i]
                    x0 = Math.min(x0, r.x); y0 = Math.min(y0, r.y)
                    x1 = Math.max(x1, r.x + r.w); y1 = Math.max(y1, r.y + r.h)
                    big = Math.max(big, r.w, r.h)
                  }
                  var padX = big * 0.22 + (extraW || 0)
                  var padY = big * 0.22 + (extraH || 0)
                  x0 -= padX; y0 -= padY; x1 += padX; y1 += padY
                  var f = Math.min(width / (x1 - x0), height / (y1 - y0))
                  return {
                    x: x0, y: y0, f: f,
                    ox: (width - (x1 - x0) * f) / 2,
                    oy: (height - (y1 - y0) * f) / 2
                  }
                }
                readonly property var liveView: computeView(root.layoutRects, 0, 0)
                readonly property var targetView: dragging && frozenView ? frozenView : liveView

                // Vue animée : le schéma se recadre en douceur au lieu de sauter.
                property real vx: targetView.x
                property real vy: targetView.y
                property real vf: targetView.f
                property real vox: targetView.ox
                property real voy: targetView.oy
                Behavior on vx { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on vy { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on vf { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on vox { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on voy { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                function toPxX(lx) { return vox + (lx - vx) * vf }
                function toPxY(ly) { return voy + (ly - vy) * vf }

                // Position logique affichée d'un écran.
                function shownPos(r) {
                  if (dragging && dragLayout[r.name]) return dragLayout[r.name]
                  if (!dragging && root.placementPreview && root.placementPreview[r.name]) return root.placementPreview[r.name]
                  return r
                }

                // Contour : là où l'écran attrapé va se poser.
                Rectangle {
                  id: ghost
                  visible: diagram.dragging && !!diagram.dragLayout[diagram.dragName]
                  readonly property var rect: {
                    for (var i = 0; i < root.layoutRects.length; i++)
                      if (root.layoutRects[i].name === diagram.dragName) return root.layoutRects[i]
                    return null
                  }
                  readonly property var pos: diagram.dragLayout[diagram.dragName] || { x: 0, y: 0 }
                  x: diagram.toPxX(pos.x)
                  y: diagram.toPxY(pos.y)
                  width: rect ? rect.w * diagram.vf : 0
                  height: rect ? rect.h * diagram.vf : 0
                  z: 1
                  radius: Math.min(Style.cornerRadius, 4)
                  color: "transparent"
                  border.width: 2
                  border.color: Color.accent
                  opacity: 0.9
                  Behavior on x { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                  Behavior on y { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                }

                Repeater {
                  model: root.layoutRects

                  Rectangle {
                    id: screenRect
                    required property var modelData

                    readonly property bool moving: diagram.dragging && diagram.dragName === modelData.name
                    readonly property var pos: diagram.shownPos(modelData)
                    readonly property bool isSelected: root.selectedOutput === modelData.name

                    // L'écran attrapé colle à la souris ; les autres glissent
                    // en douceur vers leur nouvelle place.
                    // (L'écran attrapé utilise la vue cible, pas la vue animée :
                    // il reste exactement sous la souris pendant le dézoom.)
                    x: moving && diagram.frozenView
                       ? diagram.frozenView.ox + (diagram.rawX - diagram.frozenView.x) * diagram.frozenView.f
                       : diagram.toPxX(pos.x)
                    y: moving && diagram.frozenView
                       ? diagram.frozenView.oy + (diagram.rawY - diagram.frozenView.y) * diagram.frozenView.f
                       : diagram.toPxY(pos.y)
                    width: modelData.w * diagram.vf
                    height: modelData.h * diagram.vf
                    Behavior on x { enabled: !screenRect.moving; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    Behavior on y { enabled: !screenRect.moving; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                    z: moving ? 3 : 2
                    radius: Math.min(Style.cornerRadius, 4)
                    color: isSelected ? Style.selectedFillFor(root.bar.foreground, Color.accent)
                                      : Style.hoverFillFor(root.bar.foreground, Color.accent)
                    border.width: isSelected ? 2 : 1
                    border.color: isSelected ? Color.accent : Qt.darker(root.bar.foreground, 1.6)
                    opacity: moving ? 0.75 : 1

                    Column {
                      anchors.centerIn: parent
                      spacing: 0
                      Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: screenRect.modelData.n
                        color: root.bar.foreground
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.title
                        font.bold: true
                      }
                      Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: screenRect.width > Style.space(70)
                        // Pouces : simple étiquette, les proportions restent
                        // celles de la résolution (c'est ce qui compte pour
                        // les jonctions).
                        text: (screenRect.modelData.internal ? "Portable" : screenRect.modelData.name)
                              + (screenRect.modelData.inches ? " · " + screenRect.modelData.inches + "\"" : "")
                        color: Qt.darker(root.bar.foreground, 1.3)
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: diagram.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                      preventStealing: true

                      // Décalage (px logiques) entre le coin de l'écran et la souris.
                      property real grabX: 0
                      property real grabY: 0
                      property point pressPoint
                      property bool armed: false

                      onPressed: function(mouse) {
                        root.selectedOutput = screenRect.modelData.name
                        var p = mapToItem(diagram, mouse.x, mouse.y)
                        pressPoint = p
                        armed = true
                        // Marge élargie de la taille de l'écran attrapé : il y
                        // a toujours la place de le poser et d'écarter les autres.
                        diagram.frozenView = diagram.computeView(root.layoutRects,
                                                                 screenRect.modelData.w * 0.8,
                                                                 screenRect.modelData.h * 0.8)
                        var start = diagram.shownPos(screenRect.modelData)
                        grabX = (p.x - diagram.frozenView.ox) / diagram.frozenView.f + diagram.frozenView.x - start.x
                        grabY = (p.y - diagram.frozenView.oy) / diagram.frozenView.f + diagram.frozenView.y - start.y
                      }
                      onPositionChanged: function(mouse) {
                        if (!pressed || !armed) return
                        var p = mapToItem(diagram, mouse.x, mouse.y)
                        if (!diagram.dragging) {
                          if (Math.abs(p.x - pressPoint.x) + Math.abs(p.y - pressPoint.y) < 4) return
                          diagram.dragName = screenRect.modelData.name
                          diagram.dragging = true
                        }
                        var v = diagram.frozenView
                        var lx = (p.x - v.ox) / v.f + v.x - grabX
                        var ly = (p.y - v.oy) / v.f + v.y - grabY
                        diagram.rawX = lx
                        diagram.rawY = ly
                        // Seuil d'aimantation : ~10 px à l'écran.
                        diagram.dragLayout = Model.layoutAfterDrag(root.layoutRects, screenRect.modelData.name,
                                                                   lx, ly, 10 / v.f, root.minOverlap)
                      }
                      onReleased: {
                        armed = false
                        if (!diagram.dragging) return
                        var layout = diagram.dragLayout
                        // L'écran lâché part de sous la souris et glisse vers
                        // le contour (l'animation reprend dès dragging = false).
                        root.placementPreview = layout
                        diagram.dragging = false
                        var changed = false
                        for (var i = 0; i < root.layoutRects.length; i++) {
                          var r = root.layoutRects[i]
                          var q = layout[r.name]
                          if (q && (Math.round(q.x) !== r.x || Math.round(q.y) !== r.y)) changed = true
                        }
                        if (changed) root.placeLayout(layout)
                        else root.placementPreview = null
                      }
                      onCanceled: { armed = false; diagram.dragging = false }
                    }
                  }
                }
              }
            }

            // Hauteur fixe : le texte change à chaque mouvement, il ne doit
            // pas redimensionner le panneau (source de saccades).
            Text {
              width: parent.width
              height: Style.font.caption * 3.2
              text: {
                var name = diagram.dragging ? diagram.dragName : root.selectedOutput
                var pos = ""
                for (var i = 0; i < root.layoutRects.length; i++) {
                  var r = root.layoutRects[i]
                  if (r.name !== name) continue
                  var p = diagram.dragging ? (diagram.dragLayout[name] || r) : r
                  pos = r.n + " · " + r.name + " : x " + Math.round(p.x) + ", y " + Math.round(p.y)
                    + "  (" + r.w + "×" + r.h + ")"
                }
                return pos + "\nGlisse un écran : il se colle aux autres. Lâché entre deux écrans, ils s'écartent."
              }
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              maximumLineCount: 3
              elide: Text.ElideRight
            }
          }

          // ---------- Une carte de réglages par écran ----------
          Repeater {
            model: root.targets

            OutputCard {
              width: panelColumn.width
            }
          }

          Item {
            width: parent.width
            height: Style.space(4)
          }
        }
      }
    }
  }

  // Réglages indépendants d'un écran : résolution, fréquence, orientation,
  // taille (échelle).
  component OutputCard: Column {
    id: card
    required property var modelData
    required property int index
    readonly property var output: modelData
    readonly property string name: modelData.name

    spacing: Style.space(10)

    HoverHandler {
      onHoveredChanged: if (hovered && !root.layoutDragging) root.selectedOutput = card.name
    }

    PanelSeparator {
      width: parent.width
      foreground: root.bar.foreground
    }

    Item {
      width: parent.width
      implicitHeight: cardTitle.implicitHeight + cardSubtitle.implicitHeight + Style.space(2)

      Rectangle {
        id: cardBadge
        width: Style.space(22)
        height: width
        radius: width / 2
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        color: root.selectedOutput === card.name ? Color.accent : Style.hoverFillFor(root.bar.foreground, Color.accent)
        Text {
          anchors.centerIn: parent
          text: root.outputNumber(card.name)
          color: root.selectedOutput === card.name ? Color.background : root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }

      Text {
        id: cardTitle
        anchors.left: cardBadge.right
        anchors.leftMargin: Style.space(8)
        anchors.right: parent.right
        anchors.top: parent.top
        text: root.outputTitle(card.output).toUpperCase()
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.1
        elide: Text.ElideRight
      }
      Text {
        id: cardSubtitle
        anchors.left: cardTitle.left
        anchors.right: parent.right
        anchors.top: cardTitle.bottom
        anchors.topMargin: Style.space(2)
        text: root.outputSummary(card.output)
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    CardDropdown {
      outputName: card.name
      kind: "resolution"
      label: "Résolution"
      options: root.resolutionOptions(card.output)
      current: root.resolutionValue(card.output)
      onPicked: function(v) { root.setResolution(card.output, v) }
    }

    CardDropdown {
      outputName: card.name
      kind: "refresh"
      label: "Fréquence d'actualisation"
      options: root.refreshOptions(card.output, root.resolutionValue(card.output))
      current: root.refreshValue(card.output)
      onPicked: function(v) { root.confirmSetting(card.output, "mode=" + v) }
    }

    CardDropdown {
      outputName: card.name
      kind: "orientation"
      label: "Orientation"
      options: root.orientationOptions
      current: String(card.output.saved.transform)
      onPicked: function(v) { root.confirmSetting(card.output, "transform=" + v) }
    }

    Item {
      width: parent.width
      implicitHeight: scaleTitle.implicitHeight

      Text {
        id: scaleTitle
        text: "Taille des éléments (échelle)"
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
      Text {
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        text: Math.round(Number(card.output.saved.scale) * 100) + " %"
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }

    Grid {
      id: scaleRow
      width: parent.width
      readonly property var values: root.scaleValues(card.output)
      columns: Math.max(1, values.length)
      spacing: Style.spacing.xs
      readonly property real cellWidth: (width - spacing * (columns - 1)) / columns

      Repeater {
        model: scaleRow.values

        Button {
          required property string modelData
          required property int index
          width: scaleRow.cellWidth
          text: root.effectiveScale(card.output, modelData) + "x"
          fontSize: Style.font.caption
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          horizontalPadding: Style.spacing.sm
          verticalPadding: Style.spacing.controlPaddingY
          bordered: true
          active: root.activeScaleIndex(card.output) === index
          hasCursor: root.cursorActive && root.focusSection === "scale@" + card.name && root.selectedIndex === index
          onClicked: root.setScale(card.output, modelData)
          onHovered: function(h) { if (h) root.hoverSection("scale@" + card.name, index) }
        }
      }
    }

  }

  // Liste déroulante liée au curseur clavier "<kind>@<écran>". Le binding
  // de `value` est rétabli après chaque choix : l'écran fait foi.
  component CardDropdown: Dropdown {
    id: dd
    property string kind: ""
    property string current: ""
    property string outputName: ""
    readonly property string section: kind + "@" + outputName
    signal picked(string value)

    width: parent ? parent.width : implicitWidth
    fontFamily: root.bar.fontFamily
    value: current
    hasCursor: root.cursorActive && root.focusSection === section
    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(dd)
    onHovered: function(h) { if (h) root.hoverSection(section, 0) }
    onChanged: function(v) {
      if (v !== current) dd.picked(v)
      dd.value = Qt.binding(function() { return dd.current })
    }
    onPopupOpenChanged: {
      root.openPopups = Math.max(0, root.openPopups + (popupOpen ? 1 : -1))
      if (!popupOpen) root.refocusKeys()
    }
    // Le panneau peut être détruit avant la liste (rechargement, écran
    // débranché) : `root` vaut alors null.
    Component.onCompleted: if (root) root.dropdownRefs[section] = dd
    Component.onDestruction: if (root && root.dropdownRefs && root.dropdownRefs[section] === dd) delete root.dropdownRefs[section]
  }
}
