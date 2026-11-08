#!/bin/bash

# When a live background counts as seen: per output, and never while locked,
# under the screensaver or on battery. And when a screensaver does.

source "$(dirname "$0")/lib.sh"

eval "$(sed -n '/^on_battery() {/,/^}/p; /^screensaver_running() {/,/^}/p; /^visible_outputs() {/,/^}/p' "$AMBIENT")"
POWER_SUPPLIES=$OMARCHY_AMBIENT_POWER_SUPPLIES
SCREENSAVER_LOCK=$XDG_RUNTIME_DIR/screensaver
battery_mode=off placement=background

visible() { visible_outputs | tr '\n' ' '; }

two='[{"name":"eDP-1","dpmsStatus":true,"activeWorkspace":{"id":1}},{"name":"DP-1","dpmsStatus":true,"activeWorkspace":{"id":2}}]'
monitors "$two"

workspaces '[{"id":1,"hasfullscreen":false},{"id":2,"hasfullscreen":false}]'
assert_eq "every output shows the background" "$(visible)" "eDP-1 DP-1 "

workspaces '[{"id":1,"hasfullscreen":true},{"id":2,"hasfullscreen":false}]'
assert_eq "a fullscreen window hides only its own output" "$(visible)" "DP-1 "

workspaces '[{"id":1,"hasfullscreen":true},{"id":2,"hasfullscreen":true}]'
assert_eq "fullscreen everywhere hides every output" "$(visible)" ""

workspaces '[{"id":1,"hasfullscreen":false},{"id":2,"hasfullscreen":false}]'
monitors '[{"name":"eDP-1","dpmsStatus":false,"activeWorkspace":{"id":1}},{"name":"DP-1","dpmsStatus":true,"activeWorkspace":{"id":2}}]'
assert_eq "an output that is off is hidden" "$(visible)" "DP-1 "

monitors '[{"name":"eDP-1","dpmsStatus":true,"activeWorkspace":{"id":1},"solitaryBlockedBy":["LOCK"]},{"name":"DP-1","dpmsStatus":true,"activeWorkspace":{"id":2}}]'
assert_eq "a locked session hides everything" "$(visible)" ""

monitors "$two"
echo 0 >"$scratch/power/AC/online"
assert_eq "running on battery hides everything when it is turned off then" "$(visible)" ""

battery_mode=20fps
assert_eq "at 20 fps it keeps going on battery" "$(visible)" "eDP-1 DP-1 "
battery_mode=full
assert_eq "and at full speed too" "$(visible)" "eDP-1 DP-1 "
battery_mode=off

rm -r "$scratch/power/AC"
assert_eq "a computer without a charger is never on battery" "$(visible)" "eDP-1 DP-1 "

echo $$ >"$SCREENSAVER_LOCK"
assert_eq "a running screensaver hides everything" "$(visible)" ""
sleep infinity &
echo $! >"$SCREENSAVER_LOCK"
kill -KILL $!
wait $! 2>/dev/null
assert_eq "a screensaver that died hides nothing" "$(visible)" "eDP-1 DP-1 "
: >"$SCREENSAVER_LOCK"
assert_eq "an ended screensaver hides nothing" "$(visible)" "eDP-1 DP-1 "

placement=screensaver
workspaces '[{"id":1,"hasfullscreen":true},{"id":2,"hasfullscreen":false}]'
assert_eq "a screensaver covers fullscreen windows too" "$(visible)" "eDP-1 DP-1 "
monitors '[{"name":"eDP-1","dpmsStatus":false,"activeWorkspace":{"id":1}},{"name":"DP-1","dpmsStatus":true,"activeWorkspace":{"id":2}}]'
assert_eq "a screensaver is hidden on an output that is off" "$(visible)" "DP-1 "
monitors '[{"name":"eDP-1","dpmsStatus":true,"activeWorkspace":{"id":1},"solitaryBlockedBy":["LOCK"]},{"name":"DP-1","dpmsStatus":true,"activeWorkspace":{"id":2}}]'
assert_eq "a screensaver learns the session locked" "$(visible)" "locked "

finish_tests
