#!/bin/bash
# Build the release bundle that install.sh downloads, for this architecture.
#
#   contrib/background-selector/make-bundle.sh path/to/omarchy-ttfx-layer VERSION out/
#
# The renderer comes from omarchy-ttfx-layer, built with --no-default-features.

set -euo pipefail

renderer=${1:?renderer binary}
version=${2:?version}
out=${3:?output directory}
root=$(cd "$(dirname "$0")/../.." && pwd)
here=$root/contrib/background-selector
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
b=$work/bundle

mkdir -p "$b/selector" "$b/sources" "$out"
make -s -C "$root" all
make -s -C "$root" install-core DESTDIR="$b/ambient" PREFIX=
cp "$renderer" "$b/selector/omarchy-ttfx-layer"
cp "$here/background_selector.py" "$here/catalog.json" "$here/run-preview.py" "$b/selector/"
# The scenes the carousel offers; install.sh copies them beside the user's sources.
for dir in "$root"/sources/*/; do
  case $(basename "$dir") in amiga | screensaver | ttfx) continue ;; esac
  cp -r "$dir" "$b/sources/"
done
cp -r "$here/posters" "$b/"
mkdir -p "$b/hypr"
cp "$here/ambient-background-selector.lua" "$b/hypr/"
# The shell caches QML by path, so each version loads from its own directory.
mkdir -p "$b/plugin/v$version/bin"
cp "$here"/live-preview/*.qml "$here"/live-preview/*.js "$here/live-preview/manifest.json" "$b/plugin/v$version/"
cp "$here/live-preview/bin/list.sh" "$b/plugin/v$version/bin/"
printf '%s\n' '#!/bin/bash' 'exec "$HOME/.local/bin/omarchy-ambient-select" "$@"' >"$b/plugin/v$version/bin/select"
chmod 755 "$b/plugin/v$version/bin/select" "$b/plugin/v$version/bin/list.sh"
# The native preview painter is optional: without it the carousel uses Canvas.
if [[ -f $root/build/native/libambientcells.so ]]; then
  mkdir -p "$b/plugin/v$version/native/AmbientCells"
  cp "$root/build/native/libambientcells.so" "$here/live-preview/native/AmbientCells/qmldir" "$b/plugin/v$version/native/AmbientCells/"
  strip "$b/plugin/v$version/native/AmbientCells/libambientcells.so"
else
  echo "make-bundle: no Qt 6 development files or shader tools, the bundle keeps the Canvas preview" >&2
fi
mv "$b/plugin/v$version/manifest.json" "$b/plugin/"
python3 -c '
import json, sys
path, version = sys.argv[1:]
manifest = json.load(open(path))
manifest["version"] = version
manifest["entryPoints"]["service"] = f"v{version}/Service.qml"
json.dump(manifest, open(path, "w"), indent=2)
' "$b/plugin/manifest.json" "$version"
printf '%s\n' "$version" >"$b/VERSION"

bundle=omarchy-ambient-bundle-$(uname -m).tar.gz
tar -czf "$out/$bundle" -C "$work" bundle
(cd "$out" && sha256sum "$bundle" >>SHA256SUMS)
echo "$out/$bundle"
