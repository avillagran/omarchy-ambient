# Omarchy integration

There are two ways omarchy-ambient shows up in Omarchy's menus and takes over
the idle screensaver.

## Natively: omacom/omarchy#16587

The draft pull request [omacom/omarchy#16587](https://github.com/omacom/omarchy/pull/16587) ([patch](omarchy-pr-16587.patch)) integrates the engine as an internal dependency, delivered with Omarchy's default packages and updates. The runtime package must be published to Omarchy's package repository before the integration merges. Users do not install an Ambient add-on.

- **Style > Background** has **Theme**, **Screensaver**, and **Amiga Demos**. Current quattro names the parent **Appearance**, with `style` as its existing alias. Theme opens the normal picker and stops the live background, including when the same image is selected again. The other two entries start their respective engine sources.
- **Screensaver** preserves **Set Animated Text**, **Set From Image**, **Set Amiga Demos**, **Preview**, and **Restore Default**, in that order. The selected Amiga source is checked. Successful text/image/reset operations return to the stock text screensaver before previewing; cancelling preserves the selection.
- `omarchy-launch-screensaver` delegates live sources to the engine, with activity dismissal, cursor restoration, single-instance locking and session-lock handling. The stock text path remains available.
- The update migration adds the runtime and rendering dependencies, then removes only the previous compatibility menu rows and idle clone. Settings and demos remain in place.

There is no separate Live Background submenu or Ambient Install/Remove entry. The native menus use fixed product choices; the engine's source interface remains extensible internally.

The corrected menus and keyboard-driven Amiga Preview were checked on mbp-intel with the branch shell. Keyboard activity dismissed the preview; the installed shell, previous selection and stay-awake setting were restored afterwards.

## Today: `omarchy-ambient install`

On a release without that change, `omarchy-ambient install` gives the
same result from user files alone:

- the menu rows go into `~/.config/omarchy/extensions/omarchy-menu.jsonc`,
  between two marked lines, under Style (Omarchy 4.0) or Appearance (later);
- Omarchy's idle service runs `omarchy-launch-screensaver` through
  `bash -lc`, where `~/.local/bin` comes after `/usr/bin`, so no user copy of
  the launcher is ever found. The idle service is cloned into
  `~/.config/omarchy/plugins/omarchy-ambient.idle` and calls a launcher that
  hands live screensavers over and runs Omarchy's own otherwise.

Each part is skipped when Omarchy does it natively, and
`omarchy-ambient remove` puts everything back.
