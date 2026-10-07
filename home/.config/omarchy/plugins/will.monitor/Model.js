function clampBrightness(value) {
  var n = Number(value)
  if (!isFinite(n)) return 1
  return Math.max(1, Math.min(100, Math.round(n)))
}

function normalizeScale(scale) {
  var n = parseFloat(String(scale || ""))
  if (!isFinite(n)) return ""
  return String(Math.round(n * 100) / 100)
}

function gcd(a, b) {
  while (b) {
    var remainder = a % b
    a = b
    b = remainder
  }
  return a
}

function cleanScale(scale, width, height) {
  var requested = Number(scale)
  var modeWidth = Number(width)
  var modeHeight = Number(height)
  if (!isFinite(requested) || !isFinite(modeWidth) || !isFinite(modeHeight)
      || requested <= 0 || modeWidth <= 0 || modeHeight <= 0) return ""

  var divisor = gcd(Math.round(modeWidth * 120), Math.round(modeHeight * 120))
  var scaleUnits = Math.round(requested * 120)
  if (scaleUnits > divisor) scaleUnits = divisor
  while (divisor % scaleUnits !== 0) scaleUnits++
  return normalizeScale(scaleUnits / 120)
}

function matchingScaleIndex(scales, currentScale, width, height) {
  var current = Number(currentScale)
  if (!Array.isArray(scales) || !isFinite(current)) return -1

  var bestIndex = -1
  var bestDistance = Infinity
  var normalizedCurrent = normalizeScale(current)
  for (var i = 0; i < scales.length; i++) {
    if (cleanScale(scales[i], width, height) !== normalizedCurrent) continue

    var distance = Math.abs(Number(scales[i]) - current)
    if (distance < bestDistance) {
      bestIndex = i
      bestDistance = distance
    }
  }
  return bestIndex
}

function availableScales(scales, width, height) {
  if (!Array.isArray(scales) || Number(width) <= 0 || Number(height) <= 0) return scales || []

  var byEffectiveScale = {}
  for (var i = 0; i < scales.length; i++) {
    var requested = Number(scales[i])
    var effective = Number(cleanScale(requested, width, height))

    if (!isFinite(requested) || !isFinite(effective)) continue

    var key = normalizeScale(effective)
    var existing = byEffectiveScale[key]
    if (!existing || Math.abs(requested - effective) < existing.distance) {
      byEffectiveScale[key] = {
        value: String(scales[i]),
        index: i,
        distance: Math.abs(requested - effective)
      }
    }
  }

  return Object.keys(byEffectiveScale)
    .map(function(key) { return byEffectiveScale[key] })
    .sort(function(a, b) { return a.index - b.index })
    .map(function(candidate) { return candidate.value })
}

function brightnessName(percent) {
  var p = Math.round(percent)
  if (p >= 95) return "Sun blast"
  if (p >= 80) return "Solar flare"
  if (p >= 65) return "Golden hour"
  if (p >= 45) return "Even day"
  if (p >= 30) return "Soft glow"
  if (p >= 20) return "Lamp light"
  if (p >= 10) return "Candlelit"
  return "Night owl"
}

function parseDisplays(raw) {
  var displays = []
  try {
    displays = raw ? JSON.parse(String(raw)) : []
  } catch (e) {
    displays = []
  }
  if (!Array.isArray(displays)) displays = []

  var count = 0
  for (var i = 0; i < displays.length; i++) {
    if (displays[i] && displays[i].enabled) count++
  }

  return {
    displays: displays,
    enabledDisplayCount: count
  }
}

// ---- Disposition libre des écrans (même algorithme que display-ctl) ----

function rangeOverlap(a0, a1, b0, b1) {
  return Math.min(a1, b1) - Math.max(a0, b0)
}

function rectsIntersect(a, b) {
  return rangeOverlap(a.x, a.x + a.w, b.x, b.x + b.w) > 0
      && rangeOverlap(a.y, a.y + a.h, b.y, b.y + b.h) > 0
}

// Positions où `r` est collé contre un bord de `p`, au plus près de sa
// position voulue ; aligne haut/bas/centre quand on en est à moins de
// `threshold` px logiques.
function snapCandidates(r, p, threshold, minOverlap) {
  var out = []
  var sides = ["left", "right", "top", "bottom"]
  for (var i = 0; i < sides.length; i++) {
    var side = sides[i]
    var x, y, need, lo, hi, aligns, j
    if (side === "left" || side === "right") {
      x = side === "left" ? p.x - r.w : p.x + p.w
      need = Math.min(minOverlap, r.h, p.h)
      lo = p.y - r.h + need
      hi = p.y + p.h - need
      y = Math.min(Math.max(r.y, lo), hi)
      aligns = [p.y, p.y + p.h - r.h, p.y + (p.h - r.h) / 2]
      for (j = 0; j < aligns.length; j++)
        if (Math.abs(y - aligns[j]) <= threshold && aligns[j] >= lo && aligns[j] <= hi) { y = aligns[j]; break }
    } else {
      y = side === "top" ? p.y - r.h : p.y + p.h
      need = Math.min(minOverlap, r.w, p.w)
      lo = p.x - r.w + need
      hi = p.x + p.w - need
      x = Math.min(Math.max(r.x, lo), hi)
      aligns = [p.x, p.x + p.w - r.w, p.x + (p.w - r.w) / 2]
      for (j = 0; j < aligns.length; j++)
        if (Math.abs(x - aligns[j]) <= threshold && aligns[j] >= lo && aligns[j] <= hi) { x = aligns[j]; break }
    }
    out.push({ x: Math.round(x), y: Math.round(y) })
  }
  return out
}

// Place l'écran `name` au plus près de (x, y) en le collant contre un des
// autres écrans (qui restent fixes). Retourne { x, y } en px logiques.
function snapMoved(rects, name, x, y, threshold, minOverlap) {
  var moving = null
  var others = []
  for (var i = 0; i < rects.length; i++) {
    if (rects[i].name === name) moving = { name: name, x: x, y: y, w: rects[i].w, h: rects[i].h }
    else others.push(rects[i])
  }
  if (!moving || !others.length) return { x: Math.round(x), y: Math.round(y) }

  var best = null
  var bestD = Infinity
  for (var p = 0; p < others.length; p++) {
    var cands = snapCandidates(moving, others[p], threshold, minOverlap)
    for (var c = 0; c < cands.length; c++) {
      var cand = { x: cands[c].x, y: cands[c].y, w: moving.w, h: moving.h }
      var clash = false
      for (var q = 0; q < others.length; q++)
        if (rectsIntersect(cand, others[q])) { clash = true; break }
      if (clash) continue
      var d = (cand.x - x) * (cand.x - x) + (cand.y - y) * (cand.y - y)
      if (d < bestD) { bestD = d; best = cand }
    }
  }
  return best ? { x: best.x, y: best.y } : { x: Math.round(x), y: Math.round(y) }
}

// Disposition complète pendant qu'on fait glisser l'écran `name` vers (x, y).
//  - Dans le vide : il se colle au bord le plus proche (snapMoved).
//  - Par-dessus d'autres écrans : on l'insère à cet endroit et les écrans
//    chevauchés s'écartent (de proche en proche) pour lui faire la place.
//    C'est ce qui permet de glisser un écran AU MILIEU de deux autres.
// Retourne { name: { x, y } } pour tous les écrans, en px logiques.
function layoutAfterDrag(rects, name, x, y, threshold, minOverlap) {
  var moving = null
  var others = []
  var i, j
  for (i = 0; i < rects.length; i++) {
    var r = rects[i]
    if (r.name === name) moving = { name: name, x: x, y: y, w: r.w, h: r.h }
    else others.push({ name: r.name, x: r.x, y: r.y, w: r.w, h: r.h })
  }
  var out = {}
  if (!moving) return out
  for (i = 0; i < others.length; i++) out[others[i].name] = { x: others[i].x, y: others[i].y }

  var overlapping = false
  for (i = 0; i < others.length; i++)
    if (rectsIntersect(moving, others[i])) { overlapping = true; break }

  if (!overlapping) {
    out[name] = snapMoved(rects, name, x, y, threshold, minOverlap)
    return out
  }

  // Alignement haut / centre / bas (ou gauche / centre / droite) sur les
  // écrans chevauchés quand on en est proche.
  var bestDy = threshold + 1, bestDx = threshold + 1, ay = moving.y, ax = moving.x
  for (i = 0; i < others.length; i++) {
    var o = others[i]
    if (!rectsIntersect(moving, o)) continue
    var ys = [o.y, o.y + o.h - moving.h, o.y + (o.h - moving.h) / 2]
    var xs = [o.x, o.x + o.w - moving.w, o.x + (o.w - moving.w) / 2]
    for (j = 0; j < 3; j++) {
      if (Math.abs(moving.y - ys[j]) < bestDy) { bestDy = Math.abs(moving.y - ys[j]); ay = ys[j] }
      if (Math.abs(moving.x - xs[j]) < bestDx) { bestDx = Math.abs(moving.x - xs[j]); ax = xs[j] }
    }
  }
  if (bestDy <= threshold) moving.y = ay
  if (bestDx <= threshold) moving.x = ax
  moving.x = Math.round(moving.x)
  moving.y = Math.round(moving.y)

  // Écarte les écrans chevauchés, du plus proche au plus lointain, chacun
  // poussé hors des écrans déjà placés dans la direction la plus courte qui
  // l'éloigne (gauche/droite ou haut/bas).
  var cx = moving.x + moving.w / 2, cy = moving.y + moving.h / 2
  others.sort(function(a, b) {
    var da = Math.abs(a.x + a.w / 2 - cx) + Math.abs(a.y + a.h / 2 - cy)
    var db = Math.abs(b.x + b.w / 2 - cx) + Math.abs(b.y + b.h / 2 - cy)
    return da - db
  })
  var placed = [moving]
  for (i = 0; i < others.length; i++) {
    var q = others[i]
    for (var guard = 0; guard < 8; guard++) {
      var hit = null
      for (j = 0; j < placed.length; j++) if (rectsIntersect(q, placed[j])) { hit = placed[j]; break }
      if (!hit) break
      var right = (q.x + q.w / 2) >= (hit.x + hit.w / 2)
      var down = (q.y + q.h / 2) >= (hit.y + hit.h / 2)
      var mx = right ? hit.x + hit.w - q.x : hit.x - (q.x + q.w)
      var my = down ? hit.y + hit.h - q.y : hit.y - (q.y + q.h)
      if (Math.abs(mx) <= Math.abs(my)) q.x += mx
      else q.y += my
    }
    placed.push(q)
    out[q.name] = { x: Math.round(q.x), y: Math.round(q.y) }
  }
  out[name] = { x: moving.x, y: moving.y }
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    clampBrightness: clampBrightness,
    normalizeScale: normalizeScale,
    cleanScale: cleanScale,
    matchingScaleIndex: matchingScaleIndex,
    availableScales: availableScales,
    brightnessName: brightnessName,
    parseDisplays: parseDisplays,
    snapMoved: snapMoved,
    layoutAfterDrag: layoutAfterDrag
  }
}
