#!/bin/bash
# install.sh: a checked download, everything under the home, a clean removal.

source "$(dirname "$0")/lib.sh"

for name in socat parec inotifywait omarchy-plugin-enable omarchy-plugin-disable; do stub "$name" 'exit 0'; done
monitors '[]'
workspaces '[]'

b=$scratch/pack/bundle
mkdir -p "$b/selector" "$b/posters" "$b/plugin/bin" "$b/sources/demo" "$scratch/site"
make -s -C "$ROOT" install DESTDIR="$b/ambient" PREFIX= >/dev/null
echo 9.9.9 >"$b/VERSION"
printf '#!/bin/bash\n' >"$b/selector/omarchy-ttfx-layer"
chmod +x "$b/selector/omarchy-ttfx-layer"
touch "$b/selector/background_selector.py" "$b/posters/demo.jpg" "$b/plugin/manifest.json"
printf '#!/bin/bash\n' >"$b/plugin/bin/list.sh"
printf 'name=Demo\n' >"$b/sources/demo/source.conf"
bundle=omarchy-ambient-bundle-$(uname -m).tar.gz
tar -czf "$scratch/site/$bundle" -C "$scratch/pack" bundle
(cd "$scratch/site" && sha256sum "$bundle" >SHA256SUMS)

export OMARCHY_AMBIENT_RELEASE=file://$scratch/site
install_sh=$ROOT/install.sh

mkdir -p "$HOME/.config/omarchy/ambient"
printf 'on_battery=pause\n' >"$HOME/.config/omarchy/ambient/keep.conf"
assert "it installs" bash "$install_sh"
data=$XDG_DATA_HOME/omarchy-ambient
sources=$XDG_CONFIG_HOME/omarchy/ambient/sources
assert "the scene is a source" test -f "$sources/demo/source.conf"
assert "the scene finds the renderer" test -x "$data/demo/bin/omarchy-ttfx-layer"
assert "the preview finds the renderer" test -x "$data/selector/ttfx-ambient-preview"
assert "the plugin is in place" test -x "$XDG_CONFIG_HOME/omarchy/plugins/avillagran.ambient-selector/bin/list.sh"
assert "the poster is in the cache" test -f "$HOME/.cache/omarchy/ambient-selector/demo.jpg"
assert "the command is on the path" test -x "$HOME/.local/bin/omarchy-ambient"
assert_eq "scenes keep running on battery" "$(cat "$XDG_CONFIG_HOME/omarchy/ambient/demo.conf")" "on_battery=run"

printf 'on_battery=pause\n' >"$XDG_CONFIG_HOME/omarchy/ambient/demo.conf"
assert "it installs again" bash "$install_sh"
assert_eq "a second run keeps the user's settings" "$(cat "$XDG_CONFIG_HOME/omarchy/ambient/demo.conf")" "on_battery=pause"

assert "it uninstalls" bash "$install_sh" --uninstall
assert "the source is gone" test ! -e "$sources/demo"
assert "the plugin is gone" test ! -e "$XDG_CONFIG_HOME/omarchy/plugins/avillagran.ambient-selector"
assert "the selector is gone" test ! -e "$data/selector"
assert "the renderer link is gone" test ! -e "$HOME/.local/bin/omarchy-ttfx-layer"
assert_eq "config files stay" "$(cat "$XDG_CONFIG_HOME/omarchy/ambient/keep.conf")" "on_battery=pause"

printf 'corrupt' >>"$scratch/site/$bundle"
output=$(bash "$install_sh" 2>&1) && status=0 || status=$?
assert "a corrupt download stops the install" test "$status" -ne 0
assert_eq "and says why" "$output" "Downloading $bundle
omarchy-ambient: $bundle does not match its checksum"
assert "and installs nothing" test ! -e "$sources/demo"

finish_tests
