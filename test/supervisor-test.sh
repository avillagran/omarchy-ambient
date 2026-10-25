#!/bin/bash

# The supervisor end to end, with Hyprland, OWE and the event stream stubbed:
# one program per output, paused where it can't be seen, restarted when it
# dies, and everything undone when an ordinary background is set.

source "$(dirname "$0")/lib.sh"

export OMARCHY_BG_LIVE_PATH=$scratch/sources
events=$scratch/events
mkfifo "$events"

stub systemctl 'exit 0'
stub socat "exec cat '$events'"
stub inotifywait 'exec sleep infinity'
stub owe "
case \$1 in
  status) echo '{\"manual_pause\":false}' ;;
  *) echo \"\$1\" >>'$scratch/owe.log' ;;
esac"

monitors '[{"name":"eDP-1","width":2560,"height":1600,"scale":2,"focused":true,"dpmsStatus":true,"activeWorkspace":{"id":1}},{"name":"DP-1","width":3840,"height":2160,"scale":1.5,"focused":false,"dpmsStatus":true,"activeWorkspace":{"id":2}}]'
workspaces '[{"id":1,"hasfullscreen":false},{"id":2,"hasfullscreen":false}]'

make_source "$scratch/sources" fake $'name=Fake\ngreeting=hello' "
echo \"\$OMARCHY_BG_LIVE_OUTPUT \$OMARCHY_BG_LIVE_WIDTH \$OMARCHY_BG_LIVE_SCALE \$OMARCHY_BG_LIVE_SETTING_GREETING \$1 \$OMARCHY_BG_LIVE_DATA\" >>'$scratch/runs'
exec sleep infinity"

# The program covering an output, found by the environment it was given.
program_on() {
  grep -lzx "OMARCHY_BG_LIVE_OUTPUT=$1" /proc/[0-9]*/environ 2>/dev/null | cut -d/ -f3 | head -n 1
}
state_of() { ps -o stat= -p "$(program_on "$1")" | cut -c1; }
logged() { grep -qx "$1" "$scratch/log"; }

exec 9<>"$events"
"$BG_LIVE" run fake mychoice >"$scratch/log" 2>&1 &
supervisor=$!

assert "a program starts on each output" eventually bash -c "[[ \$(cat '$scratch/runs' 2>/dev/null | wc -l) == 2 ]]"
assert_eq "each program learns its output, size and settings" "$(sort "$scratch/runs")" \
  "DP-1 3840 1.5 hello mychoice $XDG_DATA_HOME/omarchy-bg-live/fake
eDP-1 2560 2 hello mychoice $XDG_DATA_HOME/omarchy-bg-live/fake"
assert_eq "OWE is paused" "$(cat "$scratch/owe.log")" "pause"
assert_eq "the status names the source and choice" "$(cat "$HOME/.local/state/omarchy/bg-live")" "fake mychoice"

workspaces '[{"id":1,"hasfullscreen":true},{"id":2,"hasfullscreen":false}]'
echo "fullscreen>>1" >&9
assert "a fullscreen window pauses the program on its output" eventually logged "paused on eDP-1"
assert_eq "that program is stopped" "$(state_of eDP-1)" "T"
assert_eq "the other output's program keeps running" "$(state_of DP-1)" "S"

workspaces '[{"id":1,"hasfullscreen":false},{"id":2,"hasfullscreen":false}]'
echo "fullscreen>>0" >&9
assert "leaving fullscreen resumes it" eventually logged "resumed on eDP-1"

kill "$(program_on DP-1)"
assert "a program that dies is restarted" bash -c "for i in {1..70}; do grep -q 'restarting on DP-1' '$scratch/log' && exit 0; sleep 0.1; done; exit 1"

echo "monitorremoved>>DP-1" >&9
assert "an unplugged output's program ends" eventually logged "ended on DP-1"

monitors '[{"name":"eDP-1","width":2560,"height":1600,"scale":2,"focused":true,"dpmsStatus":true,"activeWorkspace":{"id":1}},{"name":"HDMI-A-1","width":1920,"height":1080,"scale":1,"focused":false,"dpmsStatus":true,"activeWorkspace":{"id":3}}]'
echo "monitoradded>>HDMI-A-1" >&9
assert "a new output gets its own program" eventually logged "started fake mychoice on HDMI-A-1"

echo "background>>background" >&9
assert "an ordinary background ends the live one" eventually bash -c "! kill -0 $supervisor 2>/dev/null"
assert "the supervisor says it stopped" logged "stopped"
assert_eq "OWE is resumed" "$(tail -n 1 "$scratch/owe.log")" "resume"
assert "the status file is gone" test ! -e "$HOME/.local/state/omarchy/bg-live"
assert "no program is left behind" bash -c "! grep -qszx 'OMARCHY_BG_LIVE_SOURCE=fake' /proc/[0-9]*/environ"

finish_tests
