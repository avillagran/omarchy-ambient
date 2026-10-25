# Shared by the tests: a scratch home, stub commands, and assertions.

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BG_LIVE=$ROOT/bin/omarchy-bg-live
failures=0

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

export HOME=$scratch/home XDG_CONFIG_HOME=$scratch/home/.config XDG_DATA_HOME=$scratch/home/.local/share
export OMARCHY_BG_LIVE_POWER_SUPPLIES=$scratch/power
mkdir -p "$HOME/.local/state/omarchy/current" "$scratch/stubs" "$scratch/power/AC"
echo Mains >"$scratch/power/AC/type"
echo 1 >"$scratch/power/AC/online"
export PATH="$scratch/stubs:$PATH"

stub() {
  printf '#!/bin/bash\n%s\n' "$2" >"$scratch/stubs/$1"
  chmod +x "$scratch/stubs/$1"
}

# hyprctl answers from monitors.json and workspaces.json in the scratch dir.
stub hyprctl '
case "$*" in
  *--batch*) cat "'"$scratch"'/monitors.json" "'"$scratch"'/workspaces.json" ;;
  *monitors*) cat "'"$scratch"'/monitors.json" ;;
esac'

monitors() { echo "$1" >"$scratch/monitors.json"; }
workspaces() { echo "$1" >"$scratch/workspaces.json"; }

# A source in its own directory: source <dir> <id> <source.conf> <run>
make_source() {
  mkdir -p "$1/$2"
  echo "$3" >"$1/$2/source.conf"
  printf '#!/bin/bash\n%s\n' "$4" >"$1/$2/run"
  chmod +x "$1/$2/run"
}

assert() {
  local name=$1
  shift
  if "$@"; then
    echo "ok   $name"
  else
    echo "FAIL $name"
    failures=$((failures + 1))
  fi
}

assert_eq() {
  if [[ $2 == "$3" ]]; then
    echo "ok   $1"
  else
    printf 'FAIL %s\n  expected: %q\n  actual:   %q\n' "$1" "$3" "$2"
    failures=$((failures + 1))
  fi
}

# Waits up to five seconds for a command to succeed.
eventually() {
  local i
  for ((i = 0; i < 50; i++)); do
    "$@" && return 0
    sleep 0.1
  done
  return 1
}

finish_tests() {
  ((failures == 0)) || { echo "$failures failed"; exit 1; }
}
