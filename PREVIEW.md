# How the screenshots were made

All images are real captures of the plugin running in `omarchy-shell` 4.0.4
against a live Mullvad 2026.4 daemon. They were taken with `grim` and cropped
to the panel. No mockups.

- `preview.png`, `docs/img/connected-ristretto.png`: a real multihop
  connection, Stockholm (se-sto-wg-2xx) entry to New York (us-nyc-wg-801)
  exit, with *DAITA: direct only* on so the chosen entry is used. Tokyo Night
  and Ristretto themes.
- `docs/img/country-zoom-latte.png`: Japan selected from the country dropdown,
  Catppuccin Latte.
- Privacy mode was on for every capture, which hides IPs and the "You"
  location. The days-left counter was painted out of the images taken before
  privacy mode also hid it. The Account tab is not pictured.

Recapture: enable the plugin, run
`omarchy bar set io.github.vonsensey.mullvad-orb privacyMode On`, then
`omarchy-shell shell summon io.github.vonsensey.mullvad-orb '{}'`,
`omarchy-shell shell call io.github.vonsensey.mullvad-orb focusOn "us nyc"`,
and `grim`.
