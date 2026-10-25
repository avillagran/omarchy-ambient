# Omarchy integration

There are two ways omarchy-ambient shows up in Omarchy's menus and takes over
the idle screensaver.

## Natively: omacom/omarchy#16587

The draft pull request [omacom/omarchy#16587](https://github.com/omacom/omarchy/pull/16587)
([patch](omarchy-pr-16587.patch)) makes Omarchy offer omarchy-ambient by
itself when it is installed, and changes nothing when it isn't:

- **Install › Style › Ambient** runs `omarchy-install-ambient`, which
  installs the `omarchy-ambient` package (`packaging/arch/PKGBUILD`), and
  **Remove › Ambient** runs `omarchy-remove-ambient`, which removes it with
  its settings and downloads.
- **Appearance › Live Background** lists the background sources through a
  `background-sources` provider (`omarchy-ambient list background`), plus
  None. Picking one runs `omarchy-ambient start <id>`.
- **Appearance › Branding › Screensaver** lists the screensaver sources
  through a `screensaver-sources` provider, next to Text Effects (the stock
  screensaver) and Preview. Picking one runs
  `omarchy-ambient screensaver --set <id>`.
- `omarchy-launch-screensaver` hands over to `omarchy-ambient screensaver`
  when a live screensaver is chosen; `force text` still forces the stock one.

Provider rows are `name, id, current id, description, icon`, tab-separated:
the shape `omarchy-ambient list` prints.

The idle service needs no change. It keys the end of the screensaver on
windows of class `org.omarchy.screensaver`, which a layer doesn't have, but it
cancels the cycle on any activity once its three-second launch grace is over,
and the activity that dismisses the screensaver is exactly that.

It was tried on a 2015 MacBook Pro with Omarchy 4.0.6 by running the shell
from the branch: both menus, choosing with the keyboard, Preview, and the
real idle timeout starting the Amiga screensaver through the new launcher.

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
