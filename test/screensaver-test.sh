#!/bin/bash

# The screensaver placement end to end, with Hyprland, the event stream and
# the dismiss helper stubbed: choosing one, running it over every output with
# the cursor hidden, one at a time, ending it on activity or on lock, and
# freezing a live background while it runs.

source "$(dirname "$0")/lib.sh"

export OMARCHY_AMBIENT_PATH=$scratch/sources OMARCHY_AMBIENT_DISMISS=$scratch/stubs/dismiss
events=$scratch/events
mkfifo "$events" "$scratch/activity" "$scratch/background-events"

stub systemctl 'exit 1'
# Each supervisor reads its own stream: EVENTS names it.
stub socat "exec cat \"\${EVENTS:-$events}\""
stub inotifywait 'exec sleep infinity'
# The dismiss helper is ready at once and reports activity when told to.
stub dismiss "echo ready; read -r _ <'$scratch/activity'; echo activity"

monitors '[{"name":"eDP-1","width":2560,"height":1600,"scale":2,"focused":true,"dpmsStatus":true,"activeWorkspace":{"id":1}},{"name":"DP-1","width":3840,"height":2160,"scale":1.5,"focused":false,"dpmsStatus":true,"activeWorkspace":{"id":2}}]'
workspaces '[{"id":1,"hasfullscreen":true},{"id":2,"hasfullscreen":false}]'

make_source "$scratch/sources" demo $'name=Demo\nplacements=background screensaver' "
echo \"\$OMARCHY_AMBIENT_OUTPUT \$OMARCHY_AMBIENT_PLACEMENT \$OMARCHY_AMBIENT_LAYER \$OMARCHY_AMBIENT_KEYBOARD \$1\" >>'$scratch/runs'
exec sleep infinity"
make_source "$scratch/sources" wallpaper $'name=Wallpaper' 'exec sleep infinity'
make_source "$scratch/sources" game $'name=Game\nplacements=screensaver\ninput=own' "
echo started >>'$scratch/game'
read -r _ <'$scratch/activity'"

program_on() {
  grep -lzx "OMARCHY_AMBIENT_OUTPUT=$1" /proc/[0-9]*/environ 2>/dev/null | cut -d/ -f3 | head -n 1
}
logged() { grep -qx "$1" "$2"; }
gone() { ! kill -0 "$1" 2>/dev/null; }
no_program_of() { ! grep -qszx "OMARCHY_AMBIENT_SOURCE=$1" /proc/[0-9]*/environ; }

# Choosing one

assert_eq "the stock screensaver is selected at first" "$("$AMBIENT" screensaver --get)" "text"
"$AMBIENT" screensaver --set demo
assert_eq "a source can be selected" "$("$AMBIENT" screensaver --get)" "demo"
assert_eq "the selection is kept in screensaver.conf" "$(cat "$XDG_CONFIG_HOME/omarchy/ambient/screensaver.conf")" "source=demo"
assert "a background-only source can't be selected" bash -c "! '$AMBIENT' screensaver --set wallpaper 2>/dev/null"
assert_eq "and the selection stays" "$("$AMBIENT" screensaver --get)" "demo"
assert_eq "the screensaver list has only screensaver sources, and the selected one" \
  "$("$AMBIENT" list screensaver | cut -f1-3)" $'Demo\tdemo\tdemo\nGame\tgame\tdemo'
assert_eq "the background list leaves out screensaver-only sources" "$("$AMBIENT" list | cut -f2 | tr '\n' ' ')" "demo wallpaper "
"$AMBIENT" screensaver --set text
assert_eq "text restores the stock screensaver" "$("$AMBIENT" screensaver --get)" "text"
assert "with the stock one selected there is nothing to run" bash -c "! '$AMBIENT' screensaver 2>/dev/null"
"$AMBIENT" screensaver --set demo

# Running and dismissing it

exec 9<>"$events"
"$AMBIENT" screensaver >"$scratch/log" 2>&1 &
saver=$!

assert "it starts on every output" eventually bash -c "[[ \$(cat '$scratch/runs' 2>/dev/null | wc -l) == 2 ]]"
assert_eq "each program learns it is a screensaver, over everything with the keyboard" "$(sort "$scratch/runs")" \
  $'DP-1 screensaver overlay exclusive \neDP-1 screensaver overlay exclusive '
assert "the cursor is hidden" grep -q 'invisible = true' "$scratch/hyprctl.log"
assert_eq "the lock holds its pid" "$(cat "$XDG_RUNTIME_DIR/omarchy-ambient/screensaver")" "$saver"

"$AMBIENT" screensaver demo >/dev/null 2>&1
assert_eq "a second one exits at once and starts nothing" "$(wc -l <"$scratch/runs")" "2"

echo "fullscreen>>1" >&9
sleep 0.5
assert_eq "a fullscreen window doesn't pause it" "$(ps -o stat= -p "$(program_on eDP-1)" | cut -c1)" "S"

echo >"$scratch/activity"
assert "activity ends it" eventually gone "$saver"
assert "it says why" logged "the user is back" "$scratch/log"
assert "the cursor is restored" grep -q 'invisible = false' "$scratch/hyprctl.log"
assert "no program is left behind" eventually no_program_of demo
assert_eq "the lock is released" "$(cat "$XDG_RUNTIME_DIR/omarchy-ambient/screensaver")" ""

# Locking the session

: >"$scratch/runs"
"$AMBIENT" screensaver demo >"$scratch/log" 2>&1 &
saver=$!
assert "a preview names its source" eventually bash -c "[[ \$(cat '$scratch/runs' | wc -l) == 2 ]]"
monitors '[{"name":"eDP-1","width":2560,"height":1600,"scale":2,"focused":true,"dpmsStatus":true,"activeWorkspace":{"id":1},"solitaryBlockedBy":["LOCK"]}]'
assert "locking the session ends it" bash -c "for i in {1..50}; do kill -0 $saver 2>/dev/null || exit 0; sleep 0.1; done; exit 1"
assert "it gives way to the lock screen" logged "the session locked" "$scratch/log"
assert "nothing keeps running under the lock" eventually no_program_of demo
monitors '[{"name":"eDP-1","width":2560,"height":1600,"scale":2,"focused":true,"dpmsStatus":true,"activeWorkspace":{"id":1}},{"name":"DP-1","width":3840,"height":2160,"scale":1.5,"focused":false,"dpmsStatus":true,"activeWorkspace":{"id":2}}]'

# Without a way to end it, it never starts

: >"$scratch/runs"
stub broken 'echo "no ext_idle_notify_v1" >&2; exit 1'
OMARCHY_AMBIENT_DISMISS=$scratch/stubs/broken "$AMBIENT" screensaver demo >"$scratch/log" 2>&1
assert_eq "a screensaver without its dismiss helper fails" "$?" "1"
assert_eq "and covers nothing" "$(cat "$scratch/runs")" ""

# A source that handles input itself

"$AMBIENT" screensaver game >"$scratch/log" 2>&1 &
saver=$!
assert "input=own runs without the dismiss helper" eventually test -s "$scratch/game"
echo >"$scratch/activity"
assert "it ends when the program exits 0" bash -c "for i in {1..50}; do kill -0 $saver 2>/dev/null || exit 0; sleep 0.1; done; exit 1"
assert "and says so" grep -q '^ended by ' "$scratch/log"

# A live background under it

exec 7<>"$scratch/background-events"
EVENTS=$scratch/background-events "$AMBIENT" run demo >"$scratch/background-log" 2>&1 &
background=$!
assert "a live background runs" eventually logged "started demo on DP-1" "$scratch/background-log"

"$AMBIENT" screensaver demo >"$scratch/log" 2>&1 &
saver=$!
eventually bash -c "grep -q 'started demo on' '$scratch/log'"
echo "screensaver>>screensaver" >&7
assert "is frozen while the screensaver runs" eventually logged "paused on DP-1" "$scratch/background-log"
echo >"$scratch/activity"
eventually gone "$saver"
echo "screensaver>>screensaver" >&7
assert "and resumed afterwards" eventually logged "resumed on DP-1" "$scratch/background-log"
echo "background>>background" >&7
eventually gone "$background"

finish_tests
