import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Dates.js" as Dates

// Liste de tâches : icône dans la barre (avec le nombre de tâches restantes)
// et panneau pour ajouter, modifier, cocher et supprimer des tâches.
// Les tâches sont stockées dans ~/.local/share/todo/todos.json.
//
// Date limite : un mot en @ dans le texte (@demain, @ven, @+3, @25/10…),
// voir Dates.js. L'icône de la barre passe en rouge s'il y a une tâche
// pour aujourd'hui ou en retard.
//
// clic gauche = panneau · clic droit = afficher/masquer le compteur
// Dans le panneau : on tape directement pour ajouter (Entrée), ↓ pour aller
// dans la liste ; j/k pour se déplacer, Espace/Entrée pour cocher,
// e pour modifier, x pour supprimer, i pour revenir au champ de saisie,
// Échap pour fermer. Double-clic sur une tâche pour la modifier.
//
// Depuis un terminal : omarchy-shell will.todo add "Acheter du pain @demain"
Panel {
  id: root
  moduleName: "will.todo"
  ipcTarget: "will.todo"
  manageIpc: false

  readonly property string dataPath: Quickshell.env("HOME") + "/.local/share/todo/todos.json"
  property var todos: []
  property int cursor: -1
  property int editing: -1
  property var now: new Date()
  property string lastWritten: ""
  readonly property int pending: todos.filter(function(t) { return !t.done }).length
  readonly property int doneCount: todos.length - pending
  readonly property int urgentCount: {
    var n = root.now
    return todos.filter(function(t) {
      var level = Dates.dueInfo(t.due, n).level
      return !t.done && (level === "overdue" || level === "today")
    }).length
  }
  readonly property bool showCount: setting("showCount", true) === true
  readonly property bool countVisible: showCount && pending > 0 && !button.vertical
  readonly property real openPanelIndicatorWidth: countVisible ? button.glyphPaintedWidth : 0
  readonly property real rowHeight: Style.space(30)
  readonly property int maxVisibleRows: 10
  readonly property var inputPreview: Dates.parseInput(input.text, root.now)

  // Glyphes Nerd Font
  readonly property string todoIcon: "󰝖"
  readonly property string iconChecked: "󰄲"
  readonly property string iconUnchecked: "󰄱"
  readonly property string iconDelete: "󰅖"
  readonly property string iconEdit: "󰏫"
  readonly property string iconClear: "󰃢"
  readonly property string iconCalendar: "󰃭"

  function load(raw) {
    // Notre propre écriture revient par le watcher : on l'ignore pour ne pas
    // recréer les lignes (et perdre une édition en cours).
    if (raw === lastWritten) return
    try {
      var parsed = JSON.parse(raw)
      todos = Array.isArray(parsed) ? parsed.filter(function(t) { return t && typeof t.text === "string" }) : []
    } catch (e) {
      todos = []
    }
    editing = -1
    if (cursor >= todos.length) cursor = todos.length - 1
  }

  function save(next) {
    todos = next
    if (cursor >= todos.length) cursor = todos.length - 1
    lastWritten = JSON.stringify(todos, null, 2) + "\n"
    dataFile.setText(lastWritten)
  }

  function add(raw) {
    var parsed = Dates.parseInput(raw, new Date())
    if (parsed.text === "") return
    var todo = { text: parsed.text, done: false, created: new Date().toISOString() }
    if (parsed.due !== "") todo.due = parsed.due
    save(todos.concat([todo]))
  }

  function toggleDone(index) {
    if (index < 0 || index >= todos.length) return
    var next = todos.slice()
    next[index] = Object.assign({}, next[index], { done: !next[index].done })
    save(next)
  }

  function remove(index) {
    if (index < 0 || index >= todos.length) return
    var next = todos.slice()
    next.splice(index, 1)
    save(next)
  }

  function clearDone() {
    save(todos.filter(function(t) { return !t.done }))
  }

  function startEdit(index) {
    if (index < 0 || index >= todos.length) return
    cursor = index
    editing = index
  }

  function commitEdit(index, raw) {
    if (editing !== index) return
    editing = -1
    var parsed = Dates.parseInput(raw, new Date())
    if (parsed.text !== "" && index < todos.length) {
      var next = todos.slice()
      var todo = Object.assign({}, next[index], { text: parsed.text })
      if (parsed.due !== "") todo.due = parsed.due
      else delete todo.due
      next[index] = todo
      save(next)
    }
    keyCatcher.forceActiveFocus()
  }

  function cancelEdit() {
    editing = -1
    keyCatcher.forceActiveFocus()
  }

  function toggleCount() {
    root.settings = Object.assign({}, root.settings, { showCount: !root.showCount })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  function focusInput() {
    cursor = -1
    input.forceActiveFocus()
  }

  function focusList() {
    if (todos.length === 0) return
    if (cursor < 0) cursor = 0
    keyCatcher.forceActiveFocus()
  }

  function moveCursor(delta) {
    if (todos.length === 0) return
    var next = cursor + delta
    if (next < 0) { focusInput(); return }
    cursor = Math.min(next, todos.length - 1)
    list.positionViewAtIndex(cursor, ListView.Contain)
  }

  function dueColor(level) {
    return level === "overdue" || level === "today" ? Color.urgent : root.bar.foreground
  }

  IpcHandler {
    target: "will.todo"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function add(text: string): void { root.add(text) }
    function list(): string {
      var n = new Date()
      return root.todos.map(function(t) {
        var due = Dates.dueInfo(t.due, n).label
        return (t.done ? "[x] " : "[ ] ") + t.text + (due ? "  (" + due + ")" : "")
      }).join("\n")
    }
  }

  onOpenedChanged: {
    now = new Date()
    if (opened) {
      cursor = -1
      editing = -1
      input.text = ""
    } else {
      editing = -1
    }
  }

  // Garde « aujourd'hui / demain / en retard » à jour, même après minuit.
  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: root.now = new Date()
  }

  FileView {
    id: dataFile
    path: root.dataPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.load(text())
    onLoadFailed: root.load("[]")
    onFileChanged: reload()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.countVisible ? root.pending + " " + root.todoIcon : root.todoIcon
    slotSize: Style.bar.iconSlot * (root.countVisible ? 2 : 1)
    active: root.urgentCount > 0
    tooltipText: ""
    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleCount()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: input
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: input.activeFocus || root.editing >= 0
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveCursor(dy) }
      onActivateRequested: root.toggleDone(root.cursor)
      onDeleteRequested: root.remove(root.cursor)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "i" || t === "a" || t === "o") root.focusInput()
        else if (t === "e") root.startEdit(root.cursor)
        else if (t === "c") root.clearDone()
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // ---------- En-tête ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.todoIcon
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
              text: "To-do"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              text: (root.todos.length === 0 ? "Rien à faire"
                : root.pending === 0 ? "Tout est fait 🎉"
                : root.pending + (root.pending > 1 ? " tâches restantes" : " tâche restante")
                  + (root.urgentCount > 0 ? " · " + root.urgentCount + " urgente" + (root.urgentCount > 1 ? "s" : "") : "")).toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }
          }
        }

        // ---------- Saisie ----------
        Column {
          width: parent.width
          spacing: Style.space(4)

          TextField {
            id: input
            width: parent.width
            placeholderText: "Nouvelle tâche…  (@demain, @ven, @25/10)"
            foreground: root.bar.foreground
            font.family: root.bar.fontFamily
            onAccepted: {
              root.add(text)
              text = ""
            }
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                root.close(); event.accepted = true
              } else if (event.key === Qt.Key_Down) {
                root.focusList(); event.accepted = true
              } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                root.switchPanel(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1)
                event.accepted = true
              }
            }
          }

          // Aperçu de la date reconnue pendant la saisie.
          Text {
            visible: root.inputPreview.due !== ""
            leftPadding: Style.space(4)
            textFormat: Text.PlainText
            text: root.iconCalendar + "  pour " + Dates.dueInfo(root.inputPreview.due, root.now).label
            color: Color.accent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        // ---------- Liste ----------
        ListView {
          id: list
          visible: root.todos.length > 0
          width: parent.width
          height: Math.min(root.todos.length, root.maxVisibleRows) * root.rowHeight
          clip: true
          interactive: contentHeight > height
          boundsBehavior: Flickable.StopAtBounds
          model: root.todos

          delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property bool isEditing: root.editing === index
            readonly property bool hot: !isEditing && (rowMouse.containsMouse || (root.cursor === index && !input.activeFocus))
            readonly property var due: Dates.dueInfo(modelData.due, root.now)

            width: list.width
            height: root.rowHeight

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, row.hot ? 0.10 : 0)
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              enabled: !row.isEditing
              onClicked: root.cursor = row.index
              onDoubleClicked: root.startEdit(row.index)
            }

            Text {
              id: check
              textFormat: Text.PlainText
              text: row.modelData.done ? root.iconChecked : root.iconUnchecked
              color: row.modelData.done ? Color.accent : root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.iconLarge
              anchors.left: parent.left
              anchors.leftMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter

              MouseArea {
                anchors.fill: parent
                anchors.margins: -Style.space(4)
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleDone(row.index)
              }
            }

            // Édition en place : Entrée valide, Échap annule.
            TextField {
              id: editor
              visible: row.isEditing
              anchors.left: check.right
              anchors.leftMargin: Style.space(8)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              verticalPadding: Style.space(3)
              foreground: root.bar.foreground
              font.family: root.bar.fontFamily

              function begin() {
                text = Dates.editText(row.modelData, root.now)
                forceActiveFocus()
                cursorPosition = text.length
              }

              onVisibleChanged: if (visible) begin()
              Component.onCompleted: if (visible) begin()
              onAccepted: root.commitEdit(row.index, text)
              onActiveFocusChanged: if (!activeFocus && row.isEditing) root.commitEdit(row.index, text)
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.cancelEdit(); event.accepted = true
                }
              }
            }

            Text {
              visible: !row.isEditing
              textFormat: Text.PlainText
              text: row.modelData.text
              color: root.bar.foreground
              opacity: row.modelData.done ? 0.45 : 1
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              font.strikeout: row.modelData.done
              elide: Text.ElideRight
              anchors.left: check.right
              anchors.leftMargin: Style.space(10)
              anchors.right: dueLabel.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: dueLabel
              visible: !row.isEditing
              textFormat: Text.PlainText
              text: row.due.label
              color: row.modelData.done ? root.bar.foreground : root.dueColor(row.due.level)
              opacity: row.modelData.done ? 0.35 : (row.due.level === "later" ? 0.55 : 0.85)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: !row.modelData.done && (row.due.level === "overdue" || row.due.level === "today")
              anchors.right: actions.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
            }

            Row {
              id: actions
              visible: !row.isEditing
              opacity: row.hot ? 1 : 0
              spacing: Style.space(10)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter

              RowAction {
                glyph: root.iconEdit
                hoverColor: Color.accent
                onActivated: root.startEdit(row.index)
              }

              RowAction {
                glyph: root.iconDelete
                hoverColor: Color.urgent
                onActivated: root.remove(row.index)
              }
            }
          }
        }

        // ---------- Pied ----------
        Item {
          visible: root.doneCount > 0
          width: parent.width
          implicitHeight: clearButton.implicitHeight

          Button {
            id: clearButton
            anchors.right: parent.right
            iconText: root.iconClear
            text: "Effacer les terminées (" + root.doneCount + ")"
            fontSize: Style.font.bodySmall
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            onClicked: root.clearDone()
          }
        }
      }
    }
  }

  component RowAction: Text {
    id: action
    property string glyph: ""
    property color hoverColor: Color.accent
    signal activated()

    textFormat: Text.PlainText
    text: glyph
    color: actionMouse.containsMouse ? hoverColor : root.bar.foreground
    opacity: actionMouse.containsMouse ? 1 : 0.6
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.icon

    MouseArea {
      id: actionMouse
      anchors.fill: parent
      anchors.margins: -Style.space(4)
      hoverEnabled: true
      enabled: action.parent && action.parent.opacity > 0
      cursorShape: Qt.PointingHandCursor
      onClicked: action.activated()
    }
  }
}
