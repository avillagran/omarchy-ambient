#!/bin/bash

# Checks a live screensaver on a real Hyprland session, with nobody at the
# keyboard: it starts on every monitor, each kind of input ends it within a
# second, the first second of input does not, no key reaches the window under
# it, and nothing is left behind. Then it runs it again and again.
#
#   test/hardware/screensaver-check.sh <source> [cycles]
#
# Needs omarchy-ambient on PATH, wtype, and make -C test/hardware for the
# virtual pointer. It draws on the screen: run it where nobody is working.

source_id=${1:?Usage: screensaver-check.sh <source> [cycles]}
cycles=${2:-10}
here=$(cd "$(dirname "$0")" && pwd)
vpointer=$here/../../build/hardware/vpointer
[[ -x $vpointer ]] || { echo "Run make -C test/hardware first" >&2; exit 1; }
command -v wtype >/dev/null || { echo "wtype is needed" >&2; exit 1; }

failures=0
check() {
  if "${@:2}"; then echo "ok   $1"; else echo "FAIL $1"; failures=$((failures + 1)); fi
}

layers() { hyprctl layers -j | jq --arg ns "omarchy-ambient-$source_id" '[.[] | .levels["3"][]? | select(.namespace == $ns)] | length'; }
monitors() { hyprctl monitors -j | jq length; }
covered() { [[ $(layers) -ge $(monitors) ]]; }
clean() {
  [[ $(hyprctl layers -j | jq --arg ns "omarchy-ambient-$source_id" '[.. | objects | select(.namespace? == $ns)] | length') == 0 ]] &&
    ! hyprctl layers -j | jq -e '[.. | objects | select(.pid? == -1)] | length > 0' >/dev/null &&
    [[ $(hyprctl getoption cursor:invisible | head -n 1) == *false ]] &&
    ! grep -qs . "${XDG_RUNTIME_DIR}/omarchy-ambient/screensaver"
}
wait_for() { local i; for ((i = 0; i < $2 * 10; i++)); do "$1" && return 0; sleep 0.1; done; return 1; }
running() { kill -0 "$saver" 2>/dev/null; }
stopped() { ! running; }

start() {
  omarchy-ambient screensaver "$source_id" >>"${TMPDIR:-/tmp}/screensaver-check.log" 2>&1 &
  saver=$!
  wait_for covered 30
}

# Milliseconds from the input to the screensaver being gone.
dismissed_by() {
  local begin
  begin=$(date +%s%N)
  "$@"
  wait_for stopped 3 || return 1
  echo "     ended $(( ($(date +%s%N) - begin) / 1000000 )) ms after the input"
}

for input in motion click scroll key; do
  check "it covers every monitor ($input)" start
  sleep 3
  if [[ $input == key ]]; then
    check "a key ends it" dismissed_by wtype -k space
  else
    check "a $input ends it" dismissed_by "$vpointer" "$input"
  fi
  check "nothing is left after a $input" wait_for clean 5
done

check "it starts again" start
sleep 0.3
"$vpointer" motion
sleep 2
check "input in the first second does not end it" running
check "input after that does" dismissed_by "$vpointer" motion
wait_for clean 5

# A terminal under the screensaver records what reaches it.
keys=$(mktemp)
hyprctl dispatch "hl.dsp.exec_cmd([[foot -a screensaver-check sh -c 'stty -icanon; cat > $keys']])" >/dev/null
sleep 2
start
sleep 3
wtype "secret"
wait_for stopped 3
sleep 0.5
check "no key reaches the window under it" test ! -s "$keys"
pkill -f 'foot -a screensaver-check'
rm -f "$keys"
wait_for clean 5

for ((i = 1; i <= cycles; i++)); do
  if ! start; then check "cycle $i starts" false; continue; fi
  sleep $((2 + RANDOM % 4))
  case $((i % 4)) in
    0) "$vpointer" motion ;;
    1) "$vpointer" click ;;
    2) "$vpointer" scroll ;;
    3) wtype -k space ;;
  esac
  wait_for stopped 3 && wait_for clean 5 || check "cycle $i ends clean" false
done
check "$cycles more cycles end clean" test "$failures" -eq 0

((failures == 0)) || { echo "$failures failed"; exit 1; }
