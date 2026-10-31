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

mkdir -p "$b/selector" "$out"
make -s -C "$root"
make -s -C "$root" install DESTDIR="$b/ambient" PREFIX=
cp "$renderer" "$b/selector/omarchy-ttfx-layer"
cp "$here/background_selector.py" "$here/catalog.json" "$here/live-preview/run-preview.py" "$b/selector/"
cp -r "$here/sources" "$here/posters" "$b/"
# The shell caches QML by path, so each version loads from its own directory.
mkdir -p "$b/plugin/v$version"
cp -r "$here/live-preview/." "$b/plugin/v$version/"
rm -f "$b/plugin/v$version/run-preview.py"
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
