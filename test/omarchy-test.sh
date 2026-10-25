#!/bin/bash

# install, remove and installed against a fake Omarchy: the menu rows land
# in the user's menu extension and leave it as it was when removed, the idle
# service is cloned to run the live screensaver, and both are skipped when
# Omarchy does it natively.

source "$(dirname "$0")/lib.sh"

export OMARCHY_AMBIENT_PATH=$scratch/sources OMARCHY_PATH=$scratch/omarchy
extension=$XDG_CONFIG_HOME/omarchy/extensions/omarchy-menu.jsonc
plugin=$XDG_CONFIG_HOME/omarchy/plugins/omarchy-ambient.idle
launcher=$XDG_DATA_HOME/omarchy-ambient/omarchy/omarchy-launch-screensaver

make_source "$scratch/sources" demo $'name=Demo "Quoted"\nicon=D\ndescription=A demo\nplacements=background screensaver' 'exit 0'
make_source "$scratch/sources" wallpaper $'name=Wallpaper' 'exit 0'
make_source "$scratch/sources" saver $'name=Saver\nplacements=screensaver' 'exit 0'

# An Omarchy 4.0: Style menu, a stock launcher, the idle service.
fake_omarchy() { # fake_omarchy <style|appearance>
  rm -rf "$OMARCHY_PATH"
  mkdir -p "$OMARCHY_PATH/default/omarchy" "$OMARCHY_PATH/bin" "$OMARCHY_PATH/shell/plugins/services/idle"
  if [[ $1 == style ]]; then
    printf '{\n  "style.background": {"label":"Background"},\n  "style.screensaver": {"label":"Screensaver"}\n}\n'
  else
    printf '{\n  "appearance.background": {"label":"Background"},\n  "appearance.branding.screensaver": {"label":"Screensaver"}\n}\n'
  fi >"$OMARCHY_PATH/default/omarchy/omarchy-menu.jsonc"
  printf '#!/bin/bash\necho stock "$@"\n' >"$OMARCHY_PATH/bin/omarchy-launch-screensaver"
  chmod +x "$OMARCHY_PATH/bin/omarchy-launch-screensaver"
  printf 'runProcess(screensaverProcess, "screensaver", "[[ locked ]] || omarchy-launch-screensaver")\n' \
    >"$OMARCHY_PATH/shell/plugins/services/idle/Service.qml"
  printf '{"id":"omarchy.idle","name":"Idle","entryPoints":{"service":"Service.qml"}}\n' \
    >"$OMARCHY_PATH/shell/plugins/services/idle/manifest.json"
}
fake_omarchy style

# omarchy plugin list/enable/disable, keeping the enabled set in a file.
echo '[{"id":"omarchy.idle","enabled":true,"clonedFrom":""}]' >"$scratch/plugins.json"
stub omarchy "
state='$scratch/plugins.json' plugins='$XDG_CONFIG_HOME/omarchy/plugins'
echo \"\$*\" >>'$scratch/omarchy.log'
case \$2 in
  list)
    for dir in \"\$plugins\"/*/; do
      [[ -f \$dir/manifest.json ]] || continue
      id=\$(jq -r .id \"\$dir/manifest.json\")
      jq -e --arg id \"\$id\" 'any(.[]; .id == \$id)' \"\$state\" >/dev/null ||
        jq --arg id \"\$id\" --arg from \"\$(jq -r '.omarchy.clonedFrom // \"\"' \"\$dir/manifest.json\")\" '. + [{id: \$id, enabled: false, clonedFrom: \$from}]' \"\$state\" >\"\$state.tmp\" && mv \"\$state.tmp\" \"\$state\"
    done
    cat \"\$state\" ;;
  enable|disable)
    on=\$([[ \$2 == enable ]] && echo true || echo false)
    # Enabling a clone disables what it was cloned from.
    jq --arg id \"\$3\" --argjson on \$on 'map(if .id == \$id then .enabled = \$on else . end)
      | (map(select(.id == \$id and .enabled))[0].clonedFrom // \"\") as \$from
      | map(if .id == \$from and \$from != \"\" then .enabled = false else . end)' \"\$state\" >\"\$state.tmp\" && mv \"\$state.tmp\" \"\$state\" ;;
esac"
stub omarchy-shell 'exit 0'

# The menu reads JSONC: comment lines and trailing commas are allowed.
parse() { python3 -c '
import json, re, sys
text = re.sub(r"(?m)^\s*//[^\n]*(\n|$)", "", open(sys.argv[1]).read())
print(json.dumps(json.loads(re.sub(r",(\s*[}\]])", r"\1", text)), sort_keys=True))' "$1"; }
row() { parse "$extension" | jq -r --arg id "$1" ".[\$id].$2 // empty"; }
enabled() { jq -r --arg id "$1" '.[] | select(.id == $id) | .enabled' "$scratch/plugins.json"; }

# The user's own extension, without a trailing comma.
mkdir -p "${extension%/*}"
cat >"$extension" <<'EOF'
{
  // My own rows
  "personal.notes": {"icon":"N","label":"Notes","action":"notes"}
}
EOF
cp "$extension" "$scratch/extension.orig"

"$AMBIENT" install >"$scratch/out" 2>&1
assert "the extension still parses" eval "parse \"\$extension\" >/dev/null"
assert_eq "the user's rows stay" "$(row personal.notes label)" "Notes"
assert_eq "Live Background goes under Style on Omarchy 4.0" "$(row style.live-background label)" "Live Background"
assert_eq "each background source gets a row" "$(row style.live-background.demo action)" "$AMBIENT start demo"
assert_eq "names are escaped" "$(row style.live-background.demo label)" 'Demo "Quoted"'
assert_eq "a screensaver-only source is no background" "$(row style.live-background.saver label)" ""
assert_eq "a background-only source is no screensaver" "$(row style.screensaver.live-wallpaper label)" ""
assert_eq "each screensaver source gets a row" "$(row style.screensaver.live-saver action)" "$AMBIENT screensaver --set saver"
assert_eq "the stock one can be chosen back" "$(row style.screensaver.live-text action)" "$AMBIENT screensaver --set text"
assert_eq "the chosen screensaver is checked" "$(row style.screensaver.live-demo checked)" "[[ \$($AMBIENT screensaver --get) == demo ]]"
assert_eq "Preview runs the routed launcher" "$(row style.screensaver.live-preview action)" "$launcher force"
assert_eq "so does System > Screensaver" "$(row system.screensaver action)" "$launcher force"

assert "the idle service is cloned" test -f "$plugin/Service.qml"
assert "the clone runs the routed launcher" grep -qF "|| \\\"$launcher\\\"\")" "$plugin/Service.qml"
assert_eq "the clone is enabled" "$(enabled omarchy-ambient.idle)" "true"
assert_eq "and replaces Omarchy's" "$(enabled omarchy.idle)" "false"
assert_eq "status says both are installed" "$("$AMBIENT" installed)" "menu=yes idle=yes"

stub omarchy-toggle-enabled 'exit 1'
PATH="$OMARCHY_PATH/bin:$PATH" "$AMBIENT" screensaver --set text
assert_eq "with Text Effects chosen the launcher runs Omarchy's" "$(PATH="$OMARCHY_PATH/bin:$PATH" "$launcher" force)" "stock force"
stub omarchy-toggle-enabled 'exit 0'
assert "with the screensaver turned off the launcher does nothing" bash -c "! PATH='$OMARCHY_PATH/bin:$PATH' '$launcher'"
assert "but Preview still runs it" bash -c "[[ \$(PATH='$OMARCHY_PATH/bin:$PATH' '$launcher' force) == 'stock force' ]]"
assert "a live one goes to omarchy-ambient" grep -q "screensaver$" "$launcher"

"$AMBIENT" install >/dev/null 2>&1
assert_eq "installing again leaves one block" "$(grep -c '>>> omarchy-ambient' "$extension")" "1"

"$AMBIENT" remove >/dev/null 2>&1
assert_eq "removing leaves the extension as it was" "$(cat "$extension")" "$(cat "$scratch/extension.orig")"
assert "the clone is gone" test ! -e "$plugin"
assert "and the launcher" test ! -e "$launcher"
assert_eq "Omarchy's idle service is back" "$(enabled omarchy.idle)" "true"
assert_eq "status says nothing is installed" "$("$AMBIENT" installed)" "menu=no idle=no"

rm "$extension"
fake_omarchy appearance
"$AMBIENT" install >/dev/null 2>&1
assert_eq "a missing extension is created" "$(row appearance.live-background label)" "Live Background"
assert_eq "later releases put screensavers under Branding" "$(row appearance.branding.screensaver.live-demo label)" 'Demo "Quoted"'
"$AMBIENT" remove >/dev/null 2>&1

# An Omarchy that does it all itself.
sed -i 's/"label":"Screensaver"}/"label":"Screensaver","provider":"screensaver-sources"}/' "$OMARCHY_PATH/default/omarchy/omarchy-menu.jsonc"
printf '#!/bin/bash\nexec omarchy-ambient screensaver\n' >"$OMARCHY_PATH/bin/omarchy-launch-screensaver"
"$AMBIENT" install >"$scratch/out" 2>&1
assert "a native menu gets no rows" bash -c "! grep -q 'omarchy-ambient' '$extension'"
assert "a native launcher needs no clone" test ! -e "$plugin"
assert_eq "status says Omarchy does both" "$("$AMBIENT" installed)" "menu=native idle=native"

# Someone else's clone of the idle service is left alone.
fake_omarchy style
mkdir -p "$XDG_CONFIG_HOME/omarchy/plugins/amiga.idle"
echo '{"id":"amiga.idle","omarchy":{"clonedFrom":"omarchy.idle"}}' >"$XDG_CONFIG_HOME/omarchy/plugins/amiga.idle/manifest.json"
omarchy plugin list --json >/dev/null; omarchy plugin enable amiga.idle
"$AMBIENT" install >"$scratch/out" 2>&1
assert "another idle clone is not replaced" test ! -e "$plugin"
assert "and the user is told" grep -q "already replaced by amiga.idle" "$scratch/out"
assert_eq "the menu rows still go in" "$(row style.live-background.demo action)" "$AMBIENT start demo"

"$AMBIENT" remove >/dev/null 2>&1
omarchy plugin disable amiga.idle; rm -rf "$XDG_CONFIG_HOME/omarchy/plugins/amiga.idle"
omarchy plugin enable omarchy.idle

# The names omarchy-bg-live had for these still work.
"$AMBIENT" omarchy install >/dev/null 2>&1
assert_eq "omarchy install still installs" "$("$AMBIENT" omarchy status)" "menu=yes idle=yes"
"$AMBIENT" omarchy uninstall >/dev/null 2>&1
assert_eq "omarchy uninstall still removes" "$("$AMBIENT" installed)" "menu=no idle=no"

# Coming from omarchy-bg-live: its settings, downloads, menu rows and idle
# clone.
legacy_plugin=$XDG_CONFIG_HOME/omarchy/plugins/omarchy-bg-live.idle
rm -rf "$XDG_CONFIG_HOME/omarchy/ambient" "$XDG_DATA_HOME/omarchy-ambient"
# Installed with PREFIX=~/.local, both data directories hold bundled sources.
mkdir -p "$XDG_CONFIG_HOME/omarchy/bg-live" "$XDG_DATA_HOME/omarchy-bg-live/demo" "$legacy_plugin" \
  "$XDG_DATA_HOME/omarchy-bg-live/sources/old" "$XDG_DATA_HOME/omarchy-bg-live/omarchy" "$XDG_DATA_HOME/omarchy-ambient/sources/new"
echo source=demo >"$XDG_CONFIG_HOME/omarchy/bg-live/screensaver.conf"
echo downloaded >"$XDG_DATA_HOME/omarchy-bg-live/demo/pack"
echo '{"id":"omarchy-bg-live.idle","omarchy":{"clonedFrom":"omarchy.idle"}}' >"$legacy_plugin/manifest.json"
omarchy plugin list --json >/dev/null; omarchy plugin enable omarchy-bg-live.idle
python3 - "$extension" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read().replace("{", '{\n// >>> omarchy-bg-live: added by "omarchy-bg-live omarchy install"\n  "style.live-background": {"label":"Old"},\n// <<< omarchy-bg-live', 1)
open(path, "w").write(text)
PY
assert_eq "the old selection is read" "$("$AMBIENT" screensaver --get)" "demo"
assert "the old settings moved" test ! -e "$XDG_CONFIG_HOME/omarchy/bg-live"
assert_eq "the old downloads moved" "$(cat "$XDG_DATA_HOME/omarchy-ambient/demo/pack")" "downloaded"
assert "next to the bundled sources" test -d "$XDG_DATA_HOME/omarchy-ambient/sources/new"
assert "the old bundled sources and launcher are dropped" test ! -e "$XDG_DATA_HOME/omarchy-bg-live"
"$AMBIENT" install >"$scratch/out" 2>&1
assert "the old menu rows are gone" bash -c "! grep -q 'omarchy-bg-live' '$extension'"
assert_eq "and the new ones are in" "$(row style.live-background label)" "Live Background"
assert "the old idle clone is gone" test ! -e "$legacy_plugin"
assert_eq "and the new one replaces Omarchy's" "$(enabled omarchy-ambient.idle)" "true"
assert_eq "with the old one off" "$(enabled omarchy-bg-live.idle)" "false"

finish_tests
