# omarchy-bg-live

Live backgrounds and screensavers for [Omarchy](https://omarchy.org): programs
that draw behind your windows instead of a still image or a video, or over
everything once you step away.

It comes with two:

- **Terminal Effects**: the Omarchy screensaver's ttfx effects in a terminal, on
  every monitor.
- **Amiga Demos**: classic demoscene productions running in FS-UAE. The demos
  are downloaded the first time you choose them. As a screensaver it goes
  through all of them, muted.

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

### In Omarchy's menus

Omarchy releases that know about omarchy-bg-live list the sources under
**Appearance › Live Background** and **Appearance › Branding › Screensaver**
by themselves. On the others, one command adds the same rows to your menu
extension and routes the idle screensaver through omarchy-bg-live:

```sh
omarchy-bg-live omarchy install     # menu rows, and the idle service routed
omarchy-bg-live omarchy status      # menu=yes|no|native idle=yes|no|native
omarchy-bg-live omarchy uninstall   # Omarchy's own menu and idle service back
```

The rows go between two marked lines in
`~/.config/omarchy/extensions/omarchy-menu.jsonc`, and nothing else in that
file changes. The idle service is cloned into
`~/.config/omarchy/plugins/omarchy-bg-live.idle`, because Omarchy's idle
service runs its own screensaver launcher by a path no user file can
override. Run `install` again after adding a source, so it gets a row.

### As the screensaver

```sh
omarchy-bg-live screensaver --set amiga   # use it at the idle timeout
omarchy-bg-live screensaver               # run it now; any activity ends it
omarchy-bg-live screensaver --get         # the selected one, or "text"
omarchy-bg-live screensaver --set text    # back to Omarchy's own
```

A screensaver covers every monitor with the keyboard to itself and the cursor
hidden, ends on the first mouse motion, click, scroll or key, and gives way to
the lock screen. Omarchy's launcher has to hand over to it; see
[docs/omarchy](docs/omarchy/README.md). The design is in
[docs/screensaver-mode.md](docs/screensaver-mode.md).

## Install

Building needs a C compiler, `wayland-scanner` and `wayland-protocols`:

```sh
make
make install PREFIX=~/.local
omarchy-bg-live omarchy install
```

At run time it needs `bash`, `jq`, `socat`, `inotifywait` (inotify-tools) and
Hyprland. Each source lists what else it needs, and offers to install it the
first time it starts.

## Tests

```sh
make test
```

`test/hardware` checks it all on a real Hyprland session, with nobody at the
keyboard (a virtual pointer and `wtype` stand in for the user). They draw on
the screen, so run them where nobody is working:

```sh
make -C test/hardware
test/hardware/screensaver-check.sh amiga 20   # every input ends it, nothing reaches the window under it, 20 cycles
test/hardware/background-check.sh amiga       # bottom layer, frozen under fullscreen and the screensaver
test/hardware/trial-idle.sh install .         # route the real idle cycle through a checkout (undo with undo)
```

## License

MIT. `vendor/gtk4-layer-shell` is gtk4-layer-shell 1.3.0 by Sophie Winter,
also MIT; see its LICENSE.
