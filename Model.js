.pragma library

// Pure helpers shared by the service, panel and globe. No QML types here, so
// test/model.test.mjs can exercise every function under plain node.

// ---------------------------------------------------------------- relays

// /var/cache/mullvad-vpn/relays.json -> sorted countries > cities > relays.
// Inactive relays are dropped: the daemon never picks them either.
function buildWorld(raw) {
  var locations = raw && raw.locations ? raw.locations : {}
  var relays = raw && raw.wireguard && Array.isArray(raw.wireguard.relays) ? raw.wireguard.relays : []
  var byCountry = {}
  var providers = {}
  for (var i = 0; i < relays.length; i++) {
    var r = relays[i]
    if (!r || r.active === false) continue
    var key = String(r.location || "")
    var dash = key.indexOf("-")
    var loc = locations[key]
    if (dash < 1 || !loc) continue
    var cc = key.slice(0, dash)
    var cityCode = key.slice(dash + 1)
    var country = byCountry[cc]
    if (!country) country = byCountry[cc] = { code: cc, name: String(loc.country || cc), cities: {}, relayCount: 0 }
    var city = country.cities[cityCode]
    if (!city) {
      city = country.cities[cityCode] = {
        code: cityCode, name: String(loc.city || cityCode),
        country: cc, countryName: country.name,
        lat: Number(loc.latitude), lon: Number(loc.longitude), relays: []
      }
    }
    var features = r.features || {}
    city.relays.push({
      hostname: String(r.hostname || ""),
      country: cc, city: cityCode,
      owned: r.owned === true,
      provider: String(r.provider || ""),
      daita: r.daita === true,
      quic: features.quic !== undefined && features.quic !== null,
      lwo: features.lwo !== undefined && features.lwo !== null,
      ipv4: String(r.ipv4_addr_in || ""),
      ipv6: String(r.ipv6_addr_in || ""),
      includeInCountry: r.include_in_country !== false
    })
    country.relayCount++
    if (r.provider) providers[r.provider] = true
  }
  var countries = []
  for (var code in byCountry) {
    var c = byCountry[code]
    var cities = []
    for (var cityKey in c.cities) {
      c.cities[cityKey].relays.sort(function(a, b) { return a.hostname < b.hostname ? -1 : 1 })
      cities.push(c.cities[cityKey])
    }
    cities.sort(byName)
    c.cities = cities
    countries.push(c)
  }
  countries.sort(byName)
  return { countries: countries, providers: Object.keys(providers).sort(caseless) }
}

function byName(a, b) { return caseless(a.name, b.name) }
function caseless(a, b) {
  var x = String(a).toLowerCase(), y = String(b).toLowerCase()
  return x < y ? -1 : (x > y ? 1 : 0)
}

function findCountry(world, code) {
  var list = world && world.countries ? world.countries : []
  for (var i = 0; i < list.length; i++) if (list[i].code === code) return list[i]
  return null
}

function findCity(world, countryCode, cityCode) {
  var country = findCountry(world, countryCode)
  if (!country) return null
  for (var i = 0; i < country.cities.length; i++) if (country.cities[i].code === cityCode) return country.cities[i]
  return null
}

function findRelay(world, hostname) {
  var list = world && world.countries ? world.countries : []
  for (var i = 0; i < list.length; i++)
    for (var j = 0; j < list[i].cities.length; j++) {
      var relays = list[i].cities[j].relays
      for (var k = 0; k < relays.length; k++) if (relays[k].hostname === hostname) return relays[k]
    }
  return null
}

// Would the daemon accept this relay under the active filters? Mirrors the
// constraints the Mullvad app greys locations out for: ownership, providers,
// DAITA without automatic multihop, and QUIC/LWO anti-censorship.
function relayMatches(relay, filter) {
  if (!relay) return false
  var f = filter || {}
  if (f.ownership === "owned" && !relay.owned) return false
  if (f.ownership === "rented" && relay.owned) return false
  if (Array.isArray(f.providers) && f.providers.length > 0 && f.providers.indexOf(relay.provider) === -1) return false
  if (f.daita && !relay.daita) return false
  if (f.obfuscation === "quic" && !relay.quic) return false
  if (f.obfuscation === "lwo" && !relay.lwo) return false
  return true
}

function matchingRelays(city, filter) {
  var out = []
  var relays = city && city.relays ? city.relays : []
  for (var i = 0; i < relays.length; i++) if (relayMatches(relays[i], filter)) out.push(relays[i])
  return out
}

// Filter for the exit (hop = "exit") or entry (hop = "entry") relay.
function relayFilter(view, hop) {
  var v = view || {}
  var daitaNeeded = v.daita === true && (hop === "entry" ? v.multihop === true : (!v.multihop && v.daitaDirectOnly === true))
  var obfuscation = hop === "exit" && v.multihop ? "" : (v.obfuscation ? v.obfuscation.mode : "")
  return {
    ownership: v.ownership || "any",
    providers: v.providers || [],
    daita: daitaNeeded,
    obfuscation: obfuscation
  }
}

// ---------------------------------------------------------------- settings

// Normalise the daemon's location constraint (settings.json shape).
function locationOf(constraint) {
  if (!constraint || constraint === "any" || !constraint.only) return { kind: "any" }
  var only = constraint.only
  if (only.custom_list) return { kind: "list", listId: String(only.custom_list.list_id || "") }
  var l = only.location || {}
  if (Array.isArray(l.hostname)) return { kind: "host", country: l.hostname[0], city: l.hostname[1], hostname: l.hostname[2] }
  if (Array.isArray(l.city)) return { kind: "city", country: l.city[0], city: l.city[1] }
  if (l.country) return { kind: "country", country: l.country }
  return { kind: "any" }
}

function onlyValue(constraint) {
  return constraint && constraint !== "any" && constraint.only !== undefined ? constraint.only : null
}

function ownershipOf(constraint) {
  var only = String(onlyValue(constraint) || "")
  if (/owned/i.test(only)) return "owned"
  if (/rented/i.test(only)) return "rented"
  return "any"
}

function portOf(setting) {
  var only = onlyValue(setting && setting.port)
  return only === null ? "any" : String(only)
}

// settings.json uses snake_case ("udp2_tcp", "wireguard_port"); the CLI takes
// kebab ("udp2tcp", "wireguard-port"). Compare on letters+digits only.
var obfuscationModes = ["auto", "off", "wireguard-port", "udp2tcp", "shadowsocks", "quic", "lwo"]
function obfuscationMode(fileValue) {
  var bare = String(fileValue || "auto").toLowerCase().replace(/[^a-z0-9]/g, "")
  for (var i = 0; i < obfuscationModes.length; i++)
    if (obfuscationModes[i].replace(/[^a-z0-9]/g, "") === bare) return obfuscationModes[i]
  return "auto"
}

var dnsBlockers = [
  { key: "block_ads", flag: "--block-ads", label: "Ads" },
  { key: "block_trackers", flag: "--block-trackers", label: "Trackers" },
  { key: "block_malware", flag: "--block-malware", label: "Malware" },
  { key: "block_gambling", flag: "--block-gambling", label: "Gambling" },
  { key: "block_adult_content", flag: "--block-adult-content", label: "Adult content" },
  { key: "block_social_media", flag: "--block-social-media", label: "Social media" }
]

function settingsView(s) {
  s = s || {}
  var relay = s.relay_settings && s.relay_settings.normal ? s.relay_settings.normal : null
  var wgc = relay && relay.wireguard_constraints ? relay.wireguard_constraints : {}
  var tunnel = s.tunnel_options || {}
  var wg = tunnel.wireguard || {}
  var daita = wg.daita || {}
  var dns = tunnel.dns_options || {}
  var blockers = dns.default_options || {}
  var obf = s.obfuscation_settings || {}
  var providers = onlyValue(relay && relay.providers)
  var ipVersion = onlyValue(wgc.ip_version)
  var rotation = wg.rotation_interval
  var lists = s.custom_lists && Array.isArray(s.custom_lists.custom_lists) ? s.custom_lists.custom_lists : []
  var methods = []
  var api = s.api_access_methods || {}
  var builtIns = ["direct", "mullvad_bridges", "encrypted_dns_proxy"]
  for (var b = 0; b < builtIns.length; b++) if (api[builtIns[b]]) methods.push(apiMethod(api[builtIns[b]], true))
  if (Array.isArray(api.custom)) for (var m = 0; m < api.custom.length; m++) methods.push(apiMethod(api.custom[m], false))
  var blockerState = {}
  for (var i = 0; i < dnsBlockers.length; i++) blockerState[dnsBlockers[i].key] = blockers[dnsBlockers[i].key] === true
  return {
    customRelay: !relay,
    exit: relay ? locationOf(relay.location) : { kind: "any" },
    entry: locationOf(wgc.entry_location),
    multihop: wgc.use_multihop === true,
    ownership: relay ? ownershipOf(relay.ownership) : "any",
    providers: providers && Array.isArray(providers.providers) ? providers.providers.slice() : [],
    ipVersion: ipVersion ? String(ipVersion) : "any",
    allowLan: s.allow_lan === true,
    lockdown: s.lockdown_mode === true,
    autoConnect: s.auto_connect === true,
    beta: s.show_beta_releases === true,
    daita: daita.enabled === true,
    daitaDirectOnly: daita.enabled === true && daita.use_multihop_if_necessary === false,
    quantum: String(wg.quantum_resistant || "auto"),
    mtu: typeof wg.mtu === "number" ? wg.mtu : null,
    rotationHours: rotation && typeof rotation.secs === "number" ? Math.round(rotation.secs / 3600) : null,
    ipv6: tunnel.generic ? tunnel.generic.enable_ipv6 === true : false,
    dns: {
      custom: dns.state === "custom",
      addresses: dns.custom_options && Array.isArray(dns.custom_options.addresses) ? dns.custom_options.addresses.slice() : [],
      blockers: blockerState
    },
    obfuscation: {
      mode: obfuscationMode(obf.selected_obfuscation),
      ports: {
        "udp2tcp": portOf(obf.udp2tcp),
        "shadowsocks": portOf(obf.shadowsocks),
        "wireguard-port": portOf(obf.wireguard_port),
        "lwo": portOf(obf.lwo)
      }
    },
    customLists: lists.map(function(l) {
      return { id: String(l.id || ""), name: String(l.name || ""), locations: (l.locations || []).map(function(x) { return locationOf({ only: { location: x } }) }) }
    }),
    apiMethods: methods
  }
}

function apiMethod(entry, builtIn) {
  return { id: String(entry.id || ""), name: String(entry.name || ""), enabled: entry.enabled === true, builtIn: builtIn }
}

// argv for `mullvad dns set default` that keeps every other blocker as-is:
// the CLI resets any blocker whose flag is omitted.
function dnsDefaultArgs(blockers, key, value) {
  var args = ["dns", "set", "default"]
  for (var i = 0; i < dnsBlockers.length; i++) {
    var k = dnsBlockers[i].key
    var on = k === key ? value : (blockers && blockers[k] === true)
    if (on) args.push(dnsBlockers[i].flag)
  }
  return args
}

// "se" / "se got" / "se got se-got-wg-001" as CLI arguments.
function locationArgs(sel) {
  if (!sel || !sel.country) return ["any"]
  var args = [sel.country]
  if (sel.city) args.push(sel.city)
  if (sel.city && sel.hostname) args.push(sel.hostname)
  return args
}

// Does a picker selection ({country, city?, hostname?} or null) say the same
// as the daemon's constraint? An empty picker never overrides a custom list
// or a custom relay - it cannot express them.
function sameLocation(constraint, sel) {
  var c = constraint || { kind: "any" }
  if (!sel || !sel.country) return c.kind === "any" || c.kind === "list"
  if (c.kind !== "country" && c.kind !== "city" && c.kind !== "host") return false
  return (c.country || "") === sel.country && (c.city || "") === (sel.city || "")
    && (c.hostname || "") === (sel.city && sel.hostname ? sel.hostname : "")
}

// The `mullvad relay set ...` commands needed before connecting to a picker
// selection - none when nothing changed, so a plain Connect never rewrites
// the user's constraints.
function connectPlan(view, sel, entrySel) {
  var v = view || {}
  var plan = []
  if (!sameLocation(v.exit, sel)) plan.push(["relay", "set", "location"].concat(locationArgs(sel)))
  if (v.multihop && !sameLocation(v.entry, entrySel)) plan.push(["relay", "set", "entry", "location"].concat(locationArgs(entrySel)))
  return plan
}

function describeLocation(world, loc, lists) {
  if (!loc || loc.kind === "any") return "Anywhere"
  if (loc.kind === "list") {
    var all = lists || []
    for (var i = 0; i < all.length; i++) if (all[i].id === loc.listId) return all[i].name
    return "Custom list"
  }
  var country = findCountry(world, loc.country)
  var countryName = country ? country.name : String(loc.country || "").toUpperCase()
  if (loc.kind === "country") return countryName
  var city = findCity(world, loc.country, loc.city)
  var cityName = city ? city.name : String(loc.city || "")
  if (loc.kind === "city") return cityName + ", " + countryName
  return loc.hostname + " · " + cityName
}

// ---------------------------------------------------------------- tunnel

// `mullvad status -j` -> flat view. Only the keys the UI reads; everything
// optional because the daemon omits whatever it does not know yet.
function tunnelView(raw) {
  var t = raw || {}
  var d = t.details || {}
  var loc = d.location || null
  var state = String(t.state || "unknown")
  var endpoint = d.endpoint || {}
  var features = Array.isArray(d.feature_indicators) ? d.feature_indicators.map(featureLabel) : []
  return {
    state: state,
    secured: state === "connected",
    blocking: (state === "disconnected" && d.locked_down === true) || state === "error"
      || state === "connecting" || state === "disconnecting",
    lockedDown: d.locked_down === true,
    location: loc ? {
      ipv4: loc.ipv4 || "", ipv6: loc.ipv6 || "",
      country: loc.country || "", city: loc.city || "",
      lat: typeof loc.latitude === "number" ? loc.latitude : null,
      lon: typeof loc.longitude === "number" ? loc.longitude : null,
      mullvadExit: loc.mullvad_exit_ip === true,
      hostname: loc.hostname || "", entryHostname: loc.entry_hostname || ""
    } : null,
    hostname: loc && loc.hostname ? loc.hostname : String(endpoint.hostname || ""),
    entryHostname: loc && loc.entry_hostname ? loc.entry_hostname : "",
    features: features,
    error: state === "error" ? errorText(d) : ""
  }
}

function featureLabel(f) {
  var raw = typeof f === "string" ? f : (f && typeof f === "object" ? Object.keys(f)[0] || "" : String(f))
  var known = {
    QuantumResistance: "Quantum-resistant", Multihop: "Multihop", Daita: "DAITA",
    DaitaMultihop: "DAITA multihop", Udp2Tcp: "UDP-over-TCP", Shadowsocks: "Shadowsocks",
    Quic: "QUIC", Lwo: "LWO", LanSharing: "LAN sharing", DnsContentBlockers: "DNS blocking",
    CustomDns: "Custom DNS", ServerIpOverride: "IP override", CustomMtu: "Custom MTU",
    LockdownMode: "Lockdown", SplitTunneling: "Split tunneling", Port: "Custom port"
  }
  return known[raw] || raw.replace(/([a-z])([A-Z])/g, "$1 $2")
}

function errorText(details) {
  var cause = details && details.cause !== undefined ? details.cause : details
  if (typeof cause === "string") return humanize(cause)
  if (cause && typeof cause === "object") {
    var k = Object.keys(cause)[0]
    if (k === "reason" || k === "Reason") return humanize(String(cause[k]))
    var inner = cause[k]
    return humanize(k) + (inner && typeof inner !== "object" ? ": " + inner : "")
  }
  return "Tunnel error"
}

function humanize(s) {
  var t = String(s).replace(/_/g, " ").replace(/([a-z])([A-Z])/g, "$1 $2").toLowerCase()
  return t.charAt(0).toUpperCase() + t.slice(1)
}

// ---------------------------------------------------------------- CLI text

function field(text, label) {
  var re = new RegExp("^\\s*" + label + "\\s*:\\s*(.*)$", "mi")
  var m = re.exec(String(text || ""))
  return m ? m[1].trim() : ""
}

// `mullvad account get -v`. The number stays in memory only; the UI masks it.
function parseAccount(text) {
  var t = String(text || "")
  if (!/Mullvad account\s*:/i.test(t)) return { loggedIn: false }
  return {
    loggedIn: true,
    number: field(t, "Mullvad account").replace(/\s+/g, ""),
    expiry: field(t, "Expires at"),
    deviceName: field(t, "Device name"),
    deviceCreated: field(t, "Device created")
  }
}

// Account state after `mullvad account get -v` exits. Only a successful read
// can log out or change the expiry: a failed one (daemon down, API
// unreachable) keeps what we knew, though a printed number still proves we
// are logged in (the CLI prints it before fetching the expiry).
function nextAccount(prev, ok, text) {
  var next = parseAccount(text)
  return ok || (next.loggedIn && next.number !== prev.number) ? next : prev
}

// `mullvad account list-devices -v` -> [{name, id, created}]
function parseDevices(text) {
  var out = []
  var blocks = String(text || "").split(/\n\s*\n/)
  for (var i = 0; i < blocks.length; i++) {
    var name = field(blocks[i], "Name")
    if (!name) continue
    out.push({ name: name, id: field(blocks[i], "Id"), created: field(blocks[i], "Created") })
  }
  return out
}

function parseVersion(text) {
  var t = String(text || "")
  return {
    current: field(t, "Current version"),
    supported: !/^false$/i.test(field(t, "Is supported")),
    upgrade: field(t, "Suggested upgrade")
  }
}

// `mullvad split-tunnel list`: "Excluded PIDs:" then one PID per line.
function parseSplitPids(text) {
  var out = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = /^\s*(\d+)\s*$/.exec(lines[i])
    if (m) out.push(Number(m[1]))
  }
  return out
}

function maskAccount(number) {
  var n = String(number || "").replace(/\s+/g, "")
  if (n.length < 4) return n ? "••••" : ""
  return "•••• •••• •••• " + n.slice(-4)
}

function groupAccount(number) {
  return String(number || "").replace(/\s+/g, "").replace(/(\d{4})(?=\d)/g, "$1 ")
}

// Days until an expiry like "2027-05-01 07:03:52 +02:00". NaN if unparseable.
function daysLeft(expiry, nowMs) {
  var m = /^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})\s*([+-]\d{2}:?\d{2}|Z|UTC)?/.exec(String(expiry || "").trim())
  if (!m) return NaN
  var zone = m[3] && m[3] !== "UTC" ? m[3] : "Z"
  if (/^[+-]\d{4}$/.test(zone)) zone = zone.slice(0, 3) + ":" + zone.slice(3)
  var at = Date.parse(m[1] + "T" + m[2] + zone)
  if (isNaN(at)) return NaN
  return Math.floor((at - (nowMs === undefined ? Date.now() : nowMs)) / 86400000)
}

// ---------------------------------------------------------------- geo

var DEG = Math.PI / 180

function wrapLon(lon) {
  var x = ((lon + 180) % 360 + 360) % 360 - 180
  return x === -180 ? 180 : x
}

function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

// Signed shortest rotation from one longitude to another, in (-180, 180].
function lonDelta(from, to) {
  var d = wrapLon(to - from)
  return d === -180 ? 180 : d
}

// Orthographic projection around (centreLat, centreLon). Returns unit-disc
// x (right) / y (up) and depth (> 0 on the visible hemisphere).
function project(lat, lon, centreLat, centreLon) {
  var p = lat * DEG, l = (lon - centreLon) * DEG, c = centreLat * DEG
  var cosP = Math.cos(p)
  return {
    x: cosP * Math.sin(l),
    y: Math.cos(c) * Math.sin(p) - Math.sin(c) * cosP * Math.cos(l),
    depth: Math.sin(c) * Math.sin(p) + Math.cos(c) * cosP * Math.cos(l)
  }
}

// Inverse of project() for a point inside the unit disc; null outside it.
function unproject(x, y, centreLat, centreLon) {
  var rho2 = x * x + y * y
  if (rho2 > 1) return null
  var z = Math.sqrt(1 - rho2)
  var c = centreLat * DEG
  var lat = Math.asin(clamp(y * Math.cos(c) + z * Math.sin(c), -1, 1)) / DEG
  var lon = centreLon + Math.atan2(x, z * Math.cos(c) - y * Math.sin(c)) / DEG
  return { lat: lat, lon: wrapLon(lon) }
}

// Points along the great circle a -> b (inclusive), for route arcs.
function greatCircle(a, b, steps) {
  var n = Math.max(2, steps || 48)
  var p1 = a.lat * DEG, l1 = a.lon * DEG, p2 = b.lat * DEG, l2 = b.lon * DEG
  var v1 = [Math.cos(p1) * Math.cos(l1), Math.cos(p1) * Math.sin(l1), Math.sin(p1)]
  var v2 = [Math.cos(p2) * Math.cos(l2), Math.cos(p2) * Math.sin(l2), Math.sin(p2)]
  var dot = clamp(v1[0] * v2[0] + v1[1] * v2[1] + v1[2] * v2[2], -1, 1)
  var omega = Math.acos(dot)
  var out = []
  for (var i = 0; i <= n; i++) {
    var t = i / n
    var s1 = omega < 1e-6 ? 1 - t : Math.sin((1 - t) * omega) / Math.sin(omega)
    var s2 = omega < 1e-6 ? t : Math.sin(t * omega) / Math.sin(omega)
    var x = s1 * v1[0] + s2 * v2[0], y = s1 * v1[1] + s2 * v2[1], z = s1 * v1[2] + s2 * v2[2]
    out.push({ lat: Math.atan2(z, Math.sqrt(x * x + y * y)) / DEG, lon: Math.atan2(y, x) / DEG })
  }
  return out
}

// Great-circle distance in km.
function distanceKm(a, b) {
  var p1 = a.lat * DEG, p2 = b.lat * DEG
  var dp = p2 - p1, dl = (b.lon - a.lon) * DEG
  var h = Math.sin(dp / 2) * Math.sin(dp / 2) + Math.cos(p1) * Math.cos(p2) * Math.sin(dl / 2) * Math.sin(dl / 2)
  return 2 * 6371 * Math.asin(Math.min(1, Math.sqrt(h)))
}

// Ray-cast point-in-polygon over a flat [lon, lat, lon, lat, ...] ring.
function pointInRing(lon, lat, ring) {
  var inside = false
  for (var i = 0, j = ring.length - 2; i < ring.length; j = i, i += 2) {
    var xi = ring[i], yi = ring[i + 1], xj = ring[j], yj = ring[j + 1]
    if ((yi > lat) !== (yj > lat) && lon < (xj - xi) * (lat - yi) / (yj - yi) + xi) inside = !inside
  }
  return inside
}

function countryAt(shapes, lat, lon) {
  for (var i = 0; i < shapes.length; i++) {
    var rings = shapes[i].r
    for (var k = 0; k < rings.length; k++) if (pointInRing(lon, lat, rings[k])) return shapes[i]
  }
  return null
}

// Bounding box of a country's largest ring, widened to include every Mullvad
// city in it - so zooming to New Zealand frames Auckland, not just the South
// Island, and France stays France rather than France + French Guiana.
function focusBox(shape, cities) {
  var box = null
  if (shape && shape.r && shape.r.length) {
    var best = shape.r[0]
    for (var i = 1; i < shape.r.length; i++) if (shape.r[i].length > best.length) best = shape.r[i]
    box = { w: 180, s: 90, e: -180, n: -90 }
    for (var k = 0; k < best.length; k += 2) {
      box.w = Math.min(box.w, best[k]); box.e = Math.max(box.e, best[k])
      box.s = Math.min(box.s, best[k + 1]); box.n = Math.max(box.n, best[k + 1])
    }
  }
  var list = cities || []
  for (var c = 0; c < list.length; c++) {
    if (!isFinite(list[c].lat) || !isFinite(list[c].lon)) continue
    if (!box) box = { w: list[c].lon, s: list[c].lat, e: list[c].lon, n: list[c].lat }
    box.w = Math.min(box.w, list[c].lon); box.e = Math.max(box.e, list[c].lon)
    box.s = Math.min(box.s, list[c].lat); box.n = Math.max(box.n, list[c].lat)
  }
  if (!box) return null
  return { lat: (box.s + box.n) / 2, lon: (box.w + box.e) / 2, spanLat: box.n - box.s, spanLon: box.e - box.w }
}

// Globe scale (1 = whole disc fits) that makes a box of the given angular
// span fill about `fill` of the view. Orthographic: a span of d degrees near
// the centre covers sin(d/2) of the radius.
function scaleForSpan(spanLat, spanLon, centreLat, fill, maxScale) {
  var lonSpan = spanLon * Math.cos(clamp(centreLat, -80, 80) * DEG)
  var span = Math.max(spanLat, lonSpan, 1.5)
  var half = Math.sin(Math.min(90, span / 2) * DEG)
  return clamp((fill || 0.7) / half, 1, maxScale || 40)
}
