<p align="center"><img src="assets/mole.png" width="88" alt="The Mullvad Orb mole"></p>

# Mullvad Orb

Mullvad VPN for Omarchy, on a globe you can spin. Pick a server by clicking a
dot or searching country, city and server. The orb flies there, zooms into the
country, fans out its servers, and draws your tunnel once you connect. Nearly
every Mullvad setting is in the same panel (the few left out are listed
below), and everything takes its colors from your Omarchy theme.

![Mullvad Orb connected to New York through a Stockholm entry server, Tokyo Night theme](preview.png)

> Unofficial. Not affiliated with or endorsed by Mullvad VPN AB. "Mullvad" is
> their trademark. This plugin is a front end: it drives Mullvad's own `mullvad`
> CLI and daemon, which you install separately (see [Setup](#setup)).

## What you get

**The orb**
- Every Mullvad city as a dot, sized by server count. Countries with servers
  are shaded, and the selected country lights up in your accent color.
- Click a dot to select its country and city. Click a country to select it.
  Double-click a city to connect.
- Choosing a country flies and zooms to it with its cities labelled. Choosing
  a city zooms in further and fans out every server around it, so you can
  pick a single one.
- While connected, a pulsing marker sits on the exit city. With multihop, a
  lifted arc runs from the entry server to the exit server. Without multihop,
  it starts at your own location, when Mullvad has seen it since the shell
  started and privacy mode is off.
- Hovering a city shows its server count (and its distance from you, when
  your location is known); hovering a server shows owned/rented, provider,
  DAITA, QUIC and LWO.
- Drag to spin, scroll to zoom. Cities your filters (ownership, providers,
  DAITA, QUIC/LWO) leave without servers are dimmed on the globe, the pickers
  count only matching servers, and the Server picker marks filtered-out ones.

**Connect tab:** live status (server, entry server, IP, active features),
searchable Country, City and Server pickers kept in sync with the globe,
multihop with its own entry country and city, custom lists as one-click
destinations, Connect / Switch / Disconnect / New server.

**Settings tab:** auto-connect, lockdown mode (asks first), local network
sharing, DAITA and DAITA direct only, quantum-resistant tunnel, IPv6 in the
tunnel, all six DNS content blockers, custom DNS servers, anti-censorship
(automatic, WireGuard port, UDP-over-TCP, Shadowsocks, QUIC, LWO, with ports),
server filters by ownership and hosting provider.

**Advanced tab:** IP version, MTU, WireGuard key rotation interval and rotate
now, custom lists (create, add the location picked on the globe, remove, use as
multihop entry, delete), split tunneling (launch any command outside the VPN,
list and release excluded apps), API access methods (enable, test, use), server
IP override import/export/clear, app version and beta program, server list
update, reset settings and factory reset (both confirmed).

**Account tab:** account number (masked until you reveal it; copy), paid-until
date and days left, this device, all devices with revoke, add time and
vouchers (both open your mullvad.net account page), log out, and log in or
create an account when logged out. If this device was removed from the
account, the orb says so and offers *Log in again* with the same account.

**Bar widget:** a small mole (*mullvad* is Swedish for mole). Its nose lights up
in your accent color while the tunnel is up, and a country code, city or server
label sits next to it. It is dimmed when disconnected, blinks while connecting,
and turns urgent-red on errors, when lockdown is blocking traffic, or on the
account's last day.

![The bar mole: connected in Tokyo Night, connected in Ristretto, disconnected](docs/img/bar.png)

**Notifications** carry the same mole and fire on real drops (the tunnel falling
into reconnect), tunnel errors, account expiry, and this device being removed
from your account. With *Drops and connects*,
they also fire on connects and plain disconnects.

![A Mullvad Orb notification](docs/img/notification.png)

| Country zoom (Catppuccin Latte) | Connected (Ristretto) |
|---|---|
| ![Japan selected, light theme](docs/img/country-zoom-latte.png) | ![Connected, Ristretto theme](docs/img/connected-ristretto.png) |

| Settings | Advanced |
|---|---|
| ![Settings tab](docs/img/settings.png) | ![Advanced tab](docs/img/advanced.png) |

## Setup

Mullvad Orb controls the Mullvad app; it does not replace it. Mullvad needs a
one-time setup first, which is why the marketplace lists the plugin as
*Manual setup*. If Mullvad is already running on your machine, skip to step 3.

**Requirements:** Omarchy 4.0.4 or newer. Built and tested on Omarchy 4.0.4
(Quickshell 0.3.1, Qt 6.11) with `mullvad-vpn` 2026.4.

1. **Install Mullvad.** Omarchy menu → *Install* → *Package*, then pick
   `mullvad-vpn`. It comes from Arch's official `extra` repository. Mullvad
   itself only supports Ubuntu, Debian and Fedora, and its
   [Linux guide](https://mullvad.net/en/help/install-mullvad-app-linux#arch-linux)
   says the Arch package is maintained by Arch, not by Mullvad.
2. **Start the Mullvad daemon.** The package does not start `mullvad-daemon`
   on its own. Right after installing, it prints the one command that enables
   the daemon now and at every boot; run it in a terminal.
3. **Install the plugin:**

   ```bash
   omarchy plugin add https://github.com/vonsensey/omarchy-mullvad-orb.git --enable
   ```

   The mole appears on the right of the bar.
4. **Log in.** Click the mole, open the *Account* tab and enter your 16-digit
   account number. The Mullvad desktop app works for this too.
5. **Connect.** Pick a country on the globe or in the *Connect* tab and press
   *Connect* (or `Enter`).

If step 1 or 2 is missing, the orb still opens and says which part is
missing.

Optional keybindings in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + V", "Mullvad Orb", "omarchy-shell shell toggle io.github.vonsensey.mullvad-orb")
o.bind("SUPER + ALT + SHIFT + V", "Mullvad connect/disconnect", "omarchy-shell mullvad-orb toggle")
```

## Using it

| In the orb | |
|---|---|
| Drag / scroll | spin / zoom |
| Click a dot | select that city (click again to zoom in to its servers) |
| Double-click a dot | connect there |
| `Enter` | connect to the selection |
| `D` / `R` | disconnect / reconnect to a new server |
| Arrows, `+` `-`, `0` | spin, zoom, whole world |
| `1`-`4` | Connect, Settings, Advanced, Account |
| `Esc` | close a dropdown, then the orb |

| Bar | |
|---|---|
| Click | open the orb |
| Right click | connect / disconnect |
| Middle click | reconnect to a new server |

Scriptable over IPC:

```bash
omarchy-shell mullvad-orb connect | disconnect | toggle | reconnect | status
omarchy-shell shell summon io.github.vonsensey.mullvad-orb '{"tab":"settings"}'
omarchy-shell shell call io.github.vonsensey.mullvad-orb focusOn "se got"      # select + fly
```

### Widget settings

Set these in the bar settings, or with `omarchy bar set io.github.vonsensey.mullvad-orb <key> <value>`:

| Key | Values | Default |
|---|---|---|
| `barLabel` | Country, City, Server, None | Country |
| `notifications` | Drops only, Drops and connects, Off | Drops only |
| `expiryWarningDays` | 0-60 | 7 |
| `privacyMode` | Off, On | Off |

Privacy mode is for screen sharing. It hides IP addresses, your own location
on the globe, the account number, and the days-left counter (unless the
account is about to expire).

### Good to know

- **Multihop with DAITA:** when DAITA is on and *DAITA: direct only* is off,
  Mullvad's smart routing picks a DAITA entry server itself, and the entry you
  chose is ignored. Turn on *direct only* to use your own entry. (Verified
  against the daemon; the Connect tab says so when it applies.)
- **Settings changed elsewhere** (the Mullvad app, the CLI) show up in the orb
  immediately, because the daemon's own settings file is watched.
- **Reconnects started outside the orb** (the Mullvad app, `mullvad reconnect`
  in a terminal, a key rotation) look like a drop to the plugin and post a
  "reconnecting" notice.
- **After updating the plugin,** restart the shell (`omarchy-restart-shell`).
  The plugin is kept loaded, so its code only reloads on a restart.

## What it writes, and what it does not

- **It writes no files of its own.** Every change goes to the Mullvad daemon
  through the `mullvad` CLI, exactly as if you had typed it. The one file it
  can cause to be written is a server IP override export, at the path you
  type into *Advanced*.
- **Reads:** `/etc/mullvad-vpn/settings.json` and
  `/var/cache/mullvad-vpn/relays.json`. Both are world-readable and published
  by the daemon.
- **Runs:**
  - `setpriv --pdeathsig TERM mullvad status -j listen`: one small watcher,
    tied to the shell's lifetime.
  - `sh -c "command -v mullvad"`: once at startup, to see whether Mullvad is
    installed.
  - `mullvad` commands when you act.
  - `ps`, to name split-tunnel apps.
  - `notify-send`.
  - `wl-copy --sensitive`, when you copy the account number.
  - `omarchy-launch-browser`, for *Add time* and vouchers.
  - `mullvad-exclude sh -c <your command>`, when you launch an app outside the
    tunnel. It runs exactly what you typed.
- **Your account number** stays in memory and is masked on screen. It is
  never put on a command line, where other local programs could read it:
  login and copy both hand it over on stdin, and the copy is marked sensitive
  so Omarchy's clipboard history skips it. Vouchers are redeemed on
  mullvad.net, because the `mullvad` CLI only accepts them as an argument.
  (Login, *Log in again* and create account were not live-tested: the test
  machine stayed logged in.)
- **No network access of its own.** The daemon talks to Mullvad; the plugin
  only talks to the daemon. The only URL it opens is your mullvad.net account
  page, in your browser, when you click for it.
- **Not included on purpose:** `mullvad debug`, log level and log streaming,
  editing single relay IP overrides by hand (import, export and clear-all are
  in), custom WireGuard endpoints, and adding custom SOCKS5/Shadowsocks API
  proxies (existing methods can be enabled, tested and used).

## Memory

Measured on this machine by comparing the `omarchy-shell` RSS with the plugin
disabled and enabled, two rounds each:

- **Enabled, orb closed:** +1 to 8 MB (the service plus the parsed relay list).
- **Orb open:** about +70 MB, mostly the two globe canvases at 2× scale. The
  globe is only created while the orb is open.
- **After closing:** about +30 MB stays with the shell's allocator and JS heap,
  and is reused the next time it opens.
- **The status watcher** (`mullvad status -j listen`) takes about 7 MB.

## Remove

```bash
omarchy plugin remove io.github.vonsensey.mullvad-orb
```

Mullvad itself and all your Mullvad settings are left exactly as they are.

## Development

```bash
test/check.sh   # model tests (node), QML parse, manifest validation, no secrets in argv, assets
```

`Model.js` holds every parser and all the geometry and is tested under node.
On a machine with Mullvad installed, it also checks that every Mullvad country
and city lands on the map.
Country outlines are Natural Earth 1:50m (public domain), simplified by
`tools/build-countries.sh`. The globe technique, an orthographic projection
on a QML Canvas, was inspired by [Radio Atlas](https://github.com/AksharP5/omarchy-radio-atlas).
This implementation is written from scratch.

## License

MIT. The mole mark (`docs/img/mole.svg`, `assets/mole.png`,
`tools/mole-notify.svg`) is original artwork under the same license.
