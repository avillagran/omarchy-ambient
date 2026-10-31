# Background selector example

A selector for Omarchy's Style > Background menu, built on Ambient. It offers four
entries: **Theme**, **Screensaver**, **Amiga Demos** and **Random**. Random picks one
category and one item per activation, with no timer. Applying always goes through
`omarchy-ambient`, so its lifecycle, visibility and battery rules stay in charge.

- `background_selector.py` lists the choices and applies them.
- `catalog.json` lists the ASCII scenes, with the non-TTFX ones first.
- `live-preview/` is an Omarchy shell plugin: a slice carousel with live ASCII
  previews and static posters for the slices next to the selected one.
- `sources/` holds one Ambient source per scene.
- `posters/` holds the still images for the carousel.
- `ambient-background-selector.lua` binds the active category to a shortcut.

The same carousel picks the screensaver: `background_selector.py saver` stores the
choice with `omarchy-ambient screensaver --set` instead of starting it.

## Install

The `install.sh` at the top of this repository installs all of this for the current
user. It downloads a release bundle, which `make-bundle.sh` builds from this directory
and an `omarchy-ttfx-layer` binary with `--neon-scene`.

## Notes

- Ambient pauses a source on battery by default. To keep one running, set
  `on_battery=run` in `~/.config/omarchy/ambient/<id>.conf`.
- The Omarchy shell caches QML types by directory. After changing the plugin, load it
  from a new directory and update `entryPoints` in `manifest.json`.
- Closing the panel ends only its own preview process group, so the active background
  keeps running.

## Tests

    python3 contrib/background-selector/test_selector.py
