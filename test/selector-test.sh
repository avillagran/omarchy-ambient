#!/bin/bash

# The background selector as an installed package ships it: omarchy-ambient
# links its shell plugin for the user and enables it, leaves a copy installed
# by hand alone, and takes it back on disable. A screensaver chosen with the
# selector before 0.5 moves over to the ttfx source.

source "$(dirname "$0")/lib.sh"

# The layout make install leaves under a prefix.
prefix=$scratch/usr
make -s -C "$ROOT" install-core install-selector DESTDIR= PREFIX="$prefix" HAVE_QT= >/dev/null 2>&1
ambient=$prefix/bin/omarchy-ambient
plugin=$prefix/share/omarchy-ambient/plugin
link=$XDG_CONFIG_HOME/omarchy/plugins/avillagran.ambient-selector

assert "the plugin manifest loads from its own version directory" \
  test "$(jq -r .entryPoints.service "$plugin/manifest.json")" == "v$(jq -r .version "$plugin/manifest.json")/Service.qml"
assert "the plugin calls the selector of this prefix" grep -qF "$prefix/bin/omarchy-ambient-select" "$plugin"/v*/bin/select
assert "the selector command names the packaged files" grep -qF "OMARCHY_AMBIENT_SOURCES=$prefix/share/omarchy-ambient/sources" "$prefix/bin/omarchy-ambient-select"
assert "the scenes ship as built-in sources" test -f "$prefix/share/omarchy-ambient/sources/neon-city/source.conf"

# The shell answers a rescan and enables plugins it can see.
stub omarchy-shell 'echo "$*" >>"$HOME/shell.calls"'
stub omarchy-plugin-enable '[[ -f $XDG_CONFIG_HOME/omarchy/plugins/$1/manifest.json ]] && echo "$1" >>"$HOME/enabled"'
stub omarchy-plugin-disable 'echo "$1" >>"$HOME/disabled"'

"$ambient" selector enable
assert "enable links the packaged plugin for the user" test "$(readlink "$link")" == "$plugin"
assert "enable asks the shell to rescan" grep -qx "\-q shell rescanPlugins" "$HOME/shell.calls"
assert "enable turns the plugin on" grep -qx avillagran.ambient-selector "$HOME/enabled"

"$ambient" selector disable
assert "disable turns the plugin off" grep -qx avillagran.ambient-selector "$HOME/disabled"
assert "disable removes its own link" test ! -e "$link"

mkdir -p "$link"
echo '{}' >"$link/manifest.json"
"$ambient" selector enable
assert "a copy installed by hand stays" test ! -L "$link"
"$ambient" selector disable
assert "disable leaves a copy installed by hand" test -f "$link/manifest.json"
rm -rf "$link"

# Without a shell to ask, enable still links the plugin and succeeds.
rm -f "$scratch/stubs/omarchy-plugin-enable"
stub omarchy-shell 'exit 1'
assert "enable works without a running shell" "$ambient" selector enable
assert "and leaves the link in place" test -L "$link"

mkdir -p "$XDG_CONFIG_HOME/omarchy/ambient"
printf 'source=screensaver\nchoice=fx:matrix\n' >"$XDG_CONFIG_HOME/omarchy/ambient/screensaver.conf"
"$ambient" status >/dev/null
assert "a selector screensaver from before 0.5 moves to ttfx" \
  test "$(OMARCHY_AMBIENT_PATH=$prefix/share/omarchy-ambient/sources "$ambient" screensaver --get)" == ttfx
printf 'source=screensaver\n' >"$XDG_CONFIG_HOME/omarchy/ambient/screensaver.conf"
"$ambient" status >/dev/null
assert "the terminal effects screensaver stays as it was" grep -qx source=screensaver "$XDG_CONFIG_HOME/omarchy/ambient/screensaver.conf"

# A scene runs the installed renderer even when an older install left a link
# for it, and falls back to that link only where nothing is installed.
mkdir -p "$scratch/renderer" "$scratch/scene-data/bin"
printf '#!/bin/bash\necho installed "$@"\n' >"$scratch/renderer/omarchy-ttfx-layer"
printf '#!/bin/bash\necho stale "$@"\n' >"$scratch/scene-data/bin/omarchy-ttfx-layer"
chmod +x "$scratch/renderer/omarchy-ttfx-layer" "$scratch/scene-data/bin/omarchy-ttfx-layer"
scene=$prefix/share/omarchy-ambient/sources/neon-city/run
for name in OUTPUT WIDTH HEIGHT SCALE NAMESPACE LAYER KEYBOARD; do export "OMARCHY_AMBIENT_$name=x"; done
assert "a scene runs the installed renderer over a stale link" \
  test "$(PATH=$scratch/renderer OMARCHY_AMBIENT_DATA=$scratch/scene-data /bin/bash "$scene" | cut -d ' ' -f 1)" == installed
assert "a scene falls back to its link when no renderer is installed" \
  test "$(PATH=$scratch/empty OMARCHY_AMBIENT_DATA=$scratch/scene-data /bin/bash "$scene" | cut -d ' ' -f 1)" == stale

finish_tests
