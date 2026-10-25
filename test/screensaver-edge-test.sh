#!/bin/bash

# The screensaver's less common paths: monitors coming and going while it
# runs, a dismiss helper that dies, a source that keeps failing, being told to
# stop, a choice, a source that can't be prepared, and what check accepts.
# Every way out has to give the cursor back and release the lock.

source "$(dirname "$0")/lib.sh"

export OMARCHY_AMBIENT_PATH=$scratch/sources OMARCHY_AMBIENT_DISMISS=$scratch/stubs/dismiss
events=$scratch/events
mkfifo "$events" "$scratch/activity" "$scratch/die"

stub systemctl 'exit 1'
stub socat "exec cat '$events'"
stub inotifywait 'exec sleep infinity'
# Ready at once; reports activity, or dies without a word, when told to.
stub dismiss "echo ready
read -r how < <(cat '$scratch/activity' & cat '$scratch/die' | sed 's/^/die/')
[[ \$how == die* ]] && exit 1
echo activity"

one='[{"name":"eDP-1","width":2560,"height":1600,"scale":2,"focused":true,"dpmsStatus":true,"activeWorkspace":{"id":1}}]'
two='[{"name":"eDP-1","width":2560,"height":1600,"scale":2,"focused":true,"dpmsStatus":true,"activeWorkspace":{"id":1}},{"name":"HDMI-A-1","width":1920,"height":1080,"scale":1,"focused":false,"dpmsStatus":true,"activeWorkspace":{"id":2}}]'
monitors "$one"
workspaces '[{"id":1,"hasfullscreen":false},{"id":2,"hasfullscreen":false}]'

make_source "$scratch/sources" demo $'name=Demo\nplacements=screensaver' "
echo \"\$OMARCHY_AMBIENT_OUTPUT \$1\" >>'$scratch/runs'
exec sleep infinity"
make_source "$scratch/sources" broken $'name=Broken\nplacements=screensaver' 'exit 3'
make_source "$scratch/sources" unready $'name=Unready\nplacements=screensaver' 'exec sleep infinity'
printf '#!/bin/bash\necho "no network" >&2\nexit 1\n' >"$scratch/sources/unready/prepare"
chmod +x "$scratch/sources/unready/prepare"

exec 9<>"$events"
lock=$XDG_RUNTIME_DIR/omarchy-ambient/screensaver
logged() { grep -q "$1" "$scratch/log"; }
gone() { ! kill -0 "$1" 2>/dev/null; }
alive() { grep -lszx "OMARCHY_AMBIENT_SOURCE=$1" /proc/[0-9]*/environ | grep -q .; }
cursor_back() { [[ $(tail -n 1 "$scratch/hyprctl.log") == *"invisible = false"* ]]; }
start() { : >"$scratch/runs"; : >"$scratch/hyprctl.log"; "$AMBIENT" screensaver "$@" >"$scratch/log" 2>&1 & saver=$!; }
ended() { eventually gone "$saver"; }

# Monitors

start demo
assert "it covers the one monitor" eventually bash -c "[[ \$(wc -l <'$scratch/runs') == 1 ]]"
monitors "$two"
echo "monitoradded>>HDMI-A-1" >&9
assert "a monitor plugged in while it runs is covered too" eventually grep -q "^HDMI-A-1 " "$scratch/runs"
echo "monitorremoved>>HDMI-A-1" >&9
assert "an unplugged monitor's program ends" eventually logged "ended on HDMI-A-1"
monitors "$one"
echo >"$scratch/activity"
assert "activity still ends it" ended
assert "nothing is left" eventually bash -c "$(declare -f alive); ! alive demo"

# The helper dying

start demo
eventually test -s "$scratch/runs"
echo >"$scratch/die"
assert "a screensaver whose dismiss helper dies ends" ended
assert "and says so" logged "the dismiss helper ended"
assert "the cursor comes back" cursor_back
assert_eq "the lock is released" "$(cat "$lock")" ""
assert "nothing is left" eventually bash -c "$(declare -f alive); ! alive demo"

# A source that keeps failing

start broken
assert "a source that keeps failing is given up on" bash -c "for i in {1..150}; do kill -0 $saver 2>/dev/null || exit 0; sleep 0.1; done; exit 1"
wait "$saver"
assert_eq "the screensaver exits 1 then" "$?" "1"
assert "the cursor comes back" cursor_back
assert_eq "the lock is released" "$(cat "$lock")" ""

# SIGTERM

start demo
eventually test -s "$scratch/runs"
kill -TERM "$saver"
assert "SIGTERM ends it" ended
assert "the cursor comes back" cursor_back
assert_eq "the lock is released" "$(cat "$lock")" ""
assert "nothing is left" eventually bash -c "$(declare -f alive); ! alive demo"

# A choice

start demo second-demo
assert "the choice reaches run" eventually grep -qx "eDP-1 second-demo" "$scratch/runs"
echo >"$scratch/activity"
ended

# Preparing

"$AMBIENT" screensaver --set demo
"$AMBIENT" screensaver --set unready >"$scratch/log" 2>&1
assert "a source that can't be prepared is not selected" bash -c "[[ \$('$AMBIENT' screensaver --get) == demo ]]"
assert "the user is told why" logged "could not be prepared"
start unready
assert "nor run" ended
assert "and covers nothing" bash -c "$(declare -f alive); ! alive unready"
assert_eq "the lock is released" "$(cat "$lock")" ""

# What check accepts

make_source "$scratch/bad" odd $'name=Odd\nplacements=background wallpaper\ninput=keyboard' 'exit 0'
assert_eq "check names bad placements and input" "$("$AMBIENT" check "$scratch/bad/odd" 2>&1)" \
  "odd: placements has wallpaper, not background or screensaver
odd: input is keyboard, not dismiss or own"
assert_eq "check accepts both placements" "$("$AMBIENT" check "$scratch/sources/demo" 2>&1)" "demo: ok"

# Usage

assert "an unknown option fails" bash -c "! '$AMBIENT' screensaver --bogus 2>/dev/null"
assert "--set needs a source" bash -c "! '$AMBIENT' screensaver --set 2>/dev/null"
assert "an unknown source fails" bash -c "! '$AMBIENT' screensaver nosuch 2>/dev/null"

finish_tests
