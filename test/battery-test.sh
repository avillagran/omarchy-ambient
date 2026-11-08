#!/bin/bash

# What a live background does on battery: the choice in Background > On
# Battery, a source's own on_battery under it, the scene told about it, and a
# note when the charger comes or goes and that changes what the user sees.

source "$(dirname "$0")/lib.sh"

export OMARCHY_AMBIENT_PATH=$scratch/sources OMARCHY_PATH=$scratch/omarchy
conf=$XDG_CONFIG_HOME/omarchy/ambient
mkdir -p "$conf" "$OMARCHY_PATH"
touch "$OMARCHY_PATH/icon.png"

make_source "$scratch/sources" scene 'name=Scene' 'exec omarchy-ttfx-layer'
make_source "$scratch/sources" amiga $'name=Amiga\non_battery=pause' 'exec sleep infinity'

get() { "$AMBIENT" battery --get; }
assert_eq "scenes run at 20 fps on battery by default" "$(get)" "20fps"
assert "a laptop has a charger" "$AMBIENT" battery --available
assert "an unknown mode is refused" bash -c "! '$AMBIENT' battery --set fast 2>/dev/null"
assert "so is an old name" bash -c "! '$AMBIENT' battery --set pause 2>/dev/null"
assert "full is a choice" "$AMBIENT" battery --set full
assert_eq "and it is kept" "$(get)" "full"
assert_eq "in its own file" "$(cat "$conf/battery.conf")" "on_battery=full"
assert "nothing runs, so nothing starts again" test ! -e "$HOME/systemd-run.calls"

# The resolution itself, from the supervisor's own functions.
eval "$(sed -n '/^settings_lines() {/,/^}/p; /^setting() {/,/^}/p; /^battery_mode_named() {/,/^}/p; /^battery_choice() {/,/^}/p; /^battery_mode() {/,/^}/p' "$AMBIENT")"
BATTERY_CONF=$conf/battery.conf CONFIG_DIR=$conf
assert_eq "the menu's choice holds for every source" "$(battery_mode amiga "$scratch/sources/amiga")" "full"
rm "$conf/battery.conf"
assert_eq "without one, a source's own on_battery stands" "$(battery_mode amiga "$scratch/sources/amiga")" "off"
printf 'on_battery=run\n' >"$conf/amiga.conf"
assert_eq "and the user's per-source setting over it" "$(battery_mode amiga "$scratch/sources/amiga")" "20fps"
assert_eq "a source that says nothing gets 20 fps" "$(battery_mode scene "$scratch/sources/scene")" "20fps"
rm "$conf/amiga.conf"

rm -r "$scratch/power/AC"
assert "a desktop has no charger to unplug" bash -c "! '$AMBIENT' battery --available"
mkdir -p "$scratch/power/AC"
echo Mains >"$scratch/power/AC/type"
echo 1 >"$scratch/power/AC/online"

# The supervisor, with Hyprland, OWE and the event stream stubbed.
events=$scratch/events
mkfifo "$events"
stub socat "exec cat '$events'"
stub inotifywait 'exec sleep infinity'
stub owe 'case $1 in status) echo "{\"manual_pause\":false}" ;; esac'
stub notify-send 'printf "%s\n" "$*" >>"$HOME/notes"'
stub omarchy-ttfx-layer 'echo "$TTFX_BG_ON_BATTERY $OMARCHY_AMBIENT_ON_BATTERY" >>"$HOME/scene-env"; exec sleep infinity'
monitors '[{"name":"eDP-1","width":2560,"height":1600,"scale":2,"focused":true,"dpmsStatus":true,"activeWorkspace":{"id":1}}]'
workspaces '[{"id":1,"hasfullscreen":false}]'
exec 9<>"$events"

program() { grep -lzx "OMARCHY_AMBIENT_SOURCE=$1" /proc/[0-9]*/environ 2>/dev/null | xargs -r grep -lzx "HOME=$HOME" 2>/dev/null | cut -d/ -f3 | head -n 1; }
state() { ps -o stat= -p "$(program "$1")" | cut -c1; }
notes() { cat "$HOME/notes" 2>/dev/null; }
supervise() {
  : >"$HOME/notes"
  "$AMBIENT" run "$@" >"$scratch/log" 2>&1 &
  supervisor=$!
  eventually bash -c "[[ -n \$(grep -lzx 'OMARCHY_AMBIENT_SOURCE=$1' /proc/[0-9]*/environ 2>/dev/null) ]]"
}
stop() {
  echo "background>>background" >&9
  eventually bash -c "! kill -0 $supervisor 2>/dev/null"
}
unplug() { echo 0 >"$scratch/power/AC/online"; echo tick >&9; }
plug() { echo 1 >"$scratch/power/AC/online"; echo tick >&9; }

# Turned off, on battery from the start: paused, and the user is told why.
printf 'on_battery=off\n' >"$conf/battery.conf"
unplug
supervise scene
assert "it is paused" eventually bash -c "grep -qx 'paused on eDP-1' '$scratch/log'"
assert "the user hears why" eventually bash -c "grep -q 'On battery: live background paused' '$HOME/notes'"
assert "the note names the scene" grep -q "Scene waits for the charger" "$HOME/notes"
assert "with Omarchy's logo" grep -q -- "-i $OMARCHY_PATH/icon.png" "$HOME/notes"
plug
assert "the charger resumes it" eventually bash -c "grep -qx 'resumed on eDP-1' '$scratch/log'"
assert "and says so" eventually bash -c "grep -q 'Plugged in: live background resumed' '$HOME/notes'"
assert_eq "the scene was told" "$(tail -n 1 "$HOME/scene-env")" "off off"
stop

# 20 fps: the scene keeps going, and a note says it slows down.
printf 'on_battery=20fps\n' >"$conf/battery.conf"
supervise scene
assert "starting on the charger says nothing" bash -c "sleep 0.5; [[ ! -s '$HOME/notes' ]]"
rm "$OMARCHY_PATH/icon.png"
unplug
assert "unplugging says it slows down" eventually bash -c "grep -q 'On battery: live background at 20 fps' '$HOME/notes'"
assert "with the themed logo where there is no file" grep -q -- "-i omarchy " "$HOME/notes"
assert_eq "and it keeps running" "$(state scene)" "S"
plug
assert "plugging in says it is back" eventually bash -c "grep -q 'Plugged in: live background at full speed' '$HOME/notes'"
stop
unplug
supervise scene
assert "starting on battery at 20 fps says nothing" bash -c "sleep 0.5; [[ ! -s '$HOME/notes' ]]"
stop
plug

# A program that is not a scene runs as it is at 20 fps, so there is nothing to say.
make_source "$scratch/sources" demo 'name=Demo' 'exec sleep infinity'
supervise demo
unplug
assert "a demo is not said to slow down" bash -c "sleep 0.5; [[ ! -s '$HOME/notes' ]]"
stop
plug

# Full: nothing changes on battery, and the scene is told to keep its pace.
printf 'on_battery=full\n' >"$conf/battery.conf"
supervise scene
unplug
assert "full stays quiet" bash -c "sleep 0.5; [[ ! -s '$HOME/notes' ]]"
assert_eq "and keeps running" "$(state scene)" "S"
assert_eq "the scene keeps its frame rate" "$(tail -n 1 "$HOME/scene-env")" "full full"
stop
plug

# Choosing while a background runs starts it again with the choice.
printf 'scene \n' >"$HOME/.local/state/omarchy/ambient"
stub systemctl 'printf "%s\n" "$*" >>"$HOME/systemctl.calls"; [[ $* == *is-active* ]]'
"$AMBIENT" battery --set off
assert "the running background starts again" grep -q 'supervise scene' "$HOME/systemd-run.calls"

finish_tests
