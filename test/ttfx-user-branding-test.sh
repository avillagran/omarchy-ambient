#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/data/bin" "$tmpdir/home/.config/omarchy/branding"
cat >"$tmpdir/data/bin/omarchy-ttfx-layer" <<'MOCK'
#!/bin/bash
printf '%s\0' "$@" >"$TEST_ARGS"
MOCK
chmod +x "$tmpdir/data/bin/omarchy-ttfx-layer"
export HOME="$tmpdir/home" OMARCHY_AMBIENT_DATA="$tmpdir/data" TEST_ARGS="$tmpdir/args"
export OMARCHY_AMBIENT_OUTPUT=DP-1 OMARCHY_AMBIENT_WIDTH=1280 OMARCHY_AMBIENT_HEIGHT=800
export OMARCHY_AMBIENT_SCALE=2 OMARCHY_AMBIENT_NAMESPACE=test OMARCHY_AMBIENT_LAYER=overlay OMARCHY_AMBIENT_KEYBOARD=exclusive
unset OMARCHY_AMBIENT_SETTING_TEXT OMARCHY_AMBIENT_SETTING_TEXT_FILE
check() {
 bash "$root/sources/ttfx/run"
 python3 - "$TEST_ARGS" "$1" "$2" <<'PY'
from pathlib import Path
import sys
args=Path(sys.argv[1]).read_bytes().split(b'\0')[:-1]
flag=sys.argv[2].encode(); value=sys.argv[3].encode()
assert args[args.index(flag)+1]==value, args
assert (b'--text' in args)+(b'--text-file' in args)==1, args
PY
}
check --text OMARCHY
printf '  custom art  \nsecond line\n' >"$HOME/.config/omarchy/branding/screensaver.txt"
check --text-file "$HOME/.config/omarchy/branding/screensaver.txt"
export OMARCHY_AMBIENT_SETTING_TEXT='custom text'
check --text 'custom text'
export OMARCHY_AMBIENT_SETTING_TEXT_FILE="$tmpdir/override with spaces.txt"
check --text-file "$OMARCHY_AMBIENT_SETTING_TEXT_FILE"
printf 'ok - branding default, missing file, text override and file override\n'
