import QtQuick
import "Model.js" as Model

// The orb: an orthographic globe drawn on two canvases. `base` holds the
// sphere, graticule and 239 country outlines and repaints only when the view
// moves; `overlay` holds the Mullvad city dots, route arcs and pulses and
// repaints every animation frame, so the pulse never re-projects the map.
Item {
  id: root

  property var shapes: []           // assets/countries.json
  property var world: ({ countries: [] })
  property var filter: ({})         // Model.relayFilter() for the exit hop
  property string selectedCountry: ""
  property string selectedCity: ""
  property string selectedHost: ""
  property var exitPoint: null      // {lat, lon} of the connected exit city
  property var entryPoint: null     // multihop entry city
  property var homePoint: null      // where Mullvad last saw you, unless hidden
  property string tunnelState: "unknown"

  property color sphereColor: "#1b1f24"
  property color landColor: "#3a424c"
  property color servedColor: "#4c5663"
  property color lineColor: "#9aa3ad"
  property color dotColor: "#e6e9ec"
  property color accentColor: "#7aa2f7"
  property color urgentColor: "#f7768e"
  property color textColor: "#e6e9ec"
  property color panelColor: "#101315"
  property string fontFamily: "monospace"
  property int fontSize: 11

  property real centreLat: 30
  property real centreLon: 10
  property real zoom: 1
  readonly property real minZoom: 0.8
  readonly property real maxZoom: 60
  readonly property real radius: Math.min(width, height) * 0.44 * zoom
  readonly property bool interacting: drag.active || flight.running

  signal countryClicked(string code)
  signal cityClicked(string country, string city)
  signal serverClicked(string country, string city, string hostname)
  signal cityActivated(string country, string city)

  Accessible.role: Accessible.Pane
  Accessible.name: "World map of Mullvad servers"
  Accessible.description: "Drag to rotate, scroll to zoom, click a dot to pick a city, double-click to connect"

  // ------------------------------------------------------------ geometry

  function vec(lat, lon) {
    var p = lat * Math.PI / 180, l = lon * Math.PI / 180, c = Math.cos(p)
    return [c * Math.cos(l), c * Math.sin(l), Math.sin(p)]
  }

  // Projection terms for the current view, computed once per paint.
  function view() {
    var p = centreLat * Math.PI / 180, l = centreLon * Math.PI / 180
    return { sp: Math.sin(p), cp: Math.cos(p), sl: Math.sin(l), cl: Math.cos(l),
             cx: width / 2, cy: height / 2, r: radius }
  }

  // Unit vector -> screen {x, y, d}; d < 0 is the far side.
  function place(v, X, Y, Z) {
    var h = X * v.cl + Y * v.sl
    var x = Y * v.cl - X * v.sl
    var y = v.cp * Z - v.sp * h
    return { x: v.cx + x * v.r, y: v.cy - y * v.r, d: v.sp * Z + v.cp * h }
  }

  property var rings: []      // [{code, pts: [X,Y,Z,...]}]
  property var grid: []
  property var cities: []     // Mullvad cities with unit vectors

  function prepareShapes() {
    var out = []
    for (var i = 0; i < shapes.length; i++) {
      for (var k = 0; k < shapes[i].r.length; k++) {
        var ring = shapes[i].r[k], pts = []
        for (var j = 0; j < ring.length; j += 2) {
          var v = vec(ring[j + 1], ring[j])
          pts.push(v[0], v[1], v[2])
        }
        // Bounding cap on the sphere (centre + angular radius) for culling.
        var mx = 0, my = 0, mz = 0
        for (var a = 0; a < pts.length; a += 3) { mx += pts[a]; my += pts[a + 1]; mz += pts[a + 2] }
        var ml = Math.sqrt(mx * mx + my * my + mz * mz) || 1
        mx /= ml; my /= ml; mz /= ml
        var minDot = 1
        for (var b = 0; b < pts.length; b += 3) minDot = Math.min(minDot, mx * pts[b] + my * pts[b + 1] + mz * pts[b + 2])
        out.push({ code: shapes[i].c.toLowerCase(), pts: pts, c: [mx, my, mz], reach: Math.acos(Math.max(-1, minDot)) })
      }
    }
    rings = out
  }

  function prepareGrid() {
    var out = [], lat, lon, line
    for (lat = -60; lat <= 60; lat += 30) {
      line = []
      for (lon = -180; lon <= 180; lon += 4) line.push.apply(line, vec(lat, lon))
      out.push(line)
    }
    for (lon = -180; lon < 180; lon += 30) {
      line = []
      for (lat = -90; lat <= 90; lat += 4) line.push.apply(line, vec(lat, lon))
      out.push(line)
    }
    grid = out
  }

  function prepareCities() {
    var out = []
    var list = world && world.countries ? world.countries : []
    for (var i = 0; i < list.length; i++) {
      for (var j = 0; j < list[i].cities.length; j++) {
        var c = list[i].cities[j]
        if (!isFinite(c.lat) || !isFinite(c.lon)) continue
        out.push({ country: c.country, city: c.code, name: c.name, countryName: c.countryName,
                   lat: c.lat, lon: c.lon, v: vec(c.lat, c.lon), total: c.relays.length,
                   matching: Model.matchingRelays(c, filter).length, relays: c.relays,
                   sx: 0, sy: 0, shown: false })
      }
    }
    cities = out
    servedCodes = {}
    for (var k = 0; k < list.length; k++) servedCodes[list[k].code] = true
  }
  property var servedCodes: ({})

  // Each hop is a great circle lifted off the surface like a flight path,
  // higher for longer hops, so it reads as an arc even when seen edge-on.
  function routeOf(points) {
    var out = []
    for (var i = 0; i + 1 < points.length; i++) {
      var arc = Model.greatCircle(points[i], points[i + 1], 64)
      var lift = Math.min(0.22, Model.distanceKm(points[i], points[i + 1]) / 40000)
      for (var j = 0; j < arc.length; j++) {
        var v = vec(arc[j].lat, arc[j].lon), h = 1 + lift * Math.sin(Math.PI * j / (arc.length - 1))
        out.push([v[0] * h, v[1] * h, v[2] * h])
      }
    }
    return out
  }
  readonly property var route: {
    if (!exitPoint) return []
    var pts = []
    if (homePoint) pts.push(homePoint)
    if (entryPoint) pts.push(entryPoint)
    pts.push(exitPoint)
    return pts.length > 1 ? routeOf(pts) : []
  }

  // ------------------------------------------------------------ painting

  // Rings are traced once per style into one path each. A ring's far-side
  // points are pinned to the horizon, which closes coastlines cleanly without
  // per-ring clipping; rings with no visible point are skipped outright.
  // While dragging, every other point is skipped.
  function traceRings(ctx, v, pick, stride) {
    // Angular radius of the part of the sphere the viewport can show.
    var half = Math.sqrt(width * width + height * height) / 2 / v.r
    var viewReach = half >= 1 ? Math.PI / 2 : Math.asin(half)
    var cx = v.cp * v.cl, cy = v.cp * v.sl, cz = v.sp
    ctx.beginPath()
    for (var i = 0; i < rings.length; i++) {
      var ring = rings[i]
      if (!pick(ring.code)) continue
      var dot = ring.c[0] * cx + ring.c[1] * cy + ring.c[2] * cz
      if (Math.acos(Math.max(-1, Math.min(1, dot))) > viewReach + ring.reach) continue
      var pts = ring.pts, n = pts.length, j
      var step = n > 60 ? 3 * stride : 3
      var visible = false
      for (j = 0; j < n; j += step) {
        if (v.sp * pts[j + 2] + v.cp * (pts[j] * v.cl + pts[j + 1] * v.sl) >= 0) { visible = true; break }
      }
      if (!visible) continue
      for (j = 0; j < n; j += step) {
        var X = pts[j], Y = pts[j + 1], Z = pts[j + 2]
        var h = X * v.cl + Y * v.sl
        var x = Y * v.cl - X * v.sl
        var y = v.cp * Z - v.sp * h
        if (v.sp * Z + v.cp * h < 0) {
          var len = Math.sqrt(x * x + y * y) || 1
          x /= len; y /= len
        }
        if (j === 0) ctx.moveTo(v.cx + x * v.r, v.cy - y * v.r)
        else ctx.lineTo(v.cx + x * v.r, v.cy - y * v.r)
      }
      ctx.closePath()
    }
  }

  // A point is hidden only when it is behind the globe: lifted route points
  // past the rim stay visible against the sky.
  function hidden(v, p) {
    if (p.d >= 0) return false
    var dx = p.x - v.cx, dy = p.y - v.cy
    return dx * dx + dy * dy < v.r * v.r
  }

  function traceLine(ctx, v, pts) {
    var drawing = false
    for (var i = 0; i < pts.length; i += 3) {
      var p = place(v, pts[i], pts[i + 1], pts[i + 2])
      if (hidden(v, p)) { drawing = false; continue }
      if (!drawing) ctx.moveTo(p.x, p.y)
      else ctx.lineTo(p.x, p.y)
      drawing = true
    }
  }

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  // fast: the half-resolution, un-antialiased frame drawn while the globe
  // moves (land fill dominates the cost); the full frame follows on release.
  function paintBase(ctx, fast) {
    ctx.reset()
    if (fast) ctx.scale(0.5, 0.5)
    var v = view()
    if (!(v.r > 0)) return
    var stride = fast ? 3 : 1

    // Atmosphere: a soft accent halo that makes the disc read as an orb.
    var halo = ctx.createRadialGradient(v.cx, v.cy, v.r * 0.96, v.cx, v.cy, v.r * 1.12)
    halo.addColorStop(0, alpha(accentColor, 0.22))
    halo.addColorStop(1, alpha(accentColor, 0))
    ctx.fillStyle = halo
    ctx.beginPath(); ctx.arc(v.cx, v.cy, v.r * 1.12, 0, Math.PI * 2); ctx.fill()

    var sphere = ctx.createRadialGradient(v.cx - v.r * 0.35, v.cy - v.r * 0.4, v.r * 0.05, v.cx, v.cy, v.r)
    sphere.addColorStop(0, Qt.lighter(sphereColor, 1.45))
    sphere.addColorStop(0.7, sphereColor)
    sphere.addColorStop(1, Qt.darker(sphereColor, 1.5))
    ctx.fillStyle = sphere
    ctx.beginPath(); ctx.arc(v.cx, v.cy, v.r, 0, Math.PI * 2); ctx.fill()

    ctx.save()
    ctx.beginPath(); ctx.arc(v.cx, v.cy, v.r - 0.5, 0, Math.PI * 2); ctx.clip()

    ctx.strokeStyle = alpha(lineColor, 0.12)
    ctx.lineWidth = 1
    ctx.beginPath()
    for (var g = 0; g < grid.length; g++) traceLine(ctx, v, grid[g])
    ctx.stroke()

    var served = servedCodes, sel = selectedCountry
    ctx.lineWidth = 0.7
    ctx.strokeStyle = alpha(lineColor, 0.28)
    traceRings(ctx, v, function(c) { return !served[c] }, stride)
    ctx.fillStyle = landColor
    ctx.fill()
    if (!fast) ctx.stroke()

    traceRings(ctx, v, function(c) { return served[c] && c !== sel }, stride)
    ctx.fillStyle = servedColor
    ctx.fill()
    if (!fast) ctx.stroke()

    if (sel) {
      traceRings(ctx, v, function(c) { return c === sel }, stride)
      ctx.fillStyle = Qt.tint(servedColor, alpha(accentColor, 0.3))
      ctx.strokeStyle = alpha(accentColor, 0.95)
      ctx.lineWidth = 1.4
      ctx.fill(); ctx.stroke()
    }

    // Terminator-style shading toward the rim keeps depth when zoomed out.
    var shade = ctx.createRadialGradient(v.cx, v.cy, v.r * 0.55, v.cx, v.cy, v.r)
    shade.addColorStop(0, alpha(sphereColor, 0))
    shade.addColorStop(1, alpha(Qt.darker(sphereColor, 1.6), 0.55))
    ctx.fillStyle = shade
    ctx.fillRect(v.cx - v.r, v.cy - v.r, v.r * 2, v.r * 2)
    ctx.restore()

    ctx.strokeStyle = alpha(lineColor, 0.45)
    ctx.lineWidth = 1
    ctx.beginPath(); ctx.arc(v.cx, v.cy, v.r, 0, Math.PI * 2); ctx.stroke()
  }

  property real phase: 0
  property var hovered: null        // {kind: "city"|"server", ...}
  property var serverSpots: []

  readonly property bool zoomedToCity: selectedCity !== "" && zoom >= 7

  function paintOverlay(ctx) {
    ctx.reset()
    var v = view()
    if (!(v.r > 0)) return
    var t = phase

    // Route: home -> (entry) -> exit, drawn as a glowing arc with a comet.
    var routePts = route
    if (routePts.length > 1) {
      var live = tunnelState === "connected"
      var col = tunnelState === "error" ? urgentColor : accentColor
      var flat = []
      for (var i = 0; i < routePts.length; i++) flat.push(routePts[i][0], routePts[i][1], routePts[i][2])
      ctx.lineCap = "round"
      ctx.strokeStyle = alpha(col, 0.18); ctx.lineWidth = 6
      ctx.beginPath(); traceLine(ctx, v, flat); ctx.stroke()
      ctx.strokeStyle = alpha(col, live ? 0.9 : 0.35 + 0.35 * Math.abs(Math.sin(t * 4)))
      ctx.lineWidth = 1.8
      ctx.beginPath(); traceLine(ctx, v, flat); ctx.stroke()
      var k = Math.floor(((t * 0.35) % 1) * (routePts.length - 1))
      var comet = place(v, routePts[k][0], routePts[k][1], routePts[k][2])
      if (!hidden(v, comet)) {
        ctx.fillStyle = alpha(col, 0.95)
        ctx.beginPath(); ctx.arc(comet.x, comet.y, 3, 0, Math.PI * 2); ctx.fill()
      }
    }

    if (homePoint) {
      var hv = vec(homePoint.lat, homePoint.lon)
      var hp = place(v, hv[0], hv[1], hv[2])
      if (hp.d > 0) {
        ctx.strokeStyle = alpha(textColor, 0.9); ctx.lineWidth = 1.5
        ctx.beginPath(); ctx.arc(hp.x, hp.y, 4, 0, Math.PI * 2); ctx.stroke()
        label(ctx, "You", hp.x + 7, hp.y - 7, 0.8)
      }
    }

    // City dots: size by server count, dimmed when filters leave none.
    var spots = [], labels = []
    var labelled = selectedCountry !== "" && zoom >= 2.2
    for (var c = 0; c < cities.length; c++) {
      var city = cities[c]
      var p = place(v, city.v[0], city.v[1], city.v[2])
      city.shown = p.d > 0.02 && p.x > -10 && p.x < width + 10 && p.y > -10 && p.y < height + 10
      city.sx = p.x; city.sy = p.y
      if (!city.shown) continue
      var isSel = city.country === selectedCountry && city.city === selectedCity
      var inSel = city.country === selectedCountry
      var size = Math.min(6, 2 + Math.sqrt(city.total) * 0.7) * (0.75 + 0.25 * p.d)
      ctx.globalAlpha = city.matching > 0 ? (0.55 + 0.45 * p.d) : 0.25
      ctx.fillStyle = isSel ? accentColor : dotColor
      ctx.beginPath(); ctx.arc(p.x, p.y, isSel ? size + 1.5 : size, 0, Math.PI * 2); ctx.fill()
      ctx.globalAlpha = 1
      if (isSel) {
        ctx.strokeStyle = alpha(accentColor, 0.8); ctx.lineWidth = 1.2
        ctx.beginPath(); ctx.arc(p.x, p.y, size + 6, 0, Math.PI * 2); ctx.stroke()
      }
      if ((labelled && inSel) || isSel) labels.push({ text: city.name, x: p.x + size + 5, y: p.y + 4, sel: isSel, rank: city.total })
    }

    // Labels: the selected city first, then bigger cities; skip overlaps.
    labels.sort(function(a, b) { return a.sel !== b.sel ? (a.sel ? -1 : 1) : b.rank - a.rank })
    ctx.font = fontSize + "px \"" + fontFamily + "\""
    var placed = []
    for (var li = 0; li < labels.length; li++) {
      var L = labels[li], w = ctx.measureText(L.text).width, h = fontSize + 2
      var clash = false
      for (var pi = 0; pi < placed.length && !clash; pi++) {
        var P = placed[pi]
        clash = L.x < P.x + P.w + 4 && L.x + w + 4 > P.x && L.y - h < P.y && L.y > P.y - h
      }
      if (clash) continue
      placed.push({ x: L.x, y: L.y, w: w })
      label(ctx, L.text, L.x, L.y, L.sel ? 1 : 0.75)
    }

    // Zoomed onto a city: fan its servers out on a ring so each is pickable.
    if (zoomedToCity) {
      for (var s = 0; s < cities.length; s++) {
        var sc = cities[s]
        if (sc.country !== selectedCountry || sc.city !== selectedCity || !sc.shown) continue
        var n = sc.relays.length, ringR = Math.max(28, Math.min(70, n * 5))
        ctx.strokeStyle = alpha(lineColor, 0.25); ctx.lineWidth = 1
        ctx.beginPath(); ctx.arc(sc.sx, sc.sy, ringR, 0, Math.PI * 2); ctx.stroke()
        for (var q = 0; q < n; q++) {
          var ang = -Math.PI / 2 + q * Math.PI * 2 / n
          var rx = sc.sx + Math.cos(ang) * ringR, ry = sc.sy + Math.sin(ang) * ringR
          var relay = sc.relays[q]
          var ok = Model.relayMatches(relay, filter)
          var chosen = relay.hostname === selectedHost
          ctx.globalAlpha = ok ? 1 : 0.3
          ctx.fillStyle = chosen ? accentColor : (relay.owned ? dotColor : alpha(dotColor, 0.6))
          ctx.beginPath(); ctx.arc(rx, ry, chosen ? 5 : 3.5, 0, Math.PI * 2); ctx.fill()
          ctx.globalAlpha = 1
          if (chosen) {
            ctx.strokeStyle = accentColor; ctx.lineWidth = 1.2
            ctx.beginPath(); ctx.arc(rx, ry, 8, 0, Math.PI * 2); ctx.stroke()
          }
          spots.push({ x: rx, y: ry, relay: relay, city: sc })
        }
      }
    }
    serverSpots = spots

    // Connection markers pulse on top of everything.
    marker(ctx, v, entryPoint, textColor, t, false)
    marker(ctx, v, exitPoint, tunnelState === "error" ? urgentColor : accentColor, t, true)
  }

  function marker(ctx, v, point, col, t, strong) {
    if (!point) return
    var mv = vec(point.lat, point.lon)
    var p = place(v, mv[0], mv[1], mv[2])
    if (p.d <= 0) return
    for (var w = 0; w < 2; w++) {
      var f = ((t * 0.6) + w * 0.5) % 1
      ctx.strokeStyle = alpha(col, (1 - f) * (strong ? 0.9 : 0.6))
      ctx.lineWidth = strong ? 2 : 1.4
      ctx.beginPath(); ctx.arc(p.x, p.y, 5 + f * (strong ? 22 : 14), 0, Math.PI * 2); ctx.stroke()
    }
    ctx.fillStyle = col
    ctx.beginPath(); ctx.arc(p.x, p.y, strong ? 4.5 : 3.5, 0, Math.PI * 2); ctx.fill()
  }

  function label(ctx, text, x, y, a) {
    ctx.font = fontSize + "px \"" + fontFamily + "\""
    ctx.lineWidth = 3
    ctx.strokeStyle = alpha(panelColor, 0.85 * a)
    ctx.strokeText(text, x, y)
    ctx.fillStyle = alpha(textColor, a)
    ctx.fillText(text, x, y)
  }

  // ------------------------------------------------------------ picking

  function cityAt(x, y) {
    var best = null, bestD = 12 * 12
    for (var i = 0; i < cities.length; i++) {
      var c = cities[i]
      if (!c.shown) continue
      var dx = c.sx - x, dy = c.sy - y, d = dx * dx + dy * dy
      if (d < bestD) { best = c; bestD = d }
    }
    return best
  }

  function serverAt(x, y) {
    for (var i = 0; i < serverSpots.length; i++) {
      var s = serverSpots[i], dx = s.x - x, dy = s.y - y
      if (dx * dx + dy * dy < 8 * 8) return s
    }
    return null
  }

  function geoAt(x, y) {
    var r = radius
    return Model.unproject((x - width / 2) / r, -(y - height / 2) / r, centreLat, centreLon)
  }

  // The city under the first tap of a double-click: by the second tap the
  // camera may already be flying, so the second hit-test can't be trusted.
  property var tappedCity: null

  function pick(x, y) {
    var s = serverAt(x, y)
    tappedCity = null
    if (s) { serverClicked(s.city.country, s.city.city, s.relay.hostname); return }
    var c = cityAt(x, y)
    tappedCity = c
    if (c) { cityClicked(c.country, c.city); return }
    var g = geoAt(x, y)
    if (!g) return
    var shape = Model.countryAt(shapes, g.lat, g.lon)
    if (shape && shape.c) countryClicked(shape.c.toLowerCase())
  }

  // ------------------------------------------------------------ camera

  function flyTo(lat, lon, zoomTo) {
    flight.stop()
    var targetLon = centreLon + Model.lonDelta(centreLon, lon)
    var far = Math.abs(targetLon - centreLon) + Math.abs(lat - centreLat) > 50
    latAnim.to = Model.clamp(lat, -75, 75)
    lonAnim.to = targetLon
    var z = Model.clamp(zoomTo, minZoom, maxZoom)
    zoomOut.to = far ? Math.min(zoom, 1.1, z) : zoom
    zoomIn.to = z
    flight.start()
  }

  function focusCountry(code) {
    var shape = null
    for (var i = 0; i < shapes.length; i++) if (shapes[i].c.toLowerCase() === code) { shape = shapes[i]; break }
    var country = Model.findCountry(world, code)
    var box = Model.focusBox(shape, country ? country.cities : [])
    if (box) flyTo(box.lat, box.lon, Model.scaleForSpan(box.spanLat, box.spanLon, box.lat, 0.5, 12))
  }

  function focusCity(countryCode, cityCode) {
    var city = Model.findCity(world, countryCode, cityCode)
    if (city) flyTo(city.lat, city.lon, Math.max(zoom, 9))
  }

  function focusPoint(p, z) { if (p) flyTo(p.lat, p.lon, z || Math.max(zoom, 2.5)) }

  // Frame a whole route (home/entry -> exit) around its great-circle middle.
  function focusRoute(a, b) {
    if (!a || !b) { focusPoint(b || a, 2.2); return }
    var mid = Model.greatCircle(a, b, 2)[1]
    var span = Model.distanceKm(a, b) / 111.2
    // Look from slightly beside the route: seen dead-centre, the lifted arc
    // points at the camera and reads as a straight line.
    var eastWest = Math.abs(Model.lonDelta(a.lon, b.lon) * Math.cos(mid.lat * Math.PI / 180)) > Math.abs(b.lat - a.lat)
    var lat = eastWest ? mid.lat - (mid.lat >= 0 ? 1 : -1) * span * 0.22 : mid.lat
    var lon = eastWest ? mid.lon : mid.lon + span * 0.22
    flyTo(lat, lon, Model.scaleForSpan(span, span, 0, 0.55, 6))
  }

  function resetView() { flyTo(centreLat, centreLon, 1) }

  function zoomBy(factor) {
    flight.stop()
    wheeling.restart()
    zoom = Model.clamp(zoom * factor, minZoom, maxZoom)
  }

  function nudge(dLon, dLat) {
    flight.stop()
    centreLon = Model.wrapLon(centreLon + dLon / zoom)
    centreLat = Model.clamp(centreLat + dLat / zoom, -80, 80)
  }

  ParallelAnimation {
    id: flight
    NumberAnimation { id: latAnim; target: root; property: "centreLat"; duration: 900; easing.type: Easing.InOutCubic }
    NumberAnimation { id: lonAnim; target: root; property: "centreLon"; duration: 900; easing.type: Easing.InOutCubic }
    SequentialAnimation {
      NumberAnimation { id: zoomOut; target: root; property: "zoom"; duration: 350; easing.type: Easing.OutQuad }
      NumberAnimation { id: zoomIn; target: root; property: "zoom"; duration: 550; easing.type: Easing.InOutCubic }
    }
    onFinished: root.centreLon = Model.wrapLon(root.centreLon)
  }

  // ------------------------------------------------------------ wiring

  readonly property bool moving: interacting || wheeling.running

  Canvas {
    id: base
    anchors.fill: parent
    visible: !root.moving
    onPaint: root.paintBase(getContext("2d"), false)
  }

  Canvas {
    id: baseFast
    width: parent.width / 2
    height: parent.height / 2
    scale: 2
    transformOrigin: Item.TopLeft
    antialiasing: false
    smooth: true
    visible: root.moving
    onPaint: root.paintBase(getContext("2d"), true)
  }

  Timer { id: wheeling; interval: 220 }

  Canvas {
    id: overlay
    anchors.fill: parent
    onPaint: root.paintOverlay(getContext("2d"))
  }

  function repaint() {
    if (moving) baseFast.requestPaint()
    else base.requestPaint()
    overlay.requestPaint()
  }

  // Pulses/comet only animate while something is live. The panel creates the
  // globe only while it is open, so a closed orb never animates.
  FrameAnimation {
    running: root.exitPoint !== null || root.tunnelState === "connecting"
    onTriggered: { root.phase += frameTime; overlay.requestPaint() }
  }

  onShapesChanged: { prepareShapes(); repaint() }
  onWorldChanged: { prepareCities(); repaint() }
  onFilterChanged: { prepareCities(); overlay.requestPaint() }
  onCentreLatChanged: repaint()
  onCentreLonChanged: repaint()
  onZoomChanged: repaint()
  onWidthChanged: repaint()
  onHeightChanged: repaint()
  onMovingChanged: repaint()
  onSelectedCountryChanged: repaint()
  onSelectedCityChanged: overlay.requestPaint()
  onSelectedHostChanged: overlay.requestPaint()
  onRouteChanged: overlay.requestPaint()
  onExitPointChanged: overlay.requestPaint()
  onHomePointChanged: overlay.requestPaint()
  onTunnelStateChanged: overlay.requestPaint()
  onSphereColorChanged: repaint()
  onLandColorChanged: repaint()
  onServedColorChanged: repaint()
  onLineColorChanged: repaint()
  onDotColorChanged: repaint()
  onAccentColorChanged: repaint()
  onUrgentColorChanged: repaint()
  onTextColorChanged: repaint()
  onPanelColorChanged: repaint()

  Component.onCompleted: { prepareGrid(); prepareShapes(); prepareCities(); repaint() }

  DragHandler {
    id: drag
    target: null
    property point last
    onActiveChanged: if (active) { flight.stop(); last = centroid.position }
    onCentroidChanged: {
      if (!active) return
      var dx = centroid.position.x - last.x, dy = centroid.position.y - last.y
      last = centroid.position
      var k = 180 / Math.PI / Math.max(1, root.radius)
      root.centreLon = Model.wrapLon(root.centreLon - dx * k)
      root.centreLat = Model.clamp(root.centreLat + dy * k, -80, 80)
    }
  }

  WheelHandler {
    target: null
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: function(event) { root.zoomBy(Math.exp(event.angleDelta.y / 600)) }
  }

  TapHandler {
    acceptedButtons: Qt.LeftButton
    gesturePolicy: TapHandler.DragThreshold
    onTapped: function(point) {
      if (tapCount > 1) return
      root.pick(point.position.x, point.position.y)
    }
    onDoubleTapped: function(point) {
      var c = root.tappedCity
      if (c) root.cityActivated(c.country, c.city)
    }
  }

  HoverHandler {
    id: hover
    onPointChanged: {
      if (root.interacting) { root.hovered = null; return }
      var x = point.position.x, y = point.position.y
      var s = root.serverAt(x, y)
      if (s) { root.hovered = { kind: "server", x: x, y: y, relay: s.relay, city: s.city }; return }
      var c = root.cityAt(x, y)
      root.hovered = c ? { kind: "city", x: x, y: y, city: c } : null
    }
    onHoveredChanged: if (!hovered) root.hovered = null
    cursorShape: drag.active ? Qt.ClosedHandCursor : (root.hovered ? Qt.PointingHandCursor : Qt.OpenHandCursor)
  }

  // Hover card: city (server count, distance from you) or a single server.
  Rectangle {
    id: tip
    readonly property var h: root.hovered
    visible: h !== null
    x: h ? Math.min(root.width - width - 6, h.x + 14) : 0
    y: h ? Math.min(root.height - height - 6, h.y + 14) : 0
    width: tipColumn.implicitWidth + 16
    height: tipColumn.implicitHeight + 10
    color: root.alpha(root.panelColor, 0.94)
    border.color: root.alpha(root.lineColor, 0.5)
    border.width: 1
    radius: 2

    Column {
      id: tipColumn
      anchors.centerIn: parent
      spacing: 2
      Text {
        textFormat: Text.PlainText
        text: !tip.h ? "" : (tip.h.kind === "server" ? tip.h.relay.hostname : tip.h.city.name + ", " + tip.h.city.countryName)
        color: root.textColor
        font.family: root.fontFamily
        font.pixelSize: root.fontSize + 1
        font.bold: true
      }
      Text {
        textFormat: Text.PlainText
        text: {
          var h = tip.h
          if (!h) return ""
          if (h.kind === "server") {
            var r = h.relay, bits = [r.owned ? "Mullvad-owned" : "Rented", r.provider]
            if (r.daita) bits.push("DAITA")
            if (r.quic) bits.push("QUIC")
            if (r.lwo) bits.push("LWO")
            return bits.join(" · ")
          }
          var line = h.city.matching + (h.city.matching === 1 ? " server" : " servers")
          if (h.city.matching !== h.city.total) line += " of " + h.city.total + " match filters"
          if (root.homePoint) line += " · ~" + Math.round(Model.distanceKm(root.homePoint, h.city)).toLocaleString() + " km away"
          return line
        }
        color: root.alpha(root.textColor, 0.7)
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
      }
    }
  }
}
