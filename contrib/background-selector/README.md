# Background selector example

A selector for Omarchy's Appearance > Background menu, built on Ambient. It offers four
entries: **Theme**, **Screensaver**, **Amiga Demos** and **Random**. Random picks one
category and one item per activation, with no timer. Applying always goes through
`omarchy-ambient`, so its lifecycle, visibility and battery rules stay in charge.

- `background_selector.py` lists the choices and applies them.
- `catalog.json` lists the ASCII scenes, with the non-TTFX ones first. The single
  TTFx effects are choices of the `ttfx` source, `fx:<effect>`.
- `live-preview/` is an Omarchy shell plugin: a slice carousel with live ASCII
  previews and static posters for the slices next to the selected one. It calls
  the selector through its `bin/select`, which the install writes.
- `run-preview.py` owns the preview renderer's process group.
- The scenes are built-in sources of the engine, in `sources/` at the top of this
  repository.
- `posters/` holds the still images for the carousel.
- `ambient-background-selector.lua` binds Super+Ctrl+Space to the selector for the active
  category. The installer puts it in `~/.config/hypr` and loads it from `hyprland.lua`.

`omarchy-ambient-select background` starts the scene you pick. `omarchy-ambient-select
screensaver` opens the same carousel and stores the choice with `omarchy-ambient
screensaver --set`. `theme`, `amiga`, `random` and `current` also work, `saver` is an
alias of `screensaver`, and `omarchy-ambient-background-select` is an alias of the command.

## Install

`make install` at the top of this repository installs the selector with the engine:
`omarchy-ambient-select` in `bin`, the selector in `lib/omarchy-ambient/selector`, the
plugin and the posters in `share/omarchy-ambient`. That is how the package and Omarchy
ship it; `omarchy-ambient selector enable` links the plugin for the user.

The `install.sh` at the top of this repository installs all of this for the current
user instead, where the system does not ship it. It downloads a release bundle, which `make-bundle.sh` builds from this directory
and an `omarchy-ttfx-layer` binary with `--neon-scene`.

## Build a bundle

Build on each target architecture with an `omarchy-ttfx-layer` renderer built with
`cargo build --release --frozen --no-default-features`. The bundle also builds the
Ambient layer and dismiss helper, so it needs a C compiler, Make, `pkg-config`,
Wayland development files and `wayland-protocols`.

The GPU preview additionally needs a C++17 compiler, the Qt 6 Quick, QML and GUI
development files, and Qt Shader Tools (`qt6-shadertools` on Arch). The builder
looks for `/usr/lib/qt6/moc`, `/usr/lib/qt6/rcc` and `/usr/lib/qt6/bin/qsb`.
`qsb` bakes the vertex and fragment shaders; `rcc` embeds both in
`libambientcells.so`, so the installed plugin needs no shader compiler.

From the repository root:

```sh
contrib/background-selector/make-bundle.sh /path/to/omarchy-ttfx-layer VERSION out/
tar -tzf "out/omarchy-ambient-bundle-$(uname -m).tar.gz" \
  | grep -F /native/AmbientCells/libambientcells.so
```

The native module is optional: if its Qt development files or shader tools are
missing, the builder prints a warning and produces a working Canvas fallback.
For a release intended to include the GPU preview, require the archive check
above to pass for both architecture bundles. A successful bundle build by itself
does not establish that the native preview was included.

## Notes

- Ambient pauses a source on battery by default. To keep one running, set
  `on_battery=run` in `~/.config/omarchy/ambient/<id>.conf`.
- The Omarchy shell caches QML types by directory. After changing the plugin, load it
  from a new directory and update `entryPoints` in `manifest.json`.
- Closing the panel ends only its own preview process group, so the active background
  keeps running.

## Tests

```sh
python3 contrib/background-selector/test_selector.py
bash contrib/background-selector/tests/native-preview-test.sh
```

The native harness compiles the real `CellPreview` implementation with a test-only
friend and runs with Qt's offscreen platform. It needs a C++17 compiler, Qt 6
Quick/QML/GUI development files, `pkg-config` and `moc`; it does not open a window,
run the shell or preview daemon, or read or change installed files.

It checks 32,000 independently generated cells through the plain cells, JSON
cells and JSON runs parsers, including Unicode, protocol escapes, malformed
records and recovery between effects. It also compares 18 CPU snapshot/save
pairs at fractional metrics, DPR 1/1.5/2, two opacities and three skews. These are
parser and CPU snapshot checks, not GPU equivalence or performance measurements.
The legacy cells format uses comma and semicolon as delimiters; those characters
are tested as glyphs in the counted runs format instead.

## Resolution

In the carousel, the up and down arrows make the selected scene finer or
coarser, up to four steps each way from the automatic grid. A background
changes behind the carousel at once; in screensaver mode the choice is stored
for the next run. Enter keeps it and Escape restores the previous background.

The choice is one line per source, `resolution=auto+2`, in
`~/.config/omarchy/ambient/<source>.conf`. All the effects under the
`screensaver` source share it.

The plus and minus keys set the frame rate limit of the selected scene by 10,
or by 20 with Shift, from 20 to 240 fps: `fps=40` in the same file. Below 20
the limit goes back to auto, the default. In auto the renderer measures what a
frame costs, in CPU and, where the kernel tells, in GPU, and climbs to the
highest rate that stays within a quarter of one core and 30% of the GPU, never
past the display's refresh rate. It remembers the rate per scene, so the next
start begins there. A scene that holds the display's rate with room to spare is
also remembered with a finer grid, which shows from its next start; the carousel
shows both, as `auto (120 fps)` and `auto (+2)`. A resolution or limit chosen
with the keys always wins. On battery every scene drops to 20 and returns to
its limit on the charger.

The single TTFx effects run on the `ttfx` source, also in auto: each effect keeps
its own pace, and the limit only holds it back where the machine cannot afford it.

F shows or hides the frame rate on every running scene, without restarting it.
