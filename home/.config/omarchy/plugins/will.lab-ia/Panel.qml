import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Serveur IA (lab-ia), NAS et PC portable : icône dans la barre + panneau à trois onglets.
// Les mesures viennent de ~/.local/bin/lab-ia-status et ~/.local/bin/nas-status,
// qui passent par SSH et renvoient du JSON, et de ~/.local/bin/pc-status (local).
//
// clic gauche = panneau · clic droit = terminal SSH · clic milieu = rafraîchir
// Dans le panneau : h / l ou ← / → pour changer d'onglet.
Panel {
  id: root
  moduleName: "will.lab-ia"
  ipcTarget: "will.lab-ia"

  readonly property string home: Quickshell.env("HOME")
  property string tab: "ia"
  property var stats: ({ online: false, state: "loading" })
  property var nas: ({ online: false, loading: true })
  property var pc: ({ online: false })
  property bool waking: false
  readonly property var tabs: ["ia", "nas", "pc"]

  readonly property bool online: stats.online === true
  readonly property var gpu: stats.gpu || ({})
  readonly property var models: (stats.ollama && stats.ollama.models) || []
  readonly property var loadedModels: models.filter(function(m) { return m.loaded })
  readonly property var containers: nas.containers || []
  readonly property int runningContainers: containers.filter(function(c) { return c.running }).length
  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property color hot: root.bar ? root.bar.urgent : Color.urgent

  // ---------- Formatage ----------
  function go(bytes) {
    return (Number(bytes || 0) / 1073741824).toFixed(1).replace(".", ",")
  }

  function size(bytes) {
    var b = Number(bytes || 0)
    if (b >= 1099511627776) return (b / 1099511627776).toFixed(1).replace(".", ",") + " To"
    if (b < 1073741824) return Math.round(b / 1048576) + " Mo"
    return go(b) + " Go"
  }

  function rate(bytesPerSec) {
    var b = Number(bytesPerSec || 0)
    if (b >= 1048576) return (b / 1048576).toFixed(1).replace(".", ",") + " Mo/s"
    if (b >= 1024) return Math.round(b / 1024) + " Ko/s"
    return b + " o/s"
  }

  function frac(used, total) {
    return total > 0 ? Math.max(0, Math.min(1, used / total)) : 0
  }

  function duration(seconds) {
    var s = Number(seconds || 0)
    var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60)
    if (d > 0) return d + " j " + h + " h"
    if (h > 0) return h + " h " + m + " min"
    return m + " min"
  }

  function expiresIn(iso) {
    if (!iso) return ""
    var t = Date.parse(String(iso).replace(/\.\d+/, ""))
    if (!isFinite(t)) return ""
    var min = Math.round((t - Date.now()) / 60000)
    return min > 0 ? "libéré dans " + min + " min" : "libération imminente"
  }

  readonly property string iaStatusText: {
    if (root.waking && !root.online) return "Réveil en cours…"
    switch (stats.state) {
    case "linux": return "En ligne · Debian " + (stats.debian || "") + " · " + duration(stats.uptime)
    case "booting": return "Démarrage…"
    case "windows": return "Démarré sur Windows"
    case "off": return "Éteint"
    case "unreachable": return "NAS injoignable"
    default: return "Connexion…"
    }
  }

  readonly property string nasStatusText: {
    if (nas.online) return "En ligne · UGOS · " + duration(nas.uptime)
    return nas.loading ? "Connexion…" : "Injoignable"
  }

  readonly property var battery: pc.battery || ({})
  readonly property string pcStatusText: {
    if (!pc.online) return "Lecture…"
    var bat = battery.ac
      ? (battery.status === "Full" ? "Secteur · batterie pleine" : "En charge · " + battery.percent + " %")
      : "Sur batterie · " + battery.percent + " %"
    return bat + " · " + duration(pc.uptime)
  }

  readonly property bool nasRaidHealthy: (nas.raid || []).every(function(r) { return r.healthy })
  readonly property var externalDisks: nas.external || []
  readonly property var backup: nas.backup || ({})
  readonly property bool backupRunning: backup.running === true
  readonly property bool backupReady: !!backup.target && !backupRunning
  // Le disque vit ailleurs : rappel quand la dernière sauvegarde a plus de 7 jours.
  readonly property bool backupStale: !backupRunning && (!backup.lastSuccess || Date.now() / 1000 - backup.lastSuccess > 7 * 86400)

  // Étapes de la sauvegarde. La phase vaut par ex. "2/3 · Médias" ou
  // "3/3 · Config Docker · 10 conteneurs arrêtés".
  readonly property var backupPhaseParts: String(backup.phase || "").split(" · ")
  readonly property int backupStep: parseInt(backupPhaseParts[0]) || 1
  readonly property var backupSteps: {
    var all = ["Documents et projets", "Médias", "Config Docker"]
    var total = parseInt(String(backupPhaseParts[0]).split("/")[1]) || all.length
    return total === all.length ? all : all.slice(0, total)
  }
  readonly property string backupDetail: backupPhaseParts.length > 2 ? backupPhaseParts.slice(2).join(" · ")
    : (backupPhaseParts[1] || "").indexOf("Arrêt") === 0 || (backupPhaseParts[1] || "").indexOf("Redémarrage") === 0
      ? backupPhaseParts[1] : ""

  readonly property var spinnerFrames: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
  property int spinnerIndex: 0
  readonly property string spinner: spinnerFrames[spinnerIndex % spinnerFrames.length]

  Timer {
    interval: 90
    running: root.backupRunning
    repeat: true
    onTriggered: root.spinnerIndex++
  }

  // Pour les notifications : disques déjà vus et sauvegarde en cours au dernier relevé.
  property var knownDisks: null
  property bool wasBackingUp: false

  function ago(ts) {
    if (!ts) return "jamais"
    var min = Math.round((Date.now() / 1000 - ts) / 60)
    if (min < 1) return "à l'instant"
    if (min < 60) return "il y a " + min + " min"
    if (min < 1440) return "il y a " + Math.round(min / 60) + " h"
    return "il y a " + Math.round(min / 1440) + " j"
  }

  readonly property string backupText: {
    if (backupRunning) return (backup.phase || "Préparation") + " · " + (backup.percent || 0) + " %"
    var last = "Dernière sauvegarde réussie : " + ago(backup.lastSuccess)
    if (!backup.target) return last + " · branche le disque sur le NAS, elle démarrera toute seule"
    if (backup.result && backup.result !== "ok") return "Dernière tentative " + backup.result + " · " + last.toLowerCase()
    return last
  }

  function notify(title, body) {
    Quickshell.execDetached(["notify-send", "-a", "NAS", "-i", "drive-harddisk", title, body])
  }

  function handleNasUpdate(next) {
    if (!next.online) return
    var disks = next.external || []
    var names = disks.map(function(d) { return d.device })
    if (root.knownDisks !== null) {
      disks.forEach(function(d) {
        if (root.knownDisks.indexOf(d.device) < 0)
          notify("Disque externe branché sur le NAS", d.name + " · " + size(d.total)
            + (d.backupTarget ? " · la sauvegarde démarre automatiquement" : ""))
      })
      root.knownDisks.forEach(function(dev) {
        if (names.indexOf(dev) < 0) notify("Disque externe débranché du NAS", dev)
      })
    }
    root.knownDisks = names

    var b = next.backup || {}
    if (root.wasBackingUp && !b.running) {
      if (b.result === "ok") notify("Sauvegarde terminée", "Les dossiers du NAS sont copiés sur le disque externe.")
      else notify("Sauvegarde " + (b.result || "interrompue"), "Détails dans ~/.local/state/nas-backup/last.log sur le NAS.")
    }
    root.wasBackingUp = b.running === true
  }

  // ---------- Actions ----------
  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function refreshNas() {
    if (!nasProc.running) nasProc.running = true
  }

  function refreshPc() {
    if (!pcProc.running) pcProc.running = true
  }

  function selectTab(name) {
    root.tab = name
    if (name === "nas") refreshNas()
    else if (name === "pc") refreshPc()
    else refresh()
  }

  function openTerminal() {
    if (root.tab === "pc") Quickshell.execDetached(["xdg-terminal-exec", "--title=btop", "btop"])
    else if (root.tab === "nas") Quickshell.execDetached(["xdg-terminal-exec", "--title=NAS", "ssh", "nas"])
    else Quickshell.execDetached(["xdg-terminal-exec", "--title=IA", root.home + "/.local/bin/ia"])
    close()
  }

  function wake() {
    root.waking = true
    Quickshell.execDetached(["ssh", "-o", "BatchMode=yes", "nas", "~/bin/wake"])
    wakeTimeout.restart()
  }

  function unloadModels() {
    if (!unloadProc.running) unloadProc.running = true
  }

  function startBackup() {
    if (backupProc.running) return
    backupProc.command = ["ssh", "-o", "BatchMode=yes", "nas", "~/bin/nas-backup start"]
    backupProc.running = true
    root.wasBackingUp = true
  }

  function cancelBackup() {
    if (backupProc.running) return
    backupProc.command = ["ssh", "-o", "BatchMode=yes", "nas", "~/bin/nas-backup cancel"]
    backupProc.running = true
  }

  Process {
    id: statusProc
    command: [root.home + "/.local/bin/lab-ia-status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var next = JSON.parse(String(text || "").trim())
          root.stats = next
          if (next.online) root.waking = false
        } catch (e) {}
      }
    }
  }

  Process {
    id: nasProc
    command: [root.home + "/.local/bin/nas-status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var next = JSON.parse(String(text || "").trim())
          root.nas = next
          root.handleNasUpdate(next)
        } catch (e) {}
      }
    }
  }

  Process {
    id: pcProc
    command: [root.home + "/.local/bin/pc-status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.pc = JSON.parse(String(text || "").trim()) } catch (e) {}
      }
    }
  }

  Process {
    id: backupProc
    onExited: root.refreshNas()
  }

  Process {
    id: unloadProc
    command: ["ssh", "-o", "BatchMode=yes", "ia", "~/.local/bin/lab-ia-unload"]
    onExited: root.refresh()
  }

  // lab-ia : rapide quand l'onglet est visible ou que la tour se réveille, lent sinon
  // (l'icône de la barre en dépend). NAS : rapide quand son onglet est ouvert,
  // toutes les 30 s sinon pour les notifications (disque branché, fin de sauvegarde).
  Timer {
    interval: (root.opened && root.tab === "ia") || root.waking ? 2000 : 15000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: root.opened && root.tab === "nas" ? 3000 : root.backupRunning ? 5000 : 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshNas()
  }

  // PC : mesuré seulement quand son onglet est ouvert.
  Timer {
    interval: 2000
    running: root.opened && root.tab === "pc"
    repeat: true
    onTriggered: root.refreshPc()
  }

  Timer { id: wakeTimeout; interval: 180000; onTriggered: root.waking = false }

  onOpenedChanged: if (opened) selectTab(root.tab)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ---------- Barre ----------
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Pendant une sauvegarde, la barre montre sa progression à la place de l'état du serveur IA.
    readonly property string label: vertical ? ""
      : root.backupRunning ? root.spinner + " " + root.backupStep + "/" + root.backupSteps.length + " " + (root.backup.percent || 0) + "%"
      : root.online && root.gpu.busy >= 10 ? root.gpu.busy + "%" : ""
    text: label ? "󰒋 " + label : "󰒋"
    slotSize: Style.bar.iconSlot * (label ? 1 + label.length * 0.3 : 1)
    dimmed: !root.online && !root.backupRunning
    active: root.loadedModels.length > 0 || root.backupRunning
    tooltipText: root.opened ? ""
      : root.backupRunning ? "Sauvegarde du NAS · " + (root.backupSteps[root.backupStep - 1] || "") + " · " + (root.backup.percent || 0) + " %"
      : "lab-ia · " + root.iaStatusText
    onPressed: function(b) {
      if (b === Qt.RightButton) {
        root.tab = "ia"
        root.openTerminal()
      } else if (b === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }

  // ---------- Panneau ----------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) {
          var i = Math.max(0, Math.min(root.tabs.length - 1, root.tabs.indexOf(root.tab) + (dx > 0 ? 1 : -1)))
          root.selectTab(root.tabs[i])
        }
        if (dy !== 0)
          panelFlick.contentY = Math.max(0, Math.min(panelFlick.contentY + dy * Style.space(56),
                                                     panelFlick.contentHeight - panelFlick.height))
      }
      onActivateRequested: root.tab === "ia" && !root.online ? root.wake() : root.openTerminal()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      // Défile quand le contenu dépasse la hauteur de l'écran (molette ou j / k).
      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: column
        width: panelFlick.width
        spacing: Style.space(14)

        // ---------- Onglets ----------
        ButtonGroup {
          options: [
            { value: "ia", label: "lab-ia", icon: "󰒋" },
            { value: "nas", label: "NAS", icon: "󰋊" },
            { value: "pc", label: "PC", icon: "󰌢" }
          ]
          value: root.tab
          focusable: false
          foreground: root.fg
          fontFamily: root.bar.fontFamily
          fontSize: Style.font.bodySmall
          onChanged: function(v) { root.selectTab(v) }
        }

        // ---------- Hero ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroValue.implicitHeight)

          readonly property bool up: root.tab === "ia" ? root.online : root.tab === "pc" ? root.pc.online === true : root.nas.online === true

          Text {
            id: heroIcon
            text: root.tab === "ia" ? "󰒋" : root.tab === "pc" ? "󰌢" : "󰋊"
            color: root.fg
            opacity: parent.up ? 1 : 0.45
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroValue.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: root.tab === "ia" ? "lab-ia" : root.tab === "pc" ? (root.pc.model || "PC") : (root.nas.hostname || "NAS")
              color: root.fg
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              text: (root.tab === "ia" ? root.iaStatusText : root.tab === "pc" ? root.pcStatusText : root.nasStatusText).toUpperCase()
              color: Qt.darker(root.fg, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Column {
            id: heroValue
            visible: parent.up
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            Text {
              anchors.right: parent.right
              text: root.tab === "ia"
                ? (root.gpu.busy || 0) + "%"
                : root.tab === "pc" ? ((root.pc.cpu ? root.pc.cpu.percent : 0) + "%")
                : ((root.nas.cpu ? root.nas.cpu.percent : 0) + "%")
              color: root.fg
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.displayLarge
              font.bold: true
            }
            Text {
              anchors.right: parent.right
              text: root.tab === "ia" ? "GPU" : "CPU"
              color: root.fg
              opacity: 0.5
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }
          }
        }

        // =====================================================================
        // Onglet lab-ia
        // =====================================================================
        Column {
          visible: root.tab === "ia"
          width: parent.width
          spacing: Style.space(14)

          Text {
            visible: !root.online
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: stats.state === "windows"
              ? "La tour tourne sous Windows. Redémarre-la sur Debian pour utiliser Ollama."
              : stats.state === "unreachable"
                ? "Impossible de joindre le NAS. Vérifie Tailscale."
                : "Le serveur ne répond pas. Réveille-le via le NAS (Wake-on-LAN)."
            color: root.fg
            opacity: 0.7
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          // ---------- GPU ----------
          PanelSeparator { visible: root.online; foreground: root.fg }

          Column {
            visible: root.online
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader { text: "RADEON RX 7800 XT"; foreground: root.fg; fontFamily: root.bar.fontFamily }

            Meter { label: "Charge"; value: (root.gpu.busy || 0) + " %"; fraction: (root.gpu.busy || 0) / 100 }
            Meter {
              label: "VRAM"
              value: root.go(root.gpu.vramUsed) + " / " + root.go(root.gpu.vramTotal) + " Go"
              fraction: root.frac(root.gpu.vramUsed, root.gpu.vramTotal)
            }
            Meter {
              label: "Puissance"
              value: (root.gpu.watts || 0) + " / " + (root.gpu.wattsCap || 0) + " W"
              fraction: root.frac(root.gpu.watts, root.gpu.wattsCap)
            }

            Row {
              width: parent.width
              spacing: Style.space(20)
              Column {
                width: (parent.width - parent.spacing) / 2
                spacing: Style.spacing.labelGap
                InfoPair { label: "Temp. bord"; value: (root.gpu.edge || 0) + " °C"; warn: root.gpu.edge >= 85 }
                InfoPair { label: "Temp. jonction"; value: (root.gpu.junction || 0) + " °C"; warn: root.gpu.junction >= 95 }
              }
              Column {
                width: (parent.width - parent.spacing) / 2
                spacing: Style.spacing.labelGap
                InfoPair { label: "Temp. mémoire"; value: (root.gpu.mem || 0) + " °C"; warn: root.gpu.mem >= 95 }
                InfoPair { label: "Ventilateur"; value: (root.gpu.fan || 0) + " tr/min" }
              }
            }
          }

          // ---------- Système ----------
          PanelSeparator { visible: root.online; foreground: root.fg }

          Column {
            visible: root.online
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader { text: "RYZEN 7 5800X"; foreground: root.fg; fontFamily: root.bar.fontFamily }

            Meter {
              label: "CPU"
              value: (stats.cpu ? stats.cpu.percent : 0) + " % · " + (stats.cpu ? stats.cpu.temp : 0) + " °C"
              fraction: (stats.cpu ? stats.cpu.percent : 0) / 100
            }
            Meter {
              label: "RAM"
              value: root.go(stats.ram && stats.ram.used) + " / " + root.go(stats.ram && stats.ram.total) + " Go"
              fraction: stats.ram ? root.frac(stats.ram.used, stats.ram.total) : 0
            }
            Meter {
              label: "Disque"
              value: root.go(stats.disk && stats.disk.used) + " / " + root.go(stats.disk && stats.disk.total) + " Go"
              fraction: stats.disk ? root.frac(stats.disk.used, stats.disk.total) : 0
            }
          }

          // ---------- Ollama ----------
          PanelSeparator { visible: root.online; foreground: root.fg }

          Column {
            visible: root.online
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "OLLAMA " + (stats.ollama ? stats.ollama.version : "") + " · "
                + (stats.ollama && stats.ollama.active ? "ACTIF" : "ARRÊTÉ")
              foreground: root.fg
              fontFamily: root.bar.fontFamily
            }

            Repeater {
              model: root.models

              Column {
                required property var modelData
                width: parent.width
                spacing: Style.space(1)

                Row {
                  width: parent.width
                  spacing: Style.space(8)

                  Text {
                    id: dot
                    text: modelData.loaded ? "●" : "·"
                    color: modelData.loaded ? root.hot : root.fg
                    opacity: modelData.loaded ? 1 : 0.4
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                  Text {
                    id: modelName
                    textFormat: Text.PlainText
                    text: modelData.name
                    color: root.fg
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: modelData.loaded
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, parent.width - dot.width - modelSize.width - parent.spacing * 3)
                  }
                  Item { width: Math.max(0, parent.width - dot.width - modelName.width - modelSize.width - parent.spacing * 3); height: 1 }
                  Text {
                    id: modelSize
                    textFormat: Text.PlainText
                    text: modelData.params + " · " + root.go(modelData.size) + " Go"
                    color: root.fg
                    opacity: 0.55
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }

                Text {
                  visible: modelData.loaded
                  leftPadding: dot.width + Style.space(8)
                  textFormat: Text.PlainText
                  text: "en mémoire · " + root.go(modelData.vram) + " Go VRAM · " + root.expiresIn(modelData.expires)
                  color: root.hot
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }

        // =====================================================================
        // Onglet PC (ce portable)
        // =====================================================================
        Column {
          visible: root.tab === "pc"
          width: parent.width
          spacing: Style.space(14)

          // ---------- Processeur ----------
          PanelSeparator { visible: root.pc.online === true; foreground: root.fg }

          Column {
            visible: root.pc.online === true
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader { text: "CORE ULTRA 7 155H · 16 CŒURS / 22 THREADS"; foreground: root.fg; fontFamily: root.bar.fontFamily }

            Meter {
              label: "CPU"
              value: (root.pc.cpu ? root.pc.cpu.percent : 0) + " % · " + (root.pc.cpu ? root.pc.cpu.temp : 0) + " °C"
              fraction: (root.pc.cpu ? root.pc.cpu.percent : 0) / 100
            }
            Meter {
              label: "RAM · LPDDR5X"
              value: root.go(root.pc.ram && root.pc.ram.used) + " / " + root.go(root.pc.ram && root.pc.ram.total) + " Go"
              fraction: root.pc.ram ? root.frac(root.pc.ram.used, root.pc.ram.total) : 0
            }

            Row {
              width: parent.width
              spacing: Style.space(20)
              Column {
                width: (parent.width - parent.spacing) / 2
                spacing: Style.spacing.labelGap
                InfoPair { label: "Fréquence"; value: ((root.pc.cpu ? root.pc.cpu.freq : 0) / 1000).toFixed(1).replace(".", ",") + " / 4,8 GHz" }
                InfoPair { label: "Temp."; value: (root.pc.cpu ? root.pc.cpu.temp : 0) + " °C"; warn: !!root.pc.cpu && root.pc.cpu.temp >= 95 }
              }
              Column {
                width: (parent.width - parent.spacing) / 2
                spacing: Style.spacing.labelGap
                InfoPair { label: "Profil"; value: root.pc.profile || "—" }
                InfoPair { label: "NPU"; value: "Intel AI Boost" }
              }
            }
          }

          // ---------- GPU ----------
          PanelSeparator { visible: root.pc.online === true; foreground: root.fg }

          Column {
            visible: root.pc.online === true
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader { text: "INTEL ARC (8 CŒURS XE)"; foreground: root.fg; fontFamily: root.bar.fontFamily }

            Meter {
              label: "Charge"
              value: (root.pc.gpu ? root.pc.gpu.busy : 0) + " %"
              fraction: (root.pc.gpu ? root.pc.gpu.busy : 0) / 100
            }
            Meter {
              label: "Fréquence"
              value: (root.pc.gpu ? root.pc.gpu.freq : 0) + " / " + (root.pc.gpu ? root.pc.gpu.freqMax : 0) + " MHz"
              fraction: root.pc.gpu ? root.frac(root.pc.gpu.freq, root.pc.gpu.freqMax) : 0
            }
          }

          // ---------- Stockage ----------
          PanelSeparator { visible: root.pc.online === true; foreground: root.fg }

          Column {
            visible: root.pc.online === true
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader { text: "SSD SAMSUNG PM9C1A · 1 TO NVME"; foreground: root.fg; fontFamily: root.bar.fontFamily }

            Meter {
              label: "Système (/)"
              value: root.size(root.pc.disk && root.pc.disk.used) + " / " + root.size(root.pc.disk && root.pc.disk.total)
              fraction: root.pc.disk ? root.frac(root.pc.disk.used, root.pc.disk.total) : 0
            }
            InfoPair { label: "Temp. SSD"; value: (root.pc.disk ? root.pc.disk.temp : 0) + " °C"; warn: !!root.pc.disk && root.pc.disk.temp >= 70 }
          }

          // ---------- Batterie ----------
          PanelSeparator { visible: root.pc.online === true; foreground: root.fg }

          Column {
            visible: root.pc.online === true
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "BATTERIE · " + (root.battery.ac ? (root.battery.status === "Full" ? "PLEINE" : "EN CHARGE") : "DÉCHARGE")
              foreground: root.battery.ac || root.battery.percent > 20 ? root.fg : root.hot
              fontFamily: root.bar.fontFamily
            }

            Meter {
              label: "Charge"
              value: (root.battery.percent || 0) + " %" + (root.battery.watts > 0 ? " · " + String(root.battery.watts).replace(".", ",") + " W" : "")
              fraction: (root.battery.percent || 0) / 100
              lowIsBad: true
            }

            Row {
              width: parent.width
              spacing: Style.space(20)
              Column {
                width: (parent.width - parent.spacing) / 2
                spacing: Style.spacing.labelGap
                InfoPair { label: "Santé"; value: (root.battery.health || 0) + " %"; warn: root.battery.health < 80 }
              }
              Column {
                width: (parent.width - parent.spacing) / 2
                spacing: Style.spacing.labelGap
                InfoPair { label: "Cycles"; value: String(root.battery.cycles || 0) }
              }
            }
          }

          // ---------- Réseau + écrans ----------
          PanelSeparator { visible: root.pc.online === true; foreground: root.fg }

          Column {
            visible: root.pc.online === true
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "RÉSEAU · " + (root.pc.net && root.pc.net.ssid ? "WI-FI " + root.pc.net.ssid.toUpperCase() : (root.pc.net && root.pc.net.iface ? root.pc.net.iface.toUpperCase() : "HORS LIGNE"))
              foreground: root.fg
              fontFamily: root.bar.fontFamily
            }

            Row {
              width: parent.width
              spacing: Style.space(20)
              Column {
                width: (parent.width - parent.spacing) / 2
                spacing: Style.spacing.labelGap
                InfoPair { label: "Réception"; value: root.rate(root.pc.net && root.pc.net.rx) }
                InfoPair { label: "Envoi"; value: root.rate(root.pc.net && root.pc.net.tx) }
              }
              Column {
                width: (parent.width - parent.spacing) / 2
                spacing: Style.spacing.labelGap
                InfoPair { label: "IP"; value: (root.pc.net && root.pc.net.ip) || "—" }
                InfoPair { label: "Signal"; value: root.pc.net && root.pc.net.signal ? root.pc.net.signal + " dBm" : "—" }
              }
            }

            PanelSectionHeader {
              text: "ÉCRANS · " + (root.pc.displays || []).length
              foreground: root.fg
              fontFamily: root.bar.fontFamily
            }

            Repeater {
              model: root.pc.displays || []
              InfoPair {
                required property var modelData
                label: modelData.name === "eDP-1" ? "Écran intégré 14\"" : (modelData.model || modelData.name)
                value: modelData.width + "×" + modelData.height + " · " + modelData.refresh + " Hz"
              }
            }
          }
        }

        // =====================================================================
        // Onglet NAS
        // =====================================================================
        Column {
          visible: root.tab === "nas"
          width: parent.width
          spacing: Style.space(14)

          Text {
            visible: !root.nas.online && !root.nas.loading
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: "Impossible de joindre le NAS. Vérifie que Tailscale est connecté."
            color: root.fg
            opacity: 0.7
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          // ---------- Système ----------
          PanelSeparator { visible: root.nas.online === true; foreground: root.fg }

          Column {
            visible: root.nas.online === true
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader { text: "PENTIUM GOLD 8505"; foreground: root.fg; fontFamily: root.bar.fontFamily }

            Meter {
              label: "CPU"
              value: (root.nas.cpu ? root.nas.cpu.percent : 0) + " % · " + (root.nas.cpu ? root.nas.cpu.temp : 0) + " °C"
              fraction: (root.nas.cpu ? root.nas.cpu.percent : 0) / 100
            }
            Meter {
              label: "RAM"
              value: root.go(root.nas.ram && root.nas.ram.used) + " / " + root.go(root.nas.ram && root.nas.ram.total) + " Go"
              fraction: root.nas.ram ? root.frac(root.nas.ram.used, root.nas.ram.total) : 0
            }

            Row {
              width: parent.width
              spacing: Style.space(20)
              Column {
                width: (parent.width - parent.spacing) / 2
                spacing: Style.spacing.labelGap
                InfoPair { label: "Réception"; value: root.rate(root.nas.net && root.nas.net.rx) }
                InfoPair { label: "Envoi"; value: root.rate(root.nas.net && root.nas.net.tx) }
              }
              Column {
                width: (parent.width - parent.spacing) / 2
                spacing: Style.spacing.labelGap
                InfoPair { label: "Lien"; value: ((root.nas.net ? root.nas.net.speed : 0) / 1000).toString().replace(".", ",") + " Gb/s" }
                InfoPair { label: "Temp. SSD"; value: (root.nas.nvmeTemp || 0) + " °C"; warn: root.nas.nvmeTemp >= 70 }
              }
            }
          }

          // ---------- Stockage ----------
          PanelSeparator { visible: root.nas.online === true; foreground: root.fg }

          Column {
            visible: root.nas.online === true
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "STOCKAGE · " + (root.nas.rebuilding ? "RECONSTRUCTION EN COURS"
                : root.nasRaidHealthy ? "RAID SAIN" : "RAID DÉGRADÉ")
              foreground: root.nasRaidHealthy && !root.nas.rebuilding ? root.fg : root.hot
              fontFamily: root.bar.fontFamily
            }

            Repeater {
              model: root.nas.volumes || []
              Meter {
                required property var modelData
                label: modelData.label
                value: root.size(modelData.used) + " / " + root.size(modelData.total)
                fraction: root.frac(modelData.used, modelData.total)
              }
            }
          }

          // ---------- Disques externes + sauvegarde ----------
          PanelSeparator { visible: root.nas.online === true; foreground: root.fg }

          Column {
            visible: root.nas.online === true
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "DISQUES EXTERNES · " + (root.externalDisks.length > 0 ? root.externalDisks.length + " BRANCHÉ" + (root.externalDisks.length > 1 ? "S" : "") : "AUCUN")
              foreground: root.fg
              fontFamily: root.bar.fontFamily
            }

            Repeater {
              model: root.externalDisks
              Meter {
                required property var modelData
                label: "󰕓 " + modelData.name + (modelData.backupTarget ? " · sauvegarde" : "")
                value: root.size(modelData.used) + " / " + root.size(modelData.total)
                fraction: root.frac(modelData.used, modelData.total)
              }
            }

            // Progression de la sauvegarde en cours : étapes + barre animée
            Column {
              visible: root.backupRunning
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: root.backupSteps

                Row {
                  required property var modelData
                  required property int index
                  readonly property bool done: index < root.backupStep - 1
                  readonly property bool current: index === root.backupStep - 1
                  spacing: Style.space(8)

                  Text {
                    width: Style.space(14)
                    text: parent.done ? "✓" : parent.current ? root.spinner : "·"
                    color: parent.done || parent.current ? root.hot : root.fg
                    opacity: parent.done || parent.current ? 1 : 0.4
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: modelData + (parent.current && root.backupDetail ? "  ·  " + root.backupDetail : "")
                    color: root.fg
                    opacity: parent.current ? 1 : parent.done ? 0.7 : 0.4
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: parent.current
                  }
                }
              }

              Item { width: 1; height: Style.space(4) }

              Meter {
                label: "Étape " + root.backupStep + " / " + root.backupSteps.length
                value: (root.backup.percent || 0) + " %" + (root.backup.speed ? " · " + root.backup.speed : "")
                  + (root.backup.eta && root.backup.eta !== "0:00:00" ? " · reste " + root.backup.eta : "")
                fraction: (root.backup.percent || 0) / 100
                animated: true
              }
            }

            Text {
              visible: !root.backupRunning
              width: parent.width
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: "󰁯 " + root.backupText
              readonly property bool warn: root.backupStale || (root.backup.result && root.backup.result !== "ok")
              color: warn ? root.hot : root.fg
              opacity: warn ? 1 : 0.6
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          // ---------- Docker ----------
          PanelSeparator { visible: root.containers.length > 0; foreground: root.fg }

          Column {
            visible: root.containers.length > 0
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "DOCKER · " + root.runningContainers + " / " + root.containers.length + " EN MARCHE"
              foreground: root.runningContainers === root.containers.length ? root.fg : root.hot
              fontFamily: root.bar.fontFamily
            }

            Flow {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.containers

                Rectangle {
                  required property var modelData
                  radius: height / 2
                  color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, modelData.running ? 0.08 : 0)
                  border.width: 1
                  border.color: modelData.running ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18) : root.hot
                  implicitWidth: chip.implicitWidth + Style.space(16)
                  implicitHeight: chip.implicitHeight + Style.space(6)

                  Text {
                    id: chip
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: (modelData.running ? "● " : "○ ") + modelData.name
                    color: modelData.running ? root.fg : root.hot
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }
        }

        // ---------- Actions ----------
        PanelSeparator { foreground: root.fg }

        Row {
          id: actions
          width: parent.width
          spacing: Style.space(6)

          readonly property bool showWake: root.tab === "ia" && !root.online
          readonly property bool showUnload: root.tab === "ia" && root.online && root.loadedModels.length > 0
          readonly property bool showBackup: root.tab === "nas" && root.nas.online === true
            && (root.backupReady || root.backupRunning)
          readonly property real half: (width - spacing) / 2

          Button {
            visible: actions.showBackup
            width: actions.half
            iconText: root.backupRunning ? "󰜺" : "󰁯"
            text: root.backupRunning ? "Annuler la sauvegarde" : "Sauvegarder"
            fontSize: Style.font.bodySmall
            foreground: root.fg
            fontFamily: root.bar.fontFamily
            bordered: true
            active: root.backupRunning
            onClicked: root.backupRunning ? root.cancelBackup() : root.startBackup()
          }

          Button {
            visible: actions.showWake
            width: actions.half
            iconText: "󰐥"
            text: root.waking ? "Réveil…" : "Réveiller"
            fontSize: Style.font.bodySmall
            foreground: root.fg
            fontFamily: root.bar.fontFamily
            bordered: true
            active: root.waking
            onClicked: if (!root.waking) root.wake()
          }

          Button {
            visible: actions.showUnload
            width: actions.half
            iconText: "󰘚"
            text: unloadProc.running ? "Déchargement…" : "Vider la VRAM (" + root.loadedModels.length + ")"
            fontSize: Style.font.bodySmall
            foreground: root.fg
            fontFamily: root.bar.fontFamily
            bordered: true
            active: unloadProc.running
            onClicked: root.unloadModels()
          }

          Button {
            width: actions.showWake || actions.showUnload || actions.showBackup ? actions.half : actions.width
            iconText: ""
            text: root.tab === "pc" ? "Moniteur système (btop)" : root.tab === "ia" && !root.online ? "Réveiller + terminal" : "Ouvrir un terminal"
            fontSize: Style.font.bodySmall
            foreground: root.fg
            fontFamily: root.bar.fontFamily
            bordered: true
            onClicked: root.openTerminal()
          }
        }
      }
      }
    }
  }

  // ---------- Composants ----------
  component Meter: Column {
    property string label: ""
    property string value: ""
    property real fraction: 0
    property bool animated: false   // reflet qui défile sur la partie remplie
    property bool lowIsBad: false   // batterie : l'alerte est quand c'est presque vide

    width: parent.width
    spacing: Style.space(4)

    Row {
      width: parent.width
      Text {
        id: meterLabel
        textFormat: Text.PlainText
        text: label
        color: root.fg
        opacity: 0.6
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Item { width: Math.max(0, parent.width - meterLabel.implicitWidth - meterValue.implicitWidth); height: 1 }
      Text {
        id: meterValue
        textFormat: Text.PlainText
        text: value
        color: root.fg
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    Item {
      width: parent.width
      implicitHeight: Style.space(6)

      Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
      }
      Rectangle {
        anchors.left: track.left
        height: track.height
        radius: track.radius
        width: fraction > 0 ? Math.max(track.height, track.width * fraction) : 0
        color: animated ? root.hot : (lowIsBad ? fraction <= 0.15 : fraction >= 0.85) ? root.hot : root.fg
        clip: true

        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 220 } }

        Rectangle {
          id: shine
          visible: animated && parent.width > 0
          width: Style.space(60)
          height: parent.height
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.55) }
            GradientStop { position: 1.0; color: "transparent" }
          }

          NumberAnimation on x {
            running: shine.visible
            loops: Animation.Infinite
            from: -shine.width
            to: track.width
            duration: 1400
          }
        }
      }

      // Pulsation de la piste tant que la sauvegarde tourne
      SequentialAnimation on opacity {
        running: animated
        loops: Animation.Infinite
        NumberAnimation { from: 1.0; to: 0.75; duration: 900; easing.type: Easing.InOutSine }
        NumberAnimation { from: 0.75; to: 1.0; duration: 900; easing.type: Easing.InOutSine }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""
    property bool warn: false

    width: parent.width
    spacing: Style.space(8)

    Text {
      id: pairLabel
      textFormat: Text.PlainText
      text: label
      color: root.fg
      opacity: 0.6
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Item { width: Math.max(0, parent.width - pairLabel.implicitWidth - pairValue.implicitWidth - parent.spacing * 2); height: 1 }
    Text {
      id: pairValue
      textFormat: Text.PlainText
      text: value
      color: warn ? root.hot : root.fg
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
