# omarchy-bg-live

Live backgrounds for [Omarchy](https://omarchy.org): programs that draw behind
your windows instead of a still image or a video.

It comes with two:

- **Screensaver**: the Omarchy screensaver's ttfx effects, on every monitor.
- **Amiga Demos**: classic demoscene productions running in FS-UAE. The demos
  are downloaded the first time you choose them.

Anyone can add more: a terminal program, an emulator, a shader, a game. See
[Creating a live background](docs/creating-sources.md).

## How it works

Each live background is a program that draws its own layer surface on the
bottom layer, behind the windows and above the regular wallpaper. Nothing is
converted to video. A supervisor runs it as the `omarchy-bg-live` user unit
and:

- starts one program per monitor (or one in total), and follows monitors
  being plugged in and out;
- pauses OWE while a live background runs, and resumes it afterwards;
- freezes a monitor's program with SIGSTOP while the monitor is off or shows
  a fullscreen window, while the session is locked, and on battery, so a
  background nobody sees costs nothing;
- restarts a program that dies, and gives up on one that keeps dying;
- ends when you set an ordinary background or a theme.

## Usage

```sh
omarchy-bg-live list                    # the sources, as menu rows
omarchy-bg-live start screensaver       # start one, in the background
omarchy-bg-live start amiga             # pick a demo first
omarchy-bg-live status                  # what is running, or "none"
omarchy-bg-live stop
```

In Omarchy, the sources appear under **Style › Background**.

## Install

Building needs a C compiler, `wayland-scanner` and `wayland-protocols`:

```sh
make
make install PREFIX=~/.local
```

At run time it needs `bash`, `jq`, `socat`, `inotifywait` (inotify-tools) and
Hyprland. Each source lists what else it needs, and offers to install it the
first time it starts.

## Tests

```sh
make test
```

## License

MIT. `vendor/gtk4-layer-shell` is gtk4-layer-shell 1.3.0 by Sophie Winter,
also MIT; see its LICENSE.
