# Handing Omarchy's screensaver over to omarchy-bg-live

Proposed change to the Omarchy fork branch `feat/backgrounds-and-amiga`, in
[`screensaver-launcher-and-menu.patch`](screensaver-launcher-and-menu.patch).
It is made against that branch's working tree as of 2026-10-25, applies with
`git apply`, and has not been applied there.

## What it changes

**`bin/omarchy-launch-screensaver`.** The branch point the fork already has
for Amiga becomes the general one: when `omarchy-bg-live screensaver --get`
is not `text`, the launcher hides the menu and `exec`s
`omarchy-bg-live screensaver`. The stock text screensaver stays exactly as
it is for everyone else, and `omarchy-launch-screensaver force text` still
forces it. The Amiga controller's lock check goes away: the engine keeps its
own lock and a second call exits 0 at once.

```sh
if [[ ${2:-} != "text" && ${2:-} != "default" ]] && omarchy-cmd-present omarchy-bg-live &&
  [[ $(omarchy-bg-live screensaver --get 2>/dev/null) != text ]]; then
  omarchy-shell -q shell hide omarchy.menu || true
  exec omarchy-bg-live screensaver
fi
```

The launcher runs in the foreground until the screensaver ends, like the
fork's Amiga path did. The idle service's process stays "running" meanwhile,
which only means a second launch in the same cycle is skipped.

**Menu, Style › Screensaver.** `style.screensaver` gets a
`screensaver-sources` provider: `omarchy-bg-live list screensaver` gives one
row per source with `screensaver` in its placements, the selected one checked
(rows are `name, id, selected id, description, icon`, the same shape as the
`background-sources` provider). Choosing a row runs
`omarchy-bg-live screensaver --set <id>`, which installs and prepares the
source first. "Default" checks and selects `text`. Preview, Edit Text, Set
From Image and Restore Default stay. The static Amiga entry goes: Amiga is a
source now. `Menu.qml` also lets a row carry its own icon (`parts[4]`), as
in the `background-sources` patch.

## What it leaves for later

The fork's own Amiga stack (`omarchy-setup-screensaver`,
`omarchy-screensaver-amiga`, `packages/amiga-runtime`, the input guard) is no
longer called by the launcher or the menu after this change. Removing it is a
separate decision, and so is what the `amiga` source loses against it in v1:
audio on `M` and Left/Right through the history (`input=own`, v2), and the
sandboxed, checksum-bound runtime (the source uses the system `fs-uae` and the
published pack, verified by its SHA-256).

## The idle service

Nothing changes in it. It keys the end of the screensaver on windows of class
`org.omarchy.screensaver`, which a layer doesn't have, but it cancels the
cycle on any activity once the three-second launch grace is over, and the
activity that dismisses the screensaver is exactly that. Checked on mbp-intel
with Omarchy 4.0.6 through a clone of the idle service
([`test/hardware/trial-idle.sh`](../../test/hardware/trial-idle.sh)), which
calls a pinned copy of the stock launcher with the block above:

```
idle-cycle-start: screensaver=15 lock=45
process-start: screensaver ... omarchy-launch-screensaver
idle-monitor: active
idle-cycle-cancel: activity          <- dismissed; the pending lock is cancelled
...
idle-cycle-start: screensaver=15 lock=45
process-start: screensaver ...
lock-system: lock-timeout            <- nobody came back; the lock takes over
process-exit: screensaver exitCode=0 <- 2.3 s later, nothing left running
```

## Trying it without touching /usr

On a test machine only:

```sh
make && make -C test/hardware
test/hardware/trial-idle.sh install .        # clone the idle service, pin the launcher
omarchy-bg-live screensaver --set amiga
test/hardware/trial-idle.sh timeouts 15 0    # screensaver after 15 s, no lock
omarchy-shell -q idle enable                 # leave stay-awake
...
test/hardware/trial-idle.sh undo             # stock idle service and timeouts back
```
