// node --test test/  (dev-only; the plugin itself needs no node)
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync, existsSync } from "node:fs"
import vm from "node:vm"

const root = new URL("..", import.meta.url).pathname
// Load the QML JS library into this realm, exporting its top-level names.
const src = readFileSync(root + "Model.js", "utf8").replace(/^\.pragma library/m, "")
const names = [...src.matchAll(/^(?:function|var) (\w+)/gm)].map(m => m[1])
const M = vm.runInThisContext(`(function(){${src}\nreturn {${names.join(",")}}})`)()
const shapes = JSON.parse(readFileSync(root + "assets/countries.json", "utf8"))
const plain = v => JSON.parse(JSON.stringify(v))

const fakeRelays = {
  locations: {
    "se-got": { city: "Gothenburg", country: "Sweden", latitude: 57.7, longitude: 11.97 },
    "se-sto": { city: "Stockholm", country: "Sweden", latitude: 59.33, longitude: 18.06 },
    "de-ber": { city: "Berlin", country: "Germany", latitude: 52.52, longitude: 13.4 }
  },
  wireguard: { relays: [
    { hostname: "se-sto-wg-002", location: "se-sto", active: true, owned: true, provider: "31173", daita: true, features: { quic: {}, lwo: null } },
    { hostname: "se-sto-wg-001", location: "se-sto", active: true, owned: false, provider: "M247", daita: false, features: { quic: null, lwo: {} } },
    { hostname: "se-got-wg-001", location: "se-got", active: false, owned: true, provider: "31173", daita: true },
    { hostname: "se-got-wg-002", location: "se-got", active: true, owned: true, provider: "31173", daita: false },
    { hostname: "de-ber-wg-001", location: "de-ber", active: true, owned: false, provider: "DataPacket", daita: true, include_in_country: false },
    { hostname: "xx-bad-wg-001", location: "nowhere", active: true }
  ] }
}

test("buildWorld groups, sorts and drops inactive/unknown relays", () => {
  const w = M.buildWorld(fakeRelays)
  assert.deepEqual(w.countries.map(c => c.code), ["de", "se"])
  const se = w.countries[1]
  assert.deepEqual(se.cities.map(c => c.name), ["Gothenburg", "Stockholm"])
  assert.equal(se.relayCount, 3)
  assert.deepEqual(se.cities[1].relays.map(r => r.hostname), ["se-sto-wg-001", "se-sto-wg-002"])
  assert.equal(M.findRelay(w, "se-got-wg-001"), null, "inactive relay must be dropped")
  const r = M.findRelay(w, "se-sto-wg-002")
  assert.equal(r.quic, true); assert.equal(r.lwo, false); assert.equal(r.owned, true)
  assert.equal(M.findRelay(w, "de-ber-wg-001").includeInCountry, false)
  assert.deepEqual(plain(w.providers), ["31173", "DataPacket", "M247"])
})

test("relay filters mirror daemon constraints", () => {
  const w = M.buildWorld(fakeRelays)
  const sto = M.findCity(w, "se", "sto")
  const names = f => M.matchingRelays(sto, f).map(r => r.hostname)
  assert.deepEqual(names({ ownership: "owned" }), ["se-sto-wg-002"])
  assert.deepEqual(names({ ownership: "rented" }), ["se-sto-wg-001"])
  assert.deepEqual(names({ providers: ["M247"] }), ["se-sto-wg-001"])
  assert.deepEqual(names({ daita: true }), ["se-sto-wg-002"])
  assert.deepEqual(names({ obfuscation: "lwo" }), ["se-sto-wg-001"])
  // DAITA needs a DAITA exit only when it may not multihop automatically.
  assert.equal(M.relayFilter({ daita: true, daitaDirectOnly: false }, "exit").daita, false)
  assert.equal(M.relayFilter({ daita: true, daitaDirectOnly: true }, "exit").daita, true)
  assert.equal(M.relayFilter({ daita: true, multihop: true }, "entry").daita, true)
  assert.equal(M.relayFilter({ daita: true, multihop: true }, "exit").daita, false)
  // With multihop the obfuscation applies to the entry hop, not the exit.
  assert.equal(M.relayFilter({ multihop: true, obfuscation: { mode: "quic" } }, "exit").obfuscation, "")
  assert.equal(M.relayFilter({ multihop: true, obfuscation: { mode: "quic" } }, "entry").obfuscation, "quic")
})

// Shapes observed from mullvad-vpn 2026.4's settings.json (values synthetic).
const settings = {
  allow_lan: true, lockdown_mode: false, auto_connect: true, show_beta_releases: false,
  custom_lists: { custom_lists: [{ id: "L1", name: "Fast", locations: [{ country: "de" }, { city: ["se", "got"] }] }] },
  obfuscation_settings: { selected_obfuscation: "udp2_tcp", udp2tcp: { port: { only: 443 } }, shadowsocks: { port: "any" }, wireguard_port: { port: { only: 53 } } },
  relay_settings: { normal: {
    location: { only: { location: { hostname: ["se", "got", "se-got-wg-001"] } } },
    ownership: { only: "MullvadOwned" },
    providers: { only: { providers: ["31173", "DataPacket"] } },
    wireguard_constraints: { ip_version: { only: "v4" }, use_multihop: true, entry_location: { only: { custom_list: { list_id: "L1" } } } }
  } },
  tunnel_options: {
    dns_options: { state: "custom", default_options: { block_ads: true, block_malware: true }, custom_options: { addresses: ["9.9.9.9"] } },
    generic: { enable_ipv6: true },
    wireguard: { daita: { enabled: true, use_multihop_if_necessary: false }, mtu: 1380, quantum_resistant: "on", rotation_interval: { secs: 172800, nanos: 0 } }
  },
  api_access_methods: {
    direct: { id: "d", name: "Direct", enabled: true },
    mullvad_bridges: { id: "b", name: "Mullvad Bridges", enabled: false },
    custom: [{ id: "c", name: "My socks", enabled: true }]
  }
}

test("settingsView normalises every constraint shape", () => {
  const v = M.settingsView(settings)
  assert.deepEqual(plain(v.exit), { kind: "host", country: "se", city: "got", hostname: "se-got-wg-001" })
  assert.deepEqual(plain(v.entry), { kind: "list", listId: "L1" })
  assert.equal(v.multihop, true)
  assert.equal(v.ownership, "owned")
  assert.deepEqual(plain(v.providers), ["31173", "DataPacket"])
  assert.equal(v.ipVersion, "v4")
  assert.equal(v.daita, true); assert.equal(v.daitaDirectOnly, true)
  assert.equal(v.mtu, 1380); assert.equal(v.rotationHours, 48); assert.equal(v.ipv6, true)
  assert.equal(v.dns.custom, true); assert.deepEqual(plain(v.dns.addresses), ["9.9.9.9"])
  assert.equal(v.dns.blockers.block_ads, true); assert.equal(v.dns.blockers.block_trackers, false)
  assert.equal(v.obfuscation.mode, "udp2tcp")
  assert.equal(v.obfuscation.ports.udp2tcp, "443"); assert.equal(v.obfuscation.ports["wireguard-port"], "53")
  assert.equal(v.obfuscation.ports.lwo, "any")
  assert.deepEqual(v.customLists[0].locations.map(l => l.kind), ["country", "city"])
  assert.deepEqual(v.apiMethods.map(m => m.name + ":" + m.enabled + ":" + m.builtIn),
    ["Direct:true:true", "Mullvad Bridges:false:true", "My socks:true:false"])
  const empty = M.settingsView({})
  assert.equal(empty.exit.kind, "any"); assert.equal(empty.ownership, "any"); assert.equal(empty.obfuscation.mode, "auto")
  assert.equal(M.settingsView({ relay_settings: { custom_tunnel_endpoint: {} } }).customRelay, true)
  assert.equal(M.locationOf("any").kind, "any")
  assert.equal(M.locationOf({ only: { location: { city: ["se", "got"] } } }).city, "got")
})

test("obfuscation mode names map between file and CLI", () => {
  assert.equal(M.obfuscationMode("wireguard_port"), "wireguard-port")
  assert.equal(M.obfuscationMode("udp2_tcp"), "udp2tcp")
  assert.equal(M.obfuscationMode("quic"), "quic")
  assert.equal(M.obfuscationMode("off"), "off")
  assert.equal(M.obfuscationMode(undefined), "auto")
})

test("dns default args keep the other blockers (the CLI resets omitted ones)", () => {
  const blockers = { block_ads: true, block_malware: true }
  assert.deepEqual(plain(M.dnsDefaultArgs(blockers, "block_trackers", true)),
    ["dns", "set", "default", "--block-ads", "--block-trackers", "--block-malware"])
  assert.deepEqual(plain(M.dnsDefaultArgs(blockers, "block_ads", false)), ["dns", "set", "default", "--block-malware"])
  assert.deepEqual(plain(M.dnsDefaultArgs(blockers, "", false)), ["dns", "set", "default", "--block-ads", "--block-malware"])
})

test("location args and descriptions", () => {
  const w = M.buildWorld(fakeRelays)
  assert.deepEqual(plain(M.locationArgs({ country: "se", city: "got", hostname: "se-got-wg-002" })), ["se", "got", "se-got-wg-002"])
  assert.deepEqual(plain(M.locationArgs({ country: "se", hostname: "x" })), ["se"])
  assert.deepEqual(plain(M.locationArgs(null)), ["any"])
  assert.equal(M.describeLocation(w, { kind: "city", country: "se", city: "sto" }), "Stockholm, Sweden")
  assert.equal(M.describeLocation(w, { kind: "country", country: "de" }), "Germany")
  assert.equal(M.describeLocation(w, { kind: "list", listId: "L1" }, [{ id: "L1", name: "Fast" }]), "Fast")
  assert.equal(M.describeLocation(w, { kind: "any" }), "Anywhere")
})

test("tunnelView covers every state", () => {
  const off = M.tunnelView({ state: "disconnected", details: { location: { ipv4: "192.0.2.1", country: "Nowhere", latitude: 10, longitude: 20, mullvad_exit_ip: false }, locked_down: false } })
  assert.equal(off.secured, false); assert.equal(off.blocking, false); assert.equal(off.location.lat, 10)
  assert.equal(M.tunnelView({ state: "disconnected", details: { locked_down: true } }).blocking, true)
  const on = M.tunnelView({ state: "connected", details: {
    location: { hostname: "se-sto-wg-002", entry_hostname: "de-ber-wg-001", mullvad_exit_ip: true, latitude: 59.3, longitude: 18 },
    feature_indicators: ["QuantumResistance", "Multihop", "Daita", "SomethingNew"] } })
  assert.equal(on.secured, true); assert.equal(on.hostname, "se-sto-wg-002"); assert.equal(on.entryHostname, "de-ber-wg-001")
  assert.deepEqual(plain(on.features), ["Quantum-resistant", "Multihop", "DAITA", "Something New"])
  assert.equal(M.tunnelView({ state: "connecting", details: {} }).blocking, true)
  const err = M.tunnelView({ state: "error", details: { cause: { reason: "is_offline" }, block_failure: null } })
  assert.equal(err.error, "Is offline"); assert.equal(err.blocking, true)
  assert.equal(M.tunnelView({ state: "error", details: { cause: "tunnel_parameter_error" } }).error, "Tunnel parameter error")
  assert.equal(M.tunnelView(null).state, "unknown")
})

test("CLI text parsers (synthetic account data)", () => {
  const acct = M.parseAccount("Mullvad account:    1234567890123456\nExpires at:         2027-05-01 07:03:52 +02:00\nAccount id:  abc\nDevice name:        Brave Otter\nDevice created:     2026-05-09 20:06:39 UTC\n")
  assert.equal(acct.loggedIn, true); assert.equal(acct.number, "1234567890123456")
  assert.equal(acct.deviceName, "Brave Otter"); assert.equal(acct.expiry, "2027-05-01 07:03:52 +02:00")
  assert.equal(M.parseAccount("Not logged in on any account\n").loggedIn, false)
  const devices = M.parseDevices("Devices on the account:\n\nName      : Brave Otter\nId        : 11-22\nPublic key: x\nCreated   : 2026-02-13 18:57:15 +01:00\n\nName      : Calm Heron\nId        : 33-44\nCreated   : 2026-02-14\n")
  assert.deepEqual(devices.map(d => d.name + "/" + d.id), ["Brave Otter/11-22", "Calm Heron/33-44"])
  assert.deepEqual(plain(M.parseVersion("Current version       : 2026.4\nIs supported          : true\nSuggested upgrade     : 2026.5\n")),
    { current: "2026.4", supported: true, upgrade: "2026.5" })
  assert.equal(M.parseVersion("Current version: 1\nIs supported: false\n").supported, false)
  assert.deepEqual(plain(M.parseSplitPids("Excluded PIDs:\n  4242\n  17\n")), [4242, 17])
  assert.deepEqual(plain(M.parseSplitPids("Excluded PIDs:\n")), [])
  assert.equal(M.maskAccount("1234567890123456"), "•••• •••• •••• 3456")
  assert.equal(M.groupAccount("1234567890123456"), "1234 5678 9012 3456")
})

test("daysLeft handles offsets and garbage", () => {
  const now = Date.parse("2027-04-21T05:03:52Z")
  assert.equal(M.daysLeft("2027-05-01 07:03:52 +02:00", now), 10)
  assert.equal(M.daysLeft("2027-05-01 05:03:52 UTC", now), 10)
  assert.ok(Number.isNaN(M.daysLeft("soon", now)))
})

test("projection round-trips and hides the far side", () => {
  for (const [lat, lon, cl, cn] of [[57.7, 11.97, 50, 10], [-33.9, 151.2, -20, 140], [10, 179, 5, -175]]) {
    const p = M.project(lat, lon, cl, cn)
    assert.ok(p.depth > 0)
    const back = M.unproject(p.x, p.y, cl, cn)
    assert.ok(Math.abs(back.lat - lat) < 1e-6 && Math.abs(M.lonDelta(back.lon, lon)) < 1e-6, `${lat},${lon}`)
  }
  assert.ok(M.project(0, 180, 0, 0).depth < 0)
  const east = M.project(0, 10, 0, 0), north = M.project(10, 0, 0, 0)
  assert.ok(east.x > 0 && Math.abs(east.y) < 1e-9, "east is right")
  assert.ok(north.y > 0 && Math.abs(north.x) < 1e-9, "north is up")
  assert.equal(M.unproject(0.9, 0.9, 0, 0), null)
  assert.equal(M.lonDelta(170, -170), 20); assert.equal(M.lonDelta(-170, 170), -20)
  assert.equal(M.wrapLon(540), 180); assert.equal(M.wrapLon(-190), 170)
})

test("great circle ends at both points and distance is sane", () => {
  const a = { lat: 55.6, lon: 12.99 }, b = { lat: 40.71, lon: -74.0 }
  const pts = M.greatCircle(a, b, 32)
  assert.equal(pts.length, 33)
  assert.ok(Math.abs(pts[0].lat - a.lat) < 1e-6 && Math.abs(pts[32].lon - b.lon) < 1e-6)
  assert.ok(Math.max(...pts.map(p => p.lat)) > a.lat, "route bends north over the Atlantic")
  const km = M.distanceKm(a, b)
  assert.ok(km > 6100 && km < 6300, String(km))
})

test("hit testing and zoom framing", () => {
  const se = M.countryAt(shapes, 59.33, 18.06)
  assert.equal(se && se.c, "SE")
  assert.equal(M.countryAt(shapes, 0, -30), null, "mid-Atlantic is sea")
  const nz = shapes.find(s => s.c === "NZ")
  const box = M.focusBox(nz, [{ lat: -36.85, lon: 174.76 }])
  assert.ok(box.lat + box.spanLat / 2 >= -36.85, "Auckland inside the frame")
  const small = M.scaleForSpan(1, 1, 1.3, 0.7), large = M.scaleForSpan(40, 60, 50, 0.7)
  assert.ok(small > large && large >= 1)
  assert.equal(M.scaleForSpan(180, 360, 0, 0.7), 1)
})

// Data coverage against the real relay list when this machine has Mullvad.
const cache = "/var/cache/mullvad-vpn/relays.json"
test("every Mullvad country and city lands on the map", { skip: !existsSync(cache) && "no relay cache" }, () => {
  const w = M.buildWorld(JSON.parse(readFileSync(cache, "utf8")))
  assert.ok(w.countries.length > 30)
  for (const c of w.countries) {
    const shape = shapes.find(s => s.c === c.code.toUpperCase())
    assert.ok(shape, `no polygon for ${c.code} ${c.name}`)
    for (const city of c.cities) {
      const hit = M.countryAt([shape], city.lat, city.lon)
      const near = shape.r.some(r => { for (let i = 0; i < r.length; i += 2) if (Math.hypot(r[i] - city.lon, r[i + 1] - city.lat) < 1) return true; return false })
      assert.ok(hit || near, `${city.name} (${c.code}) is off its country`)
      const box = M.focusBox(shape, c.cities)
      assert.ok(Math.abs(city.lat - box.lat) <= box.spanLat / 2 + 1e-9, `${city.name} outside ${c.code} frame`)
    }
  }
})
