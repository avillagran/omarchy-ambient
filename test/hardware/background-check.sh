#!/bin/bash

# Checks a live background on a real Hyprland session: it draws on the bottom
# layer of every monitor, freezes under a fullscreen window and under the
# screensaver and comes back after, and an ordinary background ends it with
# nothing left behind.
#
#   test/hardware/background-check.sh <source> [choice] [screensaver-source]
#
# Needs omarchy-ambient installed (it runs as a user unit), wtype, and
# make -C test/hardware. It draws on the screen and changes the background
# back and forth: run it where nobody is working.

source_id=${1:?Usage: background-check.sh <source> [choice] [screensaver-source]}
choice=${2:-}
saver_id=${3:-$source_id}
here=$(cd "$(dirname "$0")" && pwd)
vpointer=$here/../../build/hardware/vpointer
[[ -x $vpointer ]] || { echo "Run make -C test/hardware first" >&2; exit 1; }

failures=0
check() {
  if "${@:2}"; then echo "ok   $1"; else echo "FAIL $1"; failures=$((failures + 1)); fi
}
wait_for() { local i; for ((i = 0; i < $2 * 10; i++)); do "$1" && return 0; sleep 0.1; done; return 1; }

namespace=omarchy-ambient-$source_id
on_bottom() { [[ $(hyprctl layers -j | jq --arg ns "$namespace" '[.[] | .levels["1"][]? | select(.namespace == $ns)] | length') -ge $(hyprctl monitors -j | jq length) ]]; }
no_layer() { [[ $(hyprctl layers -j | jq --arg ns "$namespace" '[.. | objects | select(.namespace? == $ns)] | length') == 0 ]]; }
# The programs drawing it, not the supervisor: only they get an output and
# a runtime directory. S running, T stopped.
programs() {
  local environ
  for environ in /proc/[0-9]*/environ; do
    grep -qszx "OMARCHY_AMBIENT_SOURCE=$source_id" "$environ" &&
      grep -qszx "OMARCHY_AMBIENT_PLACEMENT=background" "$environ" &&
      grep -qsz "^OMARCHY_AMBIENT_RUNTIME=" "$environ" && echo "${environ//[^0-9]/}"
  done
}
all_stopped() { local p any=false; for p in $(programs); do any=true; [[ $(ps -o stat= -p "$p") == T* ]] || return 1; done; $any; }
none_stopped() { local p any=false; for p in $(programs); do any=true; [[ $(ps -o stat= -p "$p") == T* ]] && return 1; done; $any; }
nothing_left() { [[ -z $(programs) ]] && no_layer && [[ $(omarchy-ambient status) == none ]]; }

background=$(readlink ~/.local/state/omarchy/current/background)

omarchy-ambient start "$source_id" $choice
check "it draws on the bottom layer of every monitor" wait_for on_bottom 30
check "the status names it" test "$(omarchy-ambient status | cut -d ' ' -f 1)" == "$source_id"

hyprctl dispatch "hl.dsp.exec_cmd([[foot -a background-check sleep 60]])" >/dev/null
sleep 1.5
hyprctl dispatch 'hl.dsp.window.fullscreen({ action = "set", mode = "fullscreen" })' >/dev/null
check "a fullscreen window freezes it" wait_for all_stopped 8
pkill -f 'foot -a background-check'
check "closing the window brings it back" wait_for none_stopped 8

omarchy-ambient screensaver "$saver_id" >/dev/null 2>&1 &
saver=$!
check "the screensaver freezes it" wait_for all_stopped 10
sleep 2
"$vpointer" motion
saver_gone() { ! kill -0 "$saver" 2>/dev/null; }
wait_for saver_gone 5
check "it comes back when the screensaver ends" wait_for none_stopped 10

omarchy-theme-bg-set "$background"
check "an ordinary background ends it, and nothing is left" wait_for nothing_left 10

((failures == 0)) || { echo "$failures failed"; exit 1; }
