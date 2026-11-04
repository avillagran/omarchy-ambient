#!/bin/bash
# Compile the real preview implementation into an offscreen functional test.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
native=$here/../live-preview/native/AmbientCells
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
# No live shell, compositor, daemon, or installed files are used.
export QT_QPA_PLATFORM=offscreen
export XDG_RUNTIME_DIR=$build/runtime
mkdir -m700 "$XDG_RUNTIME_DIR"
/usr/lib/qt6/moc -DAMBIENT_CELLS_TEST $(pkg-config --cflags Qt6Quick Qt6Qml Qt6Gui) \
  "$native/cellpreview.cpp" -o "$build/cellpreview.moc"
# shellcheck disable=SC2046
${CXX:-c++} -O2 -std=c++17 -fPIC -I"$build" "$here/cellpreview-test.cpp" \
  -o "$build/cellpreview-test" $(pkg-config --cflags --libs Qt6Quick Qt6Qml Qt6Gui)
"$build/cellpreview-test"
