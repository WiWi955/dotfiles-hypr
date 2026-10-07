.pragma library

// Dates limites des tâches, stockées en "AAAA-MM-JJ" (heure locale).
//
// Dans le texte d'une tâche, un mot commençant par @ fixe la date limite :
//   @hier  @auj  @demain  @apres-demain  @lundi … @dim  @+3 (jours)  @+2s (semaines)
//   @25/10  @25/10/2026
// Un mot @ qui n'est pas une date (ex. @bob) reste dans le texte.

var WEEKDAYS = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]
var SHORT_DAYS = ["dim.", "lun.", "mar.", "mer.", "jeu.", "ven.", "sam."]

function pad(n) { return (n < 10 ? "0" : "") + n }

function startOfDay(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()) }

function addDays(d, n) { return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n) }

function toIso(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) }

function fromIso(s) {
  var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(s || ""))
  return m ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])) : null
}

function daysBetween(a, b) {
  return Math.round((startOfDay(b) - startOfDay(a)) / 86400000)
}

function simplify(word) {
  var s = String(word).toLowerCase()
  try { s = s.normalize("NFD").replace(/[̀-ͯ]/g, "") } catch (e) {}
  return s.replace(/['’]/g, "")
}

// Renvoie une Date pour un mot (sans le @), ou null si ce n'est pas une date.
function parseWord(word, now) {
  var w = simplify(word)
  var today = startOfDay(now)
  if (w === "auj" || w === "aujourdhui" || w === "today") return today
  if (w === "hier") return addDays(today, -1)
  if (w === "demain" || w === "dem" || w === "tomorrow") return addDays(today, 1)
  if (w === "apres-demain" || w === "apresdemain") return addDays(today, 2)

  var rel = /^\+(\d{1,3})([js]?)$/.exec(w)
  if (rel) return addDays(today, Number(rel[1]) * (rel[2] === "s" ? 7 : 1))

  if (w.length >= 3) {
    for (var i = 0; i < WEEKDAYS.length; i++) {
      if (WEEKDAYS[i].indexOf(w) === 0) {
        var delta = (i - today.getDay() + 7) % 7
        return addDays(today, delta === 0 ? 7 : delta)
      }
    }
  }

  var dm = /^(\d{1,2})[\/.-](\d{1,2})(?:[\/.-](\d{2}|\d{4}))?$/.exec(w)
  if (dm) {
    var day = Number(dm[1]), month = Number(dm[2]) - 1
    var year = dm[3] ? Number(dm[3]) : today.getFullYear()
    if (year < 100) year += 2000
    var d = new Date(year, month, day)
    if (d.getMonth() !== month || d.getDate() !== day) return null
    if (!dm[3] && d < today) d = new Date(year + 1, month, day)
    return d
  }
  return null
}

// "Appeler maman @demain" → { text: "Appeler maman", due: "2026-10-08" }
function parseInput(raw, now) {
  var due = ""
  var words = String(raw || "").trim().split(/\s+/)
  var kept = []
  for (var i = 0; i < words.length; i++) {
    var w = words[i]
    if (due === "" && w.length > 1 && w.charAt(0) === "@") {
      var d = parseWord(w.slice(1), now)
      if (d) { due = toIso(d); continue }
    }
    kept.push(w)
  }
  return { text: kept.join(" ").trim(), due: due }
}

// Texte à mettre dans le champ d'édition pour une tâche existante.
function editText(todo, now) {
  var d = fromIso(todo.due)
  if (!d) return todo.text
  var token = pad(d.getDate()) + "/" + pad(d.getMonth() + 1)
  if (d.getFullYear() !== now.getFullYear()) token += "/" + d.getFullYear()
  return todo.text + " @" + token
}

// { label, level } avec level = "overdue" | "today" | "soon" | "later" | ""
function dueInfo(due, now) {
  var d = fromIso(due)
  if (!d) return { label: "", level: "" }
  var diff = daysBetween(now, d)
  if (diff < -1) return { label: "en retard de " + (-diff) + " j", level: "overdue" }
  if (diff === -1) return { label: "hier", level: "overdue" }
  if (diff === 0) return { label: "aujourd'hui", level: "today" }
  if (diff === 1) return { label: "demain", level: "soon" }
  if (diff < 7) return { label: SHORT_DAYS[d.getDay()] + " " + pad(d.getDate()), level: "soon" }
  var label = pad(d.getDate()) + "/" + pad(d.getMonth() + 1)
  if (d.getFullYear() !== now.getFullYear()) label += "/" + d.getFullYear()
  return { label: label, level: "later" }
}

// Tri par date limite (la plus proche en haut), tâches sans date à la fin.
// À date égale, l'ordre existant est conservé.
function sortByDue(todos) {
  return todos
    .map(function(t, i) { return { t: t, i: i, key: fromIso(t.due) ? t.due : "9999-99-99" } })
    .sort(function(a, b) { return a.key < b.key ? -1 : a.key > b.key ? 1 : a.i - b.i })
    .map(function(e) { return e.t })
}
