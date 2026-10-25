#!/bin/bash

# Tries the live screensaver through Omarchy's real idle cycle on a test
# machine, without touching /usr:
#
#   trial-idle.sh install <omarchy-ambient checkout>   clone the idle service so it
#                                                     runs a pinned launcher that
#                                                     delegates to omarchy-ambient
#   trial-idle.sh timeouts <screensaver> <lock>       shorter idle timeouts, in seconds
#   trial-idle.sh undo                                put everything back
#
# The idle service runs omarchy-launch-screensaver through bash -lc, where
# ~/.local/bin comes after /usr/bin, so a user copy of the launcher is never
# found. The clone calls the pinned copy by its full path instead. This is the
# approach omarchy-amiga's installer takes; it is for test machines only.

set -euo pipefail

TRIAL=$HOME/.cache/ambient-trial
ID=ambient-trial.idle
PLUGIN=$HOME/.config/omarchy/plugins/$ID
LAUNCHER=$HOME/.local/bin/omarchy-launch-screensaver
SHELL_JSON=$HOME/.config/omarchy/shell.json
MARK="# omarchy-ambient trial: test/hardware/trial-idle.sh undo removes this file"
export OMARCHY_PATH=${OMARCHY_PATH:-/usr/share/omarchy}

install_trial() {
  local checkout=${1:?the omarchy-ambient checkout to run}
  checkout=$(realpath "$checkout")
  [[ -x $checkout/bin/omarchy-ambient ]] || { echo "No omarchy-ambient in $checkout" >&2; exit 1; }
  [[ ! -e $PLUGIN ]] || { echo "$PLUGIN exists; undo first" >&2; exit 1; }
  [[ ! -e $LAUNCHER ]] || grep -qF "$MARK" "$LAUNCHER" || { echo "$LAUNCHER is not ours" >&2; exit 1; }

  mkdir -p "$TRIAL"
  [[ -e $TRIAL/shell.json.orig ]] || cp -a "$SHELL_JSON" "$TRIAL/shell.json.orig"

  # The stock launcher, delegating to omarchy-ambient like the proposed
  # upstream change (docs/omarchy-integration.md).
  python3 - "$OMARCHY_PATH/bin/omarchy-launch-screensaver" "$LAUNCHER" "$checkout/bin" "$MARK" <<'PY'
import sys
source, target, bin_dir, mark = sys.argv[1:]
text = open(source).read()
anchor = 'if omarchy-toggle-enabled screensaver-off && [[ $1 != "force" ]]; then\n  exit 1\nfi\n'
if anchor not in text:
    raise SystemExit('the stock launcher changed; update trial-idle.sh')
block = anchor + '''
# A live screensaver from omarchy-ambient draws its own layers and ends on
# activity, so it needs none of the terminal handling below.
if [[ ${2:-} != text ]] && command -v omarchy-ambient >/dev/null &&
  [[ $(omarchy-ambient screensaver --get 2>/dev/null) != text ]]; then
  exec omarchy-ambient screensaver
fi
'''
text = text.replace(anchor, block)
lines = text.split('\n')
lines[1:1] = [mark, 'PATH="%s:$PATH"' % bin_dir]
open(target, 'w').write('\n'.join(lines))
PY
  chmod 755 "$LAUNCHER"

  local stage
  stage=$(mktemp -d "${PLUGIN%/*}/.trial.XXXXXX")
  cp -aL "$OMARCHY_PATH/shell/plugins/services/idle/." "$stage/"
  grep -q '|| omarchy-launch-screensaver")' "$stage/Service.qml" || { rm -rf "$stage"; echo "the idle service changed; update trial-idle.sh" >&2; exit 1; }
  sed -i 's#|| omarchy-launch-screensaver")#|| \\"$HOME/.local/bin/omarchy-launch-screensaver\\"")#' "$stage/Service.qml"
  jq --arg id "$ID" '.id = $id | .name = "Idle (omarchy-ambient trial)" | .omarchy = ((.omarchy // {}) + {clonedFrom: "omarchy.idle"})' \
    "$stage/manifest.json" >"$stage/manifest.json.tmp"
  mv "$stage/manifest.json.tmp" "$stage/manifest.json"
  mv "$stage" "$PLUGIN"

  omarchy-shell shell rescanPlugins >/dev/null
  sleep 1
  omarchy plugin enable "$ID" >/dev/null
  echo "installed; the idle service now runs $LAUNCHER"
}

timeouts() {
  [[ -e $TRIAL/shell.json.orig ]] || { echo "install first" >&2; exit 1; }
  jq --argjson s "$1" --argjson l "$2" '.idle.screensaver = $s | .idle.lock = $l' "$SHELL_JSON" >"$SHELL_JSON.tmp"
  mv "$SHELL_JSON.tmp" "$SHELL_JSON"
}

undo() {
  if [[ -d $PLUGIN ]]; then
    omarchy plugin disable "$ID" >/dev/null 2>&1 || true
    rm -rf "$PLUGIN"
  fi
  [[ -e $LAUNCHER ]] && grep -qF "$MARK" "$LAUNCHER" && rm -f "$LAUNCHER"
  if [[ -e $TRIAL/shell.json.orig ]]; then
    cp -a "$TRIAL/shell.json.orig" "$SHELL_JSON"
    rm -f "$TRIAL/shell.json.orig"
  fi
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  sleep 1
  omarchy plugin enable omarchy.idle >/dev/null 2>&1 || true
  echo "undone; the stock idle service is back"
}

case ${1:-} in
  install) install_trial "${2:-}" ;;
  timeouts) timeouts "${2:?screensaver seconds}" "${3:?lock seconds}" ;;
  undo) undo ;;
  *) echo "Usage: trial-idle.sh install <checkout> | timeouts <screensaver> <lock> | undo" >&2; exit 1 ;;
esac
