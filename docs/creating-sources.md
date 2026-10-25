# Creating a live background

A live background is any program that draws behind your windows: a terminal
effect, an emulator running a demo, a shader, a game in attract mode, a
dashboard. `omarchy-bg-live` runs it, gives it an output to cover, and freezes
it whenever nobody can see it.

Each live background comes from a **source**: a directory with a
`source.conf` and an executable called `run`. Put your own in
`~/.config/omarchy/bg-live/sources/<id>/` and it shows up in
**Style › Background**, next to the bundled ones. A source can also be a
screensaver; see [Screensavers](#screensavers).

## Your first source in two minutes

Matrix rain from `cmatrix`, behind your windows:

```sh
mkdir -p ~/.config/omarchy/bg-live/sources/matrix
cd ~/.config/omarchy/bg-live/sources/matrix

cat > source.conf <<'EOF'
name=Matrix
icon=󰘦
description=Falling green characters
needs=cmatrix kitty
packages=cmatrix kitty
EOF

cat > run <<'EOF'
#!/bin/bash
exec kitty +kitten panel --edge=center --layer=bottom --focus-policy=not-allowed \
  --output-name="$OMARCHY_BG_LIVE_OUTPUT" cmatrix -b
EOF
chmod +x run

omarchy-bg-live check .
omarchy-bg-live start matrix
```

`omarchy-bg-live stop`, choosing a theme, or setting an ordinary background
ends it.

## The directory

| File | Required | What it does |
| - | - | - |
| `source.conf` | yes | Name, icon and behavior; see below |
| `run` | yes | Draws the background. Runs in the foreground until it is told to stop |
| `prepare` | no | Runs once before every start, before `pick`. Use it to download or build what `run` needs, and exit early when it is already there |
| `pick` | no | Lets the user choose what to show (a demo, a level, a color). Prints the choice on stdout; printing nothing cancels |

The directory name is the source's id: lowercase letters, digits and dashes.
A source in `~/.config/omarchy/bg-live/sources` replaces a bundled source with
the same id.

## source.conf

Plain `key=value` lines; `#` starts a comment.

| Key | Default | Meaning |
| - | - | - |
| `name` | the id | Shown in the menu |
| `icon` | | A Nerd Font glyph shown next to the name |
| `description` | | Shown in search results |
| `order` | `50` | Lower comes first in the menu |
| `outputs` | `each` | `each`: one `run` per monitor, so each gets its own program. `focused`: one `run`, on the monitor that has focus when it starts. `all`: one `run` that covers every monitor by itself |
| `pause` | `stop` | `stop`: freeze the program with SIGSTOP while it can't be seen. `none`: never freeze it |
| `on_battery` | `pause` | `pause`: treat running on battery as unseen. `run`: keep going on battery |
| `needs` | | Commands the source needs, separated by spaces. `kitty\|ghostty` means either one will do |
| `placements` | `background` | Where it can run: `background`, `screensaver`, or both separated by a space |
| `input` | `dismiss` | As a screensaver. `dismiss`: any activity ends it. `own`: the source takes input itself and ends the screensaver by exiting 0 |
| `packages` | | Packages that provide them. When a need is missing, starting the source offers to install these |

Every other key is a setting of your own. It reaches `prepare`, `pick` and
`run` as `OMARCHY_BG_LIVE_SETTING_<KEY>`, so `speed=3` arrives as
`OMARCHY_BG_LIVE_SETTING_SPEED=3`. Users change any key, yours included, in
`~/.config/omarchy/bg-live/<id>.conf` without touching the source:

```sh
# ~/.config/omarchy/bg-live/amiga.conf
outputs=focused
```

## What `run` gets

`run` receives the user's choice (from `pick`, or from
`omarchy-bg-live start <id> <choice>`) as its first argument, and this
environment:

| Variable | Value |
| - | - |
| `OMARCHY_BG_LIVE_OUTPUT` | The monitor to cover, such as `eDP-1`. Empty when `outputs=all` |
| `OMARCHY_BG_LIVE_WIDTH`, `OMARCHY_BG_LIVE_HEIGHT` | That monitor's size in pixels |
| `OMARCHY_BG_LIVE_SCALE` | Its scale factor |
| `OMARCHY_BG_LIVE_CHOICE` | The choice again |
| `OMARCHY_BG_LIVE_SOURCE`, `OMARCHY_BG_LIVE_SOURCE_DIR` | The id and the source's directory |
| `OMARCHY_BG_LIVE_DATA` | A directory that persists: `~/.local/share/omarchy-bg-live/<id>`. Downloads go here |
| `OMARCHY_BG_LIVE_RUNTIME` | A directory for this run only, removed when it ends |
| `OMARCHY_BG_LIVE_NAMESPACE` | A layer namespace to use: `omarchy-bg-live-<id>` |
| `OMARCHY_BG_LIVE_PLACEMENT` | `background` or `screensaver` |
| `OMARCHY_BG_LIVE_LAYER` | The layer to draw on: `bottom`, or `overlay` as a screensaver |
| `OMARCHY_BG_LIVE_KEYBOARD` | `none`, or `exclusive` as a screensaver |
| `OMARCHY_BG_LIVE_SETTING_*` | Your settings |

`prepare` and `pick` get the same variables, except the output and runtime
ones.

### Rules for `run`

- **Stay in the foreground.** Use `exec` for the last command, and don't
  daemonize. When `run` exits, it is restarted; a program that keeps dying
  within ten seconds of starting is given up on after five tries.
- **Draw behind the windows, on the given output.** See the next section.
- **Don't take input.** A background never gets keyboard focus.
- **Expect to be frozen.** With `pause=stop`, the whole process group gets
  SIGSTOP when the output is off or shows a fullscreen window, when the
  session is locked, and on battery, then SIGCONT when it is seen again. Most
  programs need nothing for this. Programs that measure time should cope with
  a sudden jump.
- **End on SIGTERM.** Anything still running three seconds later gets SIGKILL.

## Getting a program behind the windows

A Wayland program normally opens a window. A background has to be a layer
surface on the bottom layer instead. There are three ways to get one.

**The program can do it itself.** Kitty's panel kitten draws a terminal on
the bottom layer, on a named output, so any terminal program becomes a
background:

```sh
exec kitty +kitten panel --edge=center --layer=bottom --focus-policy=not-allowed \
  --output-name="$OMARCHY_BG_LIVE_OUTPUT" your-program
```

**Anything else goes through `omarchy-bg-live layer`.** It preloads a small
library that turns the program's first window into a full-screen layer
surface on `OMARCHY_BG_LIVE_OUTPUT`, on the bottom layer, without keyboard
focus:

```sh
exec omarchy-bg-live layer mpv --no-audio "av://lavfi:mandelbrot"
SDL_VIDEODRIVER=wayland exec omarchy-bg-live layer fs-uae demo.fs-uae
```

The library builds on
[gtk4-layer-shell](https://github.com/wmww/gtk4-layer-shell)'s preload. It
also lets SDL programs (emulators, games) run, which the stock preload
doesn't. Some programs still won't cooperate. This is what has been tried:

| Program | Through `layer` |
| - | - |
| mpv, FS-UAE (SDL), ghostty | Works |
| kitty | Works, but its panel kitten is simpler |
| alacritty | Opens the surface but never starts its command |
| foot | Hangs at startup |

**A program written for this** can create its own layer surface with
gtk4-layer-shell, or any wlr-layer-shell binding, using
`OMARCHY_BG_LIVE_OUTPUT` and the `bottom` layer.

## Screensavers

Add `screensaver` to `placements` and the source shows up in
**Style › Screensaver** too. When the idle timeout comes,
`omarchy-bg-live screensaver` runs it over everything on every monitor (with
`outputs=each`), with the keyboard to itself and the cursor hidden. The first
mouse motion, click, scroll or key ends it, and so does the session locking.
A live background is frozen meanwhile.

`run` is the same program; it reads `OMARCHY_BG_LIVE_PLACEMENT` to tell. It
must cover the whole output with an opaque surface, on
`OMARCHY_BG_LIVE_LAYER` and with `OMARCHY_BG_LIVE_KEYBOARD`.
`omarchy-bg-live layer` does that already. A program that makes its own
layer surface follows them itself, and should not bind text input
(`zwp_text_input_v3`): Hyprland takes the input method's reply to it for user
activity, which ends the screensaver.

A screensaver may change what it shows at any time, even restart its program
for the next demo: dismissal does not depend on its surface. To avoid
showing the desktop in between, start the next program before ending the
last one, as [`sources/amiga/run`](../sources/amiga/run) does.

```sh
omarchy-bg-live screensaver --set matrix   # choose it (installs and prepares it)
omarchy-bg-live screensaver matrix         # preview it now
omarchy-bg-live screensaver --set text     # back to Omarchy's own
```

## Trying it out

```sh
omarchy-bg-live check ~/.config/omarchy/bg-live/sources/matrix
omarchy-bg-live run matrix        # in the foreground; Ctrl+C ends it
omarchy-bg-live start matrix      # in the background, like the menu does
omarchy-bg-live status
journalctl --user -u omarchy-bg-live -f
```

The log shows each program starting, pausing, resuming, restarting and
ending, per output.

## Examples

- [`sources/screensaver`](../sources/screensaver): the Omarchy screensaver's
  ttfx effects, through kitty's panel or ghostty.
- [`sources/amiga`](../sources/amiga): `prepare` downloads and verifies a demo
  pack, `pick` shows previews, and `run` plays the demo in FS-UAE through
  `omarchy-bg-live layer`.
- [`examples/system-monitor`](../examples/system-monitor): a terminal program
  (btop) as the background.
- [`examples/mandelbrot`](../examples/mandelbrot): a graphical program (mpv)
  as the background, with a setting for its resolution.
- [`examples/c64`](../examples/c64): a Commodore 64 program of your own in
  VICE, as the background or the screensaver. Untested sketch: the VICE
  package isn't on the test machines yet.

Copy any of them into `~/.config/omarchy/bg-live/sources/` to start your own.
