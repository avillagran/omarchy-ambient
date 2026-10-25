# Screensaver mode (design contract)

Status: agreed design, engine side implemented (2026-10-25). The changes made
while implementing it are listed at the end. Two pieces are built
in parallel against this document: the engine side (supervisor, guard,
Omarchy integration, Amiga source) and the `ttfx` source (the GPU layer
renderer from omarchy-audio-background). Change this file first when the
contract has to change, and say so in both places.

## Goal

One engine runs any kind of live content, either behind the windows (a
background) or over everything after the idle timeout (a screensaver). A
content type is a source, as today. ttfx effects, Amiga demos and, later, C64
demos are just sources. Nothing is converted to video.

The engine owns everything that is the same for every source: monitors,
layers, pausing, session lock, cursor, dismissal, restarts. A source only
draws.

## Placements

A source runs in one of two placements:

| Placement | Layer | Keyboard | Ends when |
| - | - | - | - |
| `background` | `bottom` | none | the user picks another background or theme |
| `screensaver` | `overlay` | exclusive | the user moves the mouse, clicks, scrolls or types; the session locks; SIGTERM |

`source.conf` declares which placements a source supports:

```
placements=background screensaver   # default: background
```

Sources without `screensaver` never appear in the screensaver menu.

## What `run` gets, in addition to today's environment

| Variable | Value |
| - | - |
| `OMARCHY_BG_LIVE_PLACEMENT` | `background` or `screensaver` |
| `OMARCHY_BG_LIVE_LAYER` | `bottom` or `overlay`. A program that creates its own layer surface must use it |
| `OMARCHY_BG_LIVE_KEYBOARD` | `none` or `exclusive`. Same rule |

`omarchy-bg-live layer` (the preload library) honors both variables, so
programs started through it (FS-UAE, VICE, mpv) need no change. It also
keeps two requests from reaching the compositor: idle inhibitors, so live
content never holds off the screensaver or the lock, and text input
(`zwp_text_input_v3`). SDL enables text input whenever it gets the keyboard,
that wakes the input method (fcitx5 in Omarchy), and Hyprland counts the input
method's reply as user activity, which dismissed the screensaver each time a
demo started. A program that creates its own layer surface should not bind
text input either.

In the screensaver placement the surface must cover the whole output and be
opaque. With `exclusive` keyboard, keys never reach the application under
the screensaver.

## Dismissal

Default (`input=dismiss` in `source.conf`): the engine ends the screensaver
on the first user activity. It does not depend on the content surface
receiving input. A small helper, `omarchy-bg-live-dismiss` (`build/` in a
checkout, `lib/omarchy-bg-live/` when installed), subscribes to
`ext_idle_notify_v1` with a short timeout, using the input-only notification
so idle inhibitors do not mask activity, prints `ready`, and prints `activity`
and exits on `resumed`. The engine covers nothing until the helper is ready,
and refuses to start when it is not within five seconds, so a screensaver
never takes the keyboard without a way to end it. On activity it stops every
`run` (SIGTERM, then SIGKILL after three seconds), restores the cursor and
exits 0.

Because dismissal does not depend on which surface is on top, a source may
restart its program or remap its surface (a demo transition) at any time.

`input=own`: the source handles input itself and exits with status 0 to end
the screensaver. For sources that use keys while running, such as Amiga's
`M` to toggle audio and Left/Right to move through the demo history. The
engine still ends it on session lock and SIGTERM.

The first activity after the screensaver starts is ignored for a short grace
period (default 1 s), so the event that crossed the idle threshold, or the
menu click on "Preview", does not dismiss it at once.

## Engine commands

```sh
omarchy-bg-live screensaver                 # run the selected screensaver, foreground
omarchy-bg-live screensaver <id> [choice]   # run a specific one (menu "Preview")
omarchy-bg-live screensaver --get           # selected source id, or "text" for the stock one
omarchy-bg-live screensaver --set <id>      # select it; "text" restores the stock screensaver
omarchy-bg-live list screensaver            # menu rows: the sources with screensaver in placements
```

- `--set` installs what the source needs and runs its `prepare` (the Amiga
  download) before it selects it, so the idle path never installs or
  downloads. Without a choice the screensaver skips `pick`.

- The selection lives in `~/.config/omarchy/bg-live/screensaver.conf` as
  `source=<id>`. Settings for a source in the screensaver placement are read
  from `~/.config/omarchy/bg-live/<id>.conf` as today, and a
  `[screensaver]` section is not needed in v1.
- One screensaver at a time: a lock in `$XDG_RUNTIME_DIR`. A second call
  exits 0 at once, like the stock launcher does.
- Outputs follow `outputs=`. `each` is the normal case for a screensaver.
- While the screensaver runs, a live background is frozen (it cannot be
  seen) and resumed afterwards.
- The cursor is hidden while it runs and restored on every exit path, the
  way `omarchy-screensaver` does it
  (`hyprctl eval 'hl.config({ cursor = { invisible = true } })'`).
- On session lock the screensaver ends; the lock screen takes over, as with
  the stock screensaver. Hyprland sends no event for it, so the screensaver
  looks every two seconds (a live background every five).
- A live background with `pause=none` keeps running under it, as it keeps
  running everywhere else.

## Omarchy integration

The idle service runs `omarchy-launch-screensaver` through `bash -lc`.
`~/.local/bin` is not ahead of `/usr/bin` on that PATH, so a user wrapper
does not override it, and nothing may be installed under `/usr`.

- Upstream path (preferred): the launcher delegates to
  `omarchy-bg-live screensaver` when `omarchy-bg-live screensaver --get` is
  not `text`. The Omarchy fork branch `feat/backgrounds-and-amiga` already
  routes the launcher to the Amiga screensaver; generalize that branch point
  instead of adding a second one.
- Local testing without touching `/usr`: the approach omarchy-amiga's
  installer uses (a cloned idle service that calls a pinned launcher) is
  acceptable on test machines only, and must be fully undoable.
- The idle service cancels the pending lock when the screensaver window
  closes, keyed on the `org.omarchy.screensaver` class. A layer has no
  window. User activity already wakes the idle monitor, which cancels the
  cycle, so dismissal keeps working. Verified on mbp-intel through a cloned
  idle service (`test/hardware/trial-idle.sh`): the dismissal logs
  `idle-cycle-cancel: activity` and no lock follows, and when the lock
  timeout comes with the screensaver up, the lock takes over and the
  screensaver ends about two seconds later.
- The change to Omarchy is the draft pull request omacom/omarchy#16587, and
  `omarchy-bg-live omarchy install` does the same from user files on releases
  without it; both are explained in [`docs/omarchy/README.md`](omarchy/README.md).
- Menu: Style › Screensaver lists the stock text screensaver plus every
  source with `screensaver` in `placements`, and a Preview entry.

## Sources

| Source | Placements | Input | Program |
| - | - | - | - |
| `ttfx` | background, screensaver | dismiss | `omarchy-ttfx-layer`, the GPU layer renderer: draws its own layer surface, picks its frame-rate ceiling from measured CPU cost |
| `amiga` | background, screensaver | own (v2), dismiss (v1) | FS-UAE through `omarchy-bg-live layer`, started from the pack's saved states |
| `c64` (later) | background, screensaver | dismiss | VICE (`x64sc`) through `omarchy-bg-live layer`, same pattern as Amiga |

The existing kitty/ghostty `screensaver` source stays as a fallback for
machines without the GPU renderer.

### `omarchy-ttfx-layer` command line (ttfx source)

```
omarchy-ttfx-layer --output <name> --layer bottom|overlay --keyboard none|exclusive
                   [--effects a,b,c] [--rotate <seconds>] [--fps auto|<n>]
                   [--text <wordmark>] [--audio] [--namespace <ns>]
```

It covers one output, exits 0 on SIGTERM after destroying its surface, and
never reads the audio-background plugin's state or takes its controller
lock, so both can run at once.

## Test bar

Everything is tested on mbp-intel (2015 MacBook Pro, Iris 6100, Hyprland
0.56) before it is called done:

- idle timeout starts it on every monitor; mouse motion, a click, a scroll
  and a key each dismiss it, and no key reaches the window underneath;
- a demo transition or effect rotation does not break dismissal;
- the lock at the lock timeout takes over cleanly and nothing keeps
  running under the lock screen;
- no layer is left behind (`hyprctl layers`, no `pid: -1`);
- CPU, GPU busy and temperature while it runs, against the stock
  foot + ttfx screensaver.

## Changes made while implementing it

- Text input is stubbed by the layer library, besides idle inhibitors (see
  "What `run` gets"). Found on mbp-intel: without it, every FS-UAE start
  inside the screensaver dismissed it.
- The dismiss helper's name, output and failure rule are fixed (see
  "Dismissal"), and the engine refuses to run without it.
- `list screensaver` was added for the menu, and `--set` prepares the source.
- The session lock is noticed by polling, within two seconds.
- `pause=none` backgrounds are not frozen under the screensaver.


## Measured on mbp-intel (2026-10-25)

One output, eDP-1 2560x1600 at scale 2. 60 s each, after a warm-up, with
45 s between runs. CPU per process is a share of one thread, "all CPUs" a
share of the four. GPU busy comes from the i915 RC6 residency; temperature is
`thermal_zone2` (x86_pkg_temp).

| Screensaver | All CPUs | Program | Hyprland | GPU busy | Temp |
| - | - | - | - | - | - |
| none (idle desktop) | 0.3% | | 0.0% | ~0% | 49.8 °C |
| `amiga` (FS-UAE, one demo) | 21.1% | fs-uae 62.5% | 8.8% | 66.2% | 71.9 °C |
| `ttfx` (`omarchy-ttfx-layer`, rotate=10) | 3.4% | 4.5% | 4.5% | 22.2% | 59.5 °C |
| stock (foot + ttfx) | 42.4% | foot 123.8% | 31.9% | 43.9% | 72.2 °C |

The supervisor itself (`omarchy-bg-live`) stays at 0.1%. Dismissal took about
200 ms for every kind of input with Amiga, and about 580 ms with ttfx
(measured by the ttfx thread). FS-UAE emulating a full Amiga is the costly
one: as a screensaver it costs about half of the stock one in CPU, but more
GPU.
