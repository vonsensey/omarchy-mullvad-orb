import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

// Mullvad Orb service: the one place that talks to the Mullvad daemon.
//
// Reads come from what the daemon already publishes world-readable:
//   /etc/mullvad-vpn/settings.json        every setting, rewritten on change
//   /var/cache/mullvad-vpn/relays.json    the relay list with coordinates
//   `mullvad status -j` (+ `status listen` as a change trigger)
// Writes go through the `mullvad` CLI, one command at a time. Nothing is
// persisted by this plugin: the account number only ever lives in memory.
Item {
  id: root

  property var shell: null
  property var manifest: null
  // Pushed by the bar widget (its shell.json entry); defaults when absent.
  property var settings: ({})

  readonly property string pluginId: "io.github.vonsensey.mullvad-orb"
  readonly property string settingsPath: "/etc/mullvad-vpn/settings.json"
  readonly property string relaysPath: "/var/cache/mullvad-vpn/relays.json"

  property bool checked: false
  property bool installed: false
  property bool daemonUp: false
  property var tunnel: Model.tunnelView(null)
  property var prefs: Model.settingsView({})
  property var world: ({ countries: [], providers: [] })
  property int overrideCount: 0
  // Last location Mullvad saw you at while the tunnel was down. Memory only.
  property var home: null
  property var account: ({ loggedIn: false })
  property var devices: []
  property var version: ({})
  property var splitProcesses: []
  property string apiCurrent: ""
  property string lastError: ""
  property string lastNotice: ""
  property var _queue: []
  property var _job: null
  readonly property bool busy: runner.running || _queue.length > 0

  function setting(name, fallback) {
    var v = settings ? settings[name] : undefined
    return v === undefined || v === null || v === "" ? fallback : v
  }
  readonly property string notifyMode: String(setting("notifications", "Drops only"))
  readonly property int expiryWarnDays: Number(setting("expiryWarningDays", 7))
  readonly property bool privacy: String(setting("privacyMode", "Off")) === "On"
  // real, not int: an int turns NaN (expiry unknown) into 0 = "expires today".
  readonly property real daysLeft: account.loggedIn ? Model.daysLeft(account.expiry) : NaN
  readonly property bool expiringSoon: isFinite(daysLeft) && expiryWarnDays > 0 && daysLeft <= expiryWarnDays

  // ------------------------------------------------------------ commands

  // Queue `mullvad <args>`; done(ok, stdout, stderr) runs after it exits.
  // stdinText is written to the process (used so an account number never
  // appears in argv / `ps`).
  function run(args, done, stdinText) {
    if (!installed) return
    _queue = _queue.concat([{ args: args, done: done || null, stdin: stdinText || "" }])
    _next()
  }

  function _next() {
    if (runner.running || _queue.length === 0) return
    _job = _queue[0]
    _queue = _queue.slice(1)
    runner.stdinEnabled = _job.stdin !== ""
    runner.command = ["mullvad"].concat(_job.args)
    runner.running = true
  }

  function notice(text) {
    lastNotice = text
    noticeTimer.restart()
  }

  function fail(text) {
    lastError = String(text || "").replace(/^Error:\s*/i, "").trim().split("\n")[0]
    errorTimer.restart()
  }

  // Commands from this UI often make the daemon reconnect (new server,
  // location, DAITA...). Drops inside this window are ours, not the network's.
  property real quietUntil: 0

  // Run and report: "ok" text on success, stderr on failure.
  function act(args, okText, after) {
    quietUntil = Date.now() + 10000
    run(args, function(ok, out, err) {
      if (ok && okText) root.notice(okText)
      if (!ok) root.fail(err || out || ("mullvad " + args.join(" ") + " failed"))
      if (after) after(ok, out, err)
    })
  }

  // ---- connection
  function connect() { act(["connect"]) }
  function disconnect() { act(["disconnect"]) }
  function reconnect() { act(["reconnect"], "Reconnecting to a new server") }
  function toggle() { tunnel.state === "disconnected" ? connect() : disconnect() }

  // Apply only the relay changes in `plan` (Model.connectPlan), then connect
  // - or re-route a live tunnel, which the daemon does on its own.
  function connectWith(plan) {
    for (var i = 0; i < plan.length; i++) act(plan[i])
    connect()
  }
  function connectToList(name) {
    act(["relay", "set", "custom-list", name])
    connect()
  }
  function setLocation(sel) { act(["relay", "set", "location"].concat(Model.locationArgs(sel))) }
  function setEntry(sel) { act(["relay", "set", "entry", "location"].concat(Model.locationArgs(sel))) }
  function setEntryList(name) { act(["relay", "set", "entry", "custom-list", name]) }
  function setMultihop(on) { act(["relay", "set", "multihop", on ? "on" : "off"]) }
  function setOwnership(v) { act(["relay", "set", "ownership", v]) }
  function setProviders(list) { act(["relay", "set", "provider"].concat(list && list.length ? list : ["any"])) }
  function setIpVersion(v) { act(["relay", "set", "ip-version", v]) }
  function updateRelays() { act(["relay", "update"], "Relay list update requested") }

  // ---- settings
  function onOff(v) { return v ? "on" : "off" }
  function setLan(on) { act(["lan", "set", on ? "allow" : "block"]) }
  function setLockdown(on) { act(["lockdown-mode", "set", onOff(on)]) }
  function setAutoConnect(on) { act(["auto-connect", "set", onOff(on)]) }
  function setBeta(on) { act(["beta-program", "set", onOff(on)]) }
  function setDaita(on) { act(["tunnel", "set", "daita", onOff(on)]) }
  function setDaitaDirectOnly(on) { act(["tunnel", "set", "daita-direct-only", onOff(on)]) }
  function setQuantum(on) { act(["tunnel", "set", "quantum-resistant", onOff(on)]) }
  function setIpv6(on) { act(["tunnel", "set", "ipv6", onOff(on)]) }
  function setMtu(v) { act(["tunnel", "set", "mtu", v ? String(v) : "any"], v ? "MTU set to " + v : "MTU reset") }
  function setRotation(hours) { act(["tunnel", "set", "rotation-interval", hours ? String(hours) : "any"]) }
  function rotateKey() { act(["tunnel", "set", "rotate-key"], "WireGuard key rotated") }
  function setBlocker(key, on) { act(Model.dnsDefaultArgs(prefs.dns.blockers, key, on)) }
  function setCustomDns(on, addresses) {
    if (on) act(["dns", "set", "custom"].concat(addresses))
    else act(Model.dnsDefaultArgs(prefs.dns.blockers, "", false))
  }
  function setObfuscation(mode) { act(["anti-censorship", "set", "mode", mode]) }
  function setObfuscationPort(mode, port) {
    if (mode === "auto" || mode === "off") return
    act(["anti-censorship", "set", mode, "--port", String(port || "any")], "Port updated")
  }

  // ---- maintenance
  function importOverrides(path) { act(["import-settings", path], "Imported " + path) }
  function exportOverrides(path) { act(["export-settings", path], "Exported to " + path) }
  function clearOverrides() { act(["relay", "override", "clear-all"], "Server IP overrides cleared") }
  function resetSettings() { act(["reset-settings", "-y"], "Settings reset to defaults") }
  function factoryReset() { act(["factory-reset", "-y"], "Factory reset done") }

  // ---- custom lists
  function listNew(name) { act(["custom-list", "new", name], "Created list " + name) }
  function listDelete(name) { act(["custom-list", "delete", name], "Deleted list " + name) }
  function listRename(name, next) { act(["custom-list", "edit", "rename", name, next]) }
  function listAdd(name, sel) { act(["custom-list", "edit", "add", name].concat(Model.locationArgs(sel)), "Added to " + name) }
  function listRemove(name, loc) { act(["custom-list", "edit", "remove", name].concat(Model.locationArgs(loc))) }

  // ---- split tunnelling
  function splitRemove(pid) { act(["split-tunnel", "delete", String(pid)], "", refreshSplit) }
  function splitClear() { act(["split-tunnel", "clear"], "", refreshSplit) }
  function launchExcluded(commandLine) {
    var cmd = String(commandLine || "").trim()
    if (!cmd) return
    Quickshell.execDetached(["mullvad-exclude", "sh", "-c", cmd])
    notice("Launched outside the tunnel: " + cmd)
    splitRefreshTimer.restart()
  }

  // ---- API access (the CLI addresses methods by 1-based list position)
  function apiIndex(id) {
    for (var i = 0; i < prefs.apiMethods.length; i++) if (prefs.apiMethods[i].id === id) return String(i + 1)
    return ""
  }
  function apiSetEnabled(id, on) { act(["api-access", on ? "enable" : "disable", apiIndex(id)], "", refreshApi) }
  function apiUse(id) { act(["api-access", "use", apiIndex(id)], "", refreshApi) }
  function apiTest(id, name) {
    notice("Testing " + name + "…")
    run(["api-access", "test", apiIndex(id)], function(ok, out, err) {
      if (ok) root.notice(name + ": API reachable")
      else root.fail(name + ": " + (err || out || "unreachable"))
    })
  }

  // ---- account
  function login(number) {
    var n = String(number || "").replace(/\s+/g, "")
    if (!/^\d{16}$/.test(n)) { fail("An account number is 16 digits"); return }
    run(["account", "login"], function(ok, out, err) {
      if (ok) { root.notice("Logged in"); root.refreshAccount() }
      else root.fail(err || out)
    }, n)
  }
  function logout() { act(["account", "logout"], "Logged out", refreshAccount) }
  function createAccount() { act(["account", "create"], "New account created", refreshAccount) }
  function revokeDevice(id) { act(["account", "revoke-device", id], "Device revoked", refreshDevices) }
  // The account number is the login credential: it goes to wl-copy on stdin
  // (never argv, which any local process can read) and is marked sensitive
  // so Omarchy's clipboard history does not store it.
  function copyAccount() {
    if (!account.number || clipProc.running) return
    clipProc.running = true
  }
  function openAccountPage() { Quickshell.execDetached(["omarchy-launch-browser", "https://mullvad.net/account"]) }

  // ------------------------------------------------------------ reads

  function refreshStatus() {
    if (installed && !statusProc.running) statusProc.running = true
  }

  function refreshAccount() {
    run(["account", "get", "-v"], function(ok, out) {
      root.account = Model.nextAccount(root.account, ok, out)
      root.checkExpiry()
    })
  }
  function refreshDevices() {
    // Same as the account: a failed read keeps the list unless we logged out.
    run(["account", "list-devices", "-v"], function(ok, out) {
      root.devices = ok ? Model.parseDevices(out) : root.account.loggedIn ? root.devices : []
    })
  }
  function refreshVersion() {
    run(["version"], function(ok, out) { if (ok) root.version = Model.parseVersion(out) })
  }
  function refreshApi() {
    run(["api-access", "get"], function(ok, out) { if (ok) root.apiCurrent = String(out).trim() })
  }
  function refreshSplit() {
    run(["split-tunnel", "list"], function(ok, out) {
      var pids = ok ? Model.parseSplitPids(out) : []
      if (pids.length === 0) { root.splitProcesses = []; return }
      namesProc.command = ["ps", "-o", "pid=,comm=", "-p", pids.join(",")]
      namesProc.running = true
    })
  }
  // Everything the panel shows beyond live status; called when it opens.
  function refreshAll() {
    refreshStatus()
    settingsFile.reload()
    refreshAccount()
    refreshDevices()
    refreshVersion()
    refreshApi()
    refreshSplit()
  }

  // ------------------------------------------------------------ state

  function applyStatus(text) {
    var raw = null
    try { raw = JSON.parse(text) } catch (e) { return }
    var prev = tunnel.state
    tunnel = Model.tunnelView(raw)
    daemonUp = true
    var loc = tunnel.location
    if (tunnel.state === "disconnected" && loc && !loc.mullvadExit && loc.lat !== null)
      home = { lat: loc.lat, lon: loc.lon, city: loc.city, country: loc.country }
    announce(prev, tunnel.state)
  }

  function exitCity() {
    var relay = Model.findRelay(world, tunnel.hostname)
    return relay ? Model.findCity(world, relay.country, relay.city) : null
  }

  function announce(prev, next) {
    if (prev === next || prev === "unknown" || notifyMode === "Off") return
    if (next === "connected") {
      if (notifyMode !== "Drops and connects") return
      var city = exitCity()
      notify("normal", "Mullvad connected", city ? city.name + ", " + city.countryName : tunnel.hostname)
    } else if (next === "error") {
      notify("critical", "Mullvad: tunnel error", tunnel.error + (tunnel.blocking ? " - traffic is blocked" : ""))
    } else if (next === "disconnected" && notifyMode === "Drops and connects" && Date.now() >= quietUntil) {
      // A plain disconnect is deliberate (CLI, keybind, the app); only
      // reported when connects are reported too.
      notify("normal", "Mullvad disconnected", "Traffic is no longer going through the VPN")
    } else if (prev === "connected" && next === "connecting" && Date.now() >= quietUntil) {
      // A real drop: the daemon lost the tunnel and is re-establishing it.
      notify("normal", "Mullvad reconnecting", "The tunnel dropped; traffic is blocked until it is back")
    }
  }

  // The mole ships as a PNG in the plugin: an icon-theme name would render
  // as a missing-icon placeholder on themes that lack it.
  readonly property string iconPath: Qt.resolvedUrl("assets/mole.png").toString().replace(/^file:\/\//, "")
  function notify(urgency, title, body) {
    Quickshell.execDetached(["notify-send", "-a", "Mullvad Orb", "-u", urgency, "-i", iconPath, title, body])
  }

  property string _expiryNotified: ""
  function checkExpiry() {
    if (!expiringSoon || notifyMode === "Off") return
    var today = new Date().toDateString()
    if (_expiryNotified === today) return
    _expiryNotified = today
    notify(daysLeft <= 1 ? "critical" : "normal", "Mullvad account expires " + (daysLeft <= 0 ? "today" : "in " + daysLeft + " days"),
      "Add time at mullvad.net/account")
  }

  // ------------------------------------------------------------ processes

  Process {
    id: runner
    stdout: StdioCollector { id: runnerOut; waitForEnd: true }
    stderr: StdioCollector { id: runnerErr; waitForEnd: true }
    onStarted: {
      if (root._job && root._job.stdin) {
        write(root._job.stdin + "\n")
        stdinEnabled = false
      }
    }
    onExited: function(exitCode) {
      var job = root._job
      root._job = null
      if (job && job.done) job.done(exitCode === 0, String(runnerOut.text || ""), String(runnerErr.text || ""))
      settingsFile.reload()
      Qt.callLater(root._next)
    }
  }

  Process {
    id: clipProc
    command: ["wl-copy", "--sensitive"]
    stdinEnabled: true
    onStarted: {
      write(root.account.number)
      stdinEnabled = false
    }
    onExited: function(exitCode) {
      stdinEnabled = true
      if (exitCode === 0) root.notice("Account number copied")
      else root.fail("Could not copy the account number")
    }
  }

  Process {
    id: whichProc
    command: ["sh", "-c", "command -v mullvad"]
    onExited: function(exitCode) {
      root.checked = true
      root.installed = exitCode === 0
      if (!root.installed) {
        root.tunnel = Model.tunnelView({ state: "not-installed" })
        return
      }
      root.refreshStatus()
      listener.running = true
      root.refreshAccount()
    }
  }

  Process {
    id: statusProc
    command: ["mullvad", "status", "-j"]
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.applyStatus(String(statusOut.text || ""))
      else {
        root.daemonUp = false
        root.tunnel = Model.tunnelView({ state: "daemon-offline" })
      }
    }
  }

  // Each line means "something changed"; the authoritative state is re-read
  // with `status -j` rather than trusting the stream's format.
  Process {
    id: listener
    command: ["setpriv", "--pdeathsig", "TERM", "mullvad", "status", "-j", "listen"]
    stdout: SplitParser { onRead: statusDebounce.restart() }
    onExited: if (root.installed) listenerRestart.restart()
  }

  Process {
    id: namesProc
    stdout: StdioCollector { id: namesOut; waitForEnd: true }
    onExited: {
      var rows = []
      var lines = String(namesOut.text || "").split("\n")
      for (var i = 0; i < lines.length; i++) {
        var m = /^\s*(\d+)\s+(.+)$/.exec(lines[i])
        if (m) rows.push({ pid: Number(m[1]), name: m[2].trim() })
      }
      root.splitProcesses = rows
    }
  }

  Timer { id: statusDebounce; interval: 120; onTriggered: root.refreshStatus() }
  // Quick retry while the daemon is up (stream hiccup); slow when it is down.
  Timer { id: listenerRestart; interval: root.daemonUp ? 4000 : 30000; onTriggered: { root.refreshStatus(); listener.running = true } }
  Timer { id: splitRefreshTimer; interval: 1500; onTriggered: root.refreshSplit() }
  Timer { id: noticeTimer; interval: 4000; onTriggered: root.lastNotice = "" }
  Timer { id: errorTimer; interval: 8000; onTriggered: root.lastError = "" }
  // Safety net if the listener stalls, plus a slow account/expiry refresh.
  Timer { interval: 30000; running: root.installed; repeat: true; onTriggered: root.refreshStatus() }
  Timer { interval: 6 * 3600 * 1000; running: root.installed; repeat: true; onTriggered: root.refreshAccount() }

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var raw = JSON.parse(text())
        root.prefs = Model.settingsView(raw)
        root.overrideCount = Array.isArray(raw.relay_overrides) ? raw.relay_overrides.length : 0
      } catch (e) {}
    }
  }

  FileView {
    id: relaysFile
    path: root.relaysPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.world = Model.buildWorld(JSON.parse(text())) } catch (e) {}
    }
  }

  // Scriptable from keybinds: `omarchy-shell mullvad-orb toggle` etc.
  IpcHandler {
    target: "mullvad-orb"
    function connect(): void { root.connect() }
    function disconnect(): void { root.disconnect() }
    function toggle(): void { root.toggle() }
    function reconnect(): void { root.reconnect() }
    function status(): string { return root.tunnel.state }
  }

  Component.onCompleted: whichProc.running = true
}
