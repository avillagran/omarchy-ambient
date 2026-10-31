#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/bin"
export OMARCHY_AMBIENT_DATA="$tmpdir/data"
export OMARCHY_AMBIENT_SETTING_BINARY="$tmpdir/bin/renderer"
# Only the stub counts: a real renderer in ~/.local/bin must not be found.
export PATH=/usr/bin:/bin
# Old renderer accepts unknown flags and returns its unchanged probe marker.
printf '#!/bin/bash\n[[ $* == *--probe* ]] || { echo unexpected-startup >&2; exit 99; }\necho "omarchy-ttfx-layer 1"\n' >"$OMARCHY_AMBIENT_SETTING_BINARY"
chmod +x "$OMARCHY_AMBIENT_SETTING_BINARY"
if bash "$root/sources/ttfx/prepare" >"$tmpdir/output" 2>&1; then
 echo 'old renderer incorrectly accepted' >&2; exit 1
fi
[[ ! -L $OMARCHY_AMBIENT_DATA/bin/omarchy-ttfx-layer ]]
# File support alone is insufficient while plugin configuration remains active.
printf '#!/bin/bash\necho "omarchy-ttfx-layer capabilities: text-file-v1"\n' >"$OMARCHY_AMBIENT_SETTING_BINARY"
if bash "$root/sources/ttfx/prepare" >"$tmpdir/output" 2>&1; then
 echo 'renderer without config isolation incorrectly accepted' >&2; exit 1
fi
printf '#!/bin/bash\necho "omarchy-ttfx-layer capabilities: text-file-v1 standalone-config-v1"\n' >"$OMARCHY_AMBIENT_SETTING_BINARY"
bash "$root/sources/ttfx/prepare"
[[ $(readlink "$OMARCHY_AMBIENT_DATA/bin/omarchy-ttfx-layer") == "$OMARCHY_AMBIENT_SETTING_BINARY" ]]
printf 'ok - old and partial capabilities rejected; isolated branding build accepted\n'
