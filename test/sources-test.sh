#!/bin/bash

# Finding sources, reading their settings, listing them, and checking them.

source "$(dirname "$0")/lib.sh"

builtin=$scratch/builtin
user=$XDG_CONFIG_HOME/omarchy/ambient/sources
export OMARCHY_AMBIENT_PATH=$user:$builtin
stub systemctl 'exit 1'

make_source "$builtin" waves $'name=Waves\norder=20\nicon=W\ndescription=Calm waves\nspeed = 3 ' 'exit 0'
make_source "$builtin" fire $'name=Fire\norder=10' 'exit 0'
make_source "$builtin" stars $'name=Stars' 'exit 0'

assert_eq "sources are listed by order, then name, with their icon" "$("$AMBIENT" list)" \
  $'Fire\tfire\t\t\t\nWaves\twaves\t\tCalm waves\tW\nStars\tstars\t\t\t'

make_source "$user" stars $'name=My Stars' 'exit 0'
assert_eq "a user's source replaces a bundled one of the same name" "$("$AMBIENT" list | grep stars | cut -f1)" "My Stars"

eval "$(sed -n '/^settings_lines() {/,/^}/p; /^setting() {/,/^}/p; /^missing_needs() {/,/^}/p; /^source_dir() {/,/^}/p' "$AMBIENT")"
CONFIG_DIR=$XDG_CONFIG_HOME/omarchy/ambient
SOURCE_PATH=$OMARCHY_AMBIENT_PATH

assert_eq "a setting is read without surrounding spaces" "$(setting waves "$builtin/waves" speed)" "3"
assert_eq "a missing setting falls back to its default" "$(setting waves "$builtin/waves" outputs each)" "each"
echo "speed=7" >"$CONFIG_DIR/waves.conf"
assert_eq "the user's settings override the source's" "$(setting waves "$builtin/waves" speed)" "7"

echo "needs=bash definitely-not-a-command|sh nor-this-one" >>"$builtin/waves/source.conf"
assert_eq "a need is met by any of its alternatives" "$(missing_needs waves "$builtin/waves")" "nor-this-one"

assert_eq "a source passes its check" "$("$AMBIENT" check "$builtin/fire" 2>&1)" "fire: ok"

make_source "$scratch/bad" Bad_One $'outputs=sometimes\npause=maybe' 'exit 0'
chmod -x "$scratch/bad/Bad_One/run"
touch "$scratch/bad/Bad_One/pick"
assert_eq "the check names every problem" "$("$AMBIENT" check "$scratch/bad/Bad_One" 2>&1)" \
  "Bad_One: the directory name, Bad_One, should be lowercase letters, digits and dashes
Bad_One: source.conf has no name
Bad_One: outputs is sometimes, not each, focused or all
Bad_One: pause is maybe, not stop or none
Bad_One: run is missing or not executable
Bad_One: pick is not executable"

for dir in "$ROOT"/sources/* "$ROOT"/examples/*; do
  output=$("$AMBIENT" check "$dir" 2>&1)
  assert "bundled $(basename "$dir") is well formed" bash -c "[[ \$1 == *': ok' || \$1 == *'this computer lacks'* ]] && [[ \$1 != *'not '* ]]" _ "$output"
done

finish_tests
