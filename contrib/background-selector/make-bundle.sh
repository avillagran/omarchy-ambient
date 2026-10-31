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
mkdir "$b/plugin"
cp -r "$here/live-preview/." "$b/plugin/"
rm -f "$b/plugin/run-preview.py"
printf '%s\n' "$version" >"$b/VERSION"

bundle=omarchy-ambient-bundle-$(uname -m).tar.gz
tar -czf "$out/$bundle" -C "$work" bundle
(cd "$out" && sha256sum "$bundle" >>SHA256SUMS)
echo "$out/$bundle"
