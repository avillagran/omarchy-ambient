# omarchy-ambient

Live backgrounds and screensavers for [Omarchy](https://omarchy.org): programs
that draw behind your windows instead of a still image or a video, or over
everything once you step away.

It sits next to OWE, Omarchy's wallpaper engine, rather than replacing it:
OWE plays images and videos, omarchy-ambient runs programs. While a live
background is up, OWE is paused, and it resumes when the program ends.

It comes with three:

- **Omarchy Effects**: the Omarchy screensaver's ttfx effects drawn on the GPU
  by `omarchy-ttfx-layer`, which keeps its frame rate within what the
  computer can afford. It comes with the Omarchy Audio Background plugin, or
  set `binary=` in `~/.config/omarchy/ambient/ttfx.conf`.
- **Amiga Demos**: classic demoscene productions running in FS-UAE. The demos
  are downloaded the first time you choose them. As a screensaver it goes
  through all of them, muted.
- **Terminal Effects**: the same effects in a kitty or ghostty terminal, for
  computers without the GPU renderer.

All three run as the background; Omarchy Effects and Amiga Demos also run as
the screensaver.

Anyone can add more: a terminal program, an emulator, a shader, a game. See
[Creating a live background](docs/creating-sources.md).

## Try the ASCII scenes

On an Omarchy that ships omarchy-ambient, the scenes and their selector are
already there: Super+Ctrl+Space or Appearance > Background opens them.
Elsewhere, install them for your user:

```sh
curl -fsSL https://raw.githubusercontent.com/avillagran/omarchy-ambient/main/install.sh | bash
```

It needs Omarchy 4.0 or newer, on x86_64 or ARM64.
It installs for your user under `~/.local`, without sudo, and verifies the download.
Remove it with the same command, ending in `| bash -s -- --uninstall`.
After the install, Super+Ctrl+Space opens the selector in place of Omarchy's
background menu, and the uninstall gives the shortcut back.

```sh
omarchy-ambient start sand-clock-galaxy            # try one
omarchy-ambient-select background                  # pick the background, with live previews
omarchy-ambient-select screensaver                 # pick the screensaver, the same way
omarchy-ambient stop                               # back to your wallpaper
```

In the carousel, arrows left and right choose a scene and up and down change its
resolution, live behind the carousel. Plus and minus set its frame rate limit, by
10 or by 20 with Shift, and F shows the fps. Enter keeps it, Escape restores it.
Scenes find their own pace: they climb to what the machine affords, up to the
display's refresh rate, and a machine with room to spare gets a finer grid from
the next start. On battery they drop to 20 fps.

One engine runs them all: every scene works as a background and as a screensaver.
Every scene is drawn from text glyphs on the GPU, reacts to what is playing, and
follows the cursor.

| | | |
|---|---|---|
| ![Sunset Drive](docs/media/sunset-drive.jpg) | ![Lunar Drift](docs/media/lunar-drift.jpg) | ![Neon City](docs/media/neon-city.jpg) |
| Sunset Drive | Lunar Drift | Neon City |
| ![Neon Transit](docs/media/neon-transit.jpg) | ![Eye](docs/media/eye.jpg) | ![Cockpit](docs/media/cockpit.jpg) |
| Neon Transit | Eye | Cockpit |
| ![Aquarium](docs/media/aquarium.jpg) | ![Jellyfish](docs/media/jellyfish.jpg) | ![Data Globe](docs/media/data-globe.jpg) |
| Aquarium | Jellyfish | Data Globe |
| ![Sand Clock Galaxy](docs/media/sand-clock-galaxy.jpg) | ![Sand Clock Chladni](docs/media/sand-clock-chladni.jpg) | ![Sand Clock Dunes](docs/media/sand-clock-dunes.jpg) |
| Sand Clock Galaxy | Sand Clock Chladni | Sand Clock Dunes |
| ![Event Horizon](docs/media/event-horizon.jpg) | ![Supernova](docs/media/supernova.jpg) | ![Abyss](docs/media/abyss.jpg) |
| Event Horizon | Supernova | Abyss |
| ![Solar System](docs/media/solar-system.jpg) | ![Load Canyon](docs/media/load-canyon.jpg) | ![Neon Avenue](docs/media/neon-avenue.jpg) |
| Solar System | Load Canyon | Neon Avenue |
| ![Packet Grid](docs/media/packet-grid.jpg) | ![Silicon](docs/media/silicon.jpg) | ![Sand Clock Ferrofluid](docs/media/sand-clock-ferrofluid.jpg) |
| Packet Grid | Silicon | Sand Clock Ferrofluid |
| ![Sand Clock Excavation](docs/media/sand-clock-excavation.jpg) | ![Sand Clock Zen](docs/media/sand-clock-zen.jpg) | ![Sand Clock Foundry](docs/media/sand-clock-foundry.jpg) |
| Sand Clock Excavation | Sand Clock Zen | Sand Clock Foundry |
| ![Sand Clock Swarm](docs/media/sand-clock-swarm.jpg) | ![Sand Clock Shore](docs/media/sand-clock-shore.jpg) | ![Sand Clock Glass](docs/media/sand-clock-glass.jpg) |
| Sand Clock Swarm | Sand Clock Shore | Sand Clock Glass |
| ![Sand Clock Dust Devil](docs/media/sand-clock-dust-devil.jpg) | ![Sand Clock Spectrum](docs/media/sand-clock-spectrum.jpg) | ![Sand Clock Mandala](docs/media/sand-clock-mandala.jpg) |
| Sand Clock Dust Devil | Sand Clock Spectrum | Sand Clock Mandala |

The sand clocks are toys to play with. The cursor never clicks, so they read
its motion: the time breaks into sand wherever the cursor passes and pours
back, circling stirs a vortex, and a quick side to side shake blows the clock
apart for a moment. They hear beats, drops and silence too. Ten are built
around play: Ferrofluid is black magnetic fluid the cursor pulls into spikes;
Excavation hides relics under sand for the cursor to brush off; Zen is a garden
it rakes; Foundry fuses sand into circuit traces that beats run along; Swarm is
nanobots that turn into a live waveform with music; Shore keeps glowing
footprints until a wave takes them; Glass gathers dust in front of a neon city
for the cursor to wipe; Dust Devil raises a whirlwind where the cursor rests;
Spectrum pours sand into equalizer tubes the cursor blows apart; Mandala repeats
every stroke round the time and sweeps it all into the new minute.

Event Horizon through Silicon are solid 3D: a perspective camera,
depth-tested triangles and ray-traced spheres, shaded with glyphs. Several draw the machine itself, read
from `/proc`: Solar System and Load Canyon show per-core CPU load, memory and
swap; Neon Avenue lights its windows and fills its sky lanes with CPU load;
Packet Grid turns network traffic into pulses of light, downloads running at
you and uploads away; Silicon raises and heats one core per CPU, fills its
memory chips with use and sends disk and network traffic along its traces. All
three answer the music and the cursor: it steers the flight down the avenue
and scans the facade it points at, marks the grid's floor and draws packets
in, and turns the board to name the core it rests on. Event Horizon swallows
the rocks and star dust the cursor throws in, and each one it eats flares the
photon ring.

In the four journeys (Neon City, Vector Highway, Circuit Run and Sunset Drive)
the cursor brings what it rests on into focus: in Neon City the tower under it
wakes, with a scan line climbing its windows and its name over the roof; on the
other roads a palm, a cactus, a sign, a prism, a ridge or a patch of moon
ground lights up, framed, with its name or altitude over it. Every beat sends a
ring of light out from the cursor. Load Canyon turns almost all the way round
with the cursor, so the newest relief can be watched from afar, and Abyss keeps
three shoals: silver fish, large golden ones and glowing lanternfish.

## How it works

Each live background is a program that draws its own layer surface on the
bottom layer, behind the windows and above the regular wallpaper. Nothing is
converted to video. A supervisor runs it as the `omarchy-ambient` user unit
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
omarchy-ambient list                    # the sources, as menu rows
omarchy-ambient start screensaver       # start one, in the background
omarchy-ambient start amiga             # pick a demo first
omarchy-ambient status                  # what is running, or "none"
omarchy-ambient stop
```

### In Omarchy's menus

Omarchy releases that know about omarchy-ambient offer live backgrounds
and screensavers by themselves. On the others, one command turns
**Style › Background** into a submenu (Theme, Screensaver, Amiga Demos when
installed, Random), where **Screensaver** opens the selector with live
previews straight away, adds **Set ASCII Scenes …** to the screensaver menu,
and routes the idle screensaver through omarchy-ambient:

```sh
omarchy-ambient install     # menu rows, and the idle service routed
omarchy-ambient installed   # menu=yes|no|native idle=yes|no|native
omarchy-ambient remove      # Omarchy's own menu and idle service back
```

The rows go between two marked lines in
`~/.config/omarchy/extensions/omarchy-menu.jsonc`, and nothing else in that
file changes. The idle service is cloned into
`~/.config/omarchy/plugins/omarchy-ambient.idle`, because Omarchy's idle
service runs its own screensaver launcher by a path no user file can
override. The selector lists every scene by itself, so a new source needs no new row.

### As the screensaver

```sh
omarchy-ambient screensaver --set amiga   # use it at the idle timeout
omarchy-ambient screensaver               # run it now; any activity ends it
omarchy-ambient screensaver --get         # the selected one, or "text"
omarchy-ambient screensaver --set text    # back to Omarchy's own
```

A screensaver covers every monitor with the keyboard to itself and the cursor
hidden, ends on the first mouse motion, click, scroll or key, and gives way to
the lock screen. Omarchy's launcher has to hand over to it; see
[docs/omarchy](docs/omarchy/README.md). The design is in
[docs/screensaver-mode.md](docs/screensaver-mode.md).

## Install

Building needs a C compiler, `wayland-scanner`, `wayland-protocols` and `jq`.
With the Qt 6 Quick development files and Qt Shader Tools it also builds the
GPU painter of the selector's previews; without them the previews use Canvas.

```sh
make
make install PREFIX=~/.local
omarchy-ambient selector enable   # link the selector into the Omarchy shell
```

`make install` puts in the program, its sources and scenes, and the background
selector: `omarchy-ambient-select`, the shell plugin it opens, and the scene
posters. `omarchy-ambient selector enable` links that plugin into
`~/.config/omarchy/plugins` and enables it; the selector also does it the first
time it opens. `omarchy-ambient selector disable` takes it back.

At run time it needs `bash`, `jq`, `socat`, `inotifywait` (inotify-tools),
`python3` and Hyprland, and the Omarchy Effects source and the scenes need
[omarchy-ttfx-layer](https://github.com/avillagran/omarchy-ttfx-layer) on the
PATH. Each other source lists what else it needs, and offers to install it the
first time it starts. `packaging/arch/PKGBUILD` builds the package for x86_64
and aarch64.

### Coming from omarchy-bg-live

This was called omarchy-bg-live at first. `make install` removes the old
program, the first run moves `~/.config/omarchy/bg-live` and
`~/.local/share/omarchy-bg-live` over, and `omarchy-ambient install` swaps the
old menu rows and idle clone for the new ones. `omarchy-ambient omarchy
install|uninstall|status` still work.

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
