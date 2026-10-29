#!/bin/bash

# The Amiga source starts FS-UAE without the sound server when it stops answering.

source "$(dirname "$0")/lib.sh"

export OMARCHY_AMBIENT_DATA=$scratch/data OMARCHY_AMBIENT_RUNTIME=$scratch/runtime OMARCHY_AMBIENT_PLACEMENT=background
demo=$OMARCHY_AMBIENT_DATA/demos/0001-Demo
mkdir -p "$demo/variants/a/state"
echo '{"variants":[{"config":"variants/a/demo.fs-uae"}]}' >"$demo/config.json"
touch "$demo/variants/a/demo.fs-uae" "$demo/variants/a/state/Saved State 1.uss"
stub omarchy-ambient 'echo "${ALSOFT_DRIVERS-unset} $*" >"'"$scratch"'/launch"'

stub paplay 'exit 0'
"$ROOT/sources/amiga/run"
assert_eq "with a sound server that answers, FS-UAE keeps its audio driver" "$(cut -d' ' -f1 "$scratch/launch")" "unset"
assert "and the demo plays muted" grep -q -- '--volume=0' "$scratch/launch"

stub paplay 'sleep 10'
start=$SECONDS
"$ROOT/sources/amiga/run"
assert_eq "with a sound server that hangs, FS-UAE runs with the null audio driver" "$(cut -d' ' -f1 "$scratch/launch")" "null"
assert "after waiting at most a few seconds" test $((SECONDS - start)) -le 4

finish_tests
