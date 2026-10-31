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
- `ambient-background-selector.lua` binds the active category to a shortcut.

## Requirements

The scenes need an `omarchy-ttfx-layer` build with `--neon-scene`, and the live
previews need its `ttfx-ambient-preview` mode. Each source runs
`$OMARCHY_AMBIENT_DATA/bin/omarchy-ttfx-layer`, so link that binary into the data
directory of every source you install.

## Install

1. Copy `background_selector.py`, `catalog.json` and `live-preview/run-preview.py` to
   `~/.local/share/omarchy-ambient/selector/`, next to the
   `ttfx-ambient-preview` binary.
2. Copy `sources/*` to `~/.config/omarchy/ambient/sources/`.
3. Copy `live-preview/` to `~/.config/omarchy/plugins/avillagran.ambient-selector/`.
4. Point the Style > Background menu entries at `background_selector.py` with the
   argument `theme`, `screensaver`, `amiga` or `random`.

Posters are read from `~/.cache/omarchy/ambient-selector/`, using the `poster` name
in `catalog.json`.

## Notes

- Ambient pauses a source on battery by default. To keep one running, set
  `on_battery=run` in `~/.config/omarchy/ambient/<id>.conf`.
- The Omarchy shell caches QML types by directory. After changing the plugin, load it
  from a new directory and update `entryPoints` in `manifest.json`.
- Closing the panel ends only its own preview process group, so the active background
  keeps running.

## Tests

    python3 contrib/background-selector/test_selector.py
