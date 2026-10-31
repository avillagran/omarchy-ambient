#!/bin/bash
# Install omarchy-ambient and its ASCII scenes for the current user. No sudo.
#
#   curl -fsSL https://raw.githubusercontent.com/avillagran/omarchy-ambient/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/avillagran/omarchy-ambient/main/install.sh | bash -s -- --uninstall

set -euo pipefail

release=${OMARCHY_AMBIENT_RELEASE:-https://github.com/avillagran/omarchy-ambient/releases/latest/download}
config=${XDG_CONFIG_HOME:-$HOME/.config}
data=${XDG_DATA_HOME:-$HOME/.local/share}
cache=$HOME/.cache # Where the selector looks for posters.
bindir=$HOME/.local/bin
plugin_id=avillagran.ambient-selector
selector=$data/omarchy-ambient/selector
manifest=$selector/installed-sources
backups=$data/omarchy-ambient-backup

say() { printf '%s\n' "$*"; }
die() { printf 'omarchy-ambient: %s\n' "$*" >&2; exit 1; }

# Move something that is not ours aside, once. Uninstalling puts it back as it was.
keep() {
  local target=$1 slot
  [[ -e $target || -L $target ]] || return 0
  grep -qxF "$target" "$backups/index" 2>/dev/null && return 0
  mkdir -p "$backups"
  slot=$backups/1
  [[ -f $backups/index ]] && slot=$backups/$(($(wc -l <"$backups/index") + 1))
  cp -a "$target" "$slot"
  printf '%s\n' "$target" >>"$backups/index"
}

restore_kept() {
  local target n=0
  [[ -f $backups/index ]] || return 0
  while IFS= read -r target; do
    n=$((n + 1))
    rm -rf "$target"
    mkdir -p "$(dirname "$target")"
    cp -a "$backups/$n" "$target"
  done <"$backups/index"
  rm -rf "$backups"
}

is_ours() { [[ -f $manifest ]] && grep -qxF "$1" "$manifest"; }

uninstall() {
  local id conf active rebuild_menu=false
  [[ -f $manifest ]] || die "nothing to remove: this installer did not install it here"
  if [[ -x $bindir/omarchy-ambient ]]; then
    active=$("$bindir/omarchy-ambient" status 2>/dev/null | awk '{print $1}')
    if [[ -n $active ]] && is_ours "$active"; then
      "$bindir/omarchy-ambient" stop >/dev/null 2>&1 || true
    fi
    if [[ -e $selector/added-menu ]]; then
      "$bindir/omarchy-ambient" remove >/dev/null 2>&1 || true
    else
      rebuild_menu=true
    fi
  fi
  if command -v omarchy-plugin-disable >/dev/null; then
    omarchy-plugin-disable "$plugin_id" >/dev/null 2>&1 || true
  fi
  if [[ -f $manifest ]]; then
    while read -r id; do
      [[ $id =~ ^[a-z0-9-]+$ ]] || continue
      rm -rf "${config:?}/omarchy/ambient/sources/$id" "${data:?}/omarchy-ambient/$id/bin"
      # Ours, unless the user has since edited it.
      conf=$config/omarchy/ambient/$id.conf
      [[ $(cat "$conf" 2>/dev/null) == on_battery=run ]] && rm -f "$conf"
      rmdir "$data/omarchy-ambient/$id" 2>/dev/null || true
    done <"$manifest"
  fi
  # Only what this installer put there, never a build or package of the user's.
  if [[ $(readlink "$bindir/omarchy-ttfx-layer" 2>/dev/null) == "$selector/"* ]]; then
    rm -f "$bindir/omarchy-ttfx-layer"
  fi
  if [[ -e $selector/copied-ambient ]]; then
    rm -rf "$bindir/omarchy-ambient" "$HOME/.local/lib/omarchy-ambient" \
      "$HOME/.local/share/omarchy-ambient/sources"
  elif [[ -L $bindir/omarchy-ambient ]]; then
    rm -f "$bindir/omarchy-ambient"
  fi
  rm -rf "${config:?}/omarchy/plugins/$plugin_id" "$selector" "${cache:?}/omarchy/ambient-selector"
  rm -f "$bindir/omarchy-ambient-background-select"
  rmdir "$config/omarchy/ambient/sources" "$config/omarchy/ambient" 2>/dev/null || true
  restore_kept
  # The menu was already there: it must only list what is left.
  if $rebuild_menu && [[ -x $bindir/omarchy-ambient ]]; then
    "$bindir/omarchy-ambient" install >/dev/null 2>&1 || true
  fi
  if [[ -d $config/omarchy/plugins/$plugin_id ]] && command -v omarchy-plugin-enable >/dev/null; then
    omarchy-plugin-enable "$plugin_id" >/dev/null 2>&1 || true
  fi
  say "omarchy-ambient removed. Any config you edited in $config/omarchy/ambient stays."
}

case ${1:-} in
  --uninstall) uninstall; exit 0 ;;
  "") ;;
  *) die "usage: install.sh [--uninstall]" ;;
esac

[[ $EUID -ne 0 ]] || die "run this as your user, not as root"
case $(uname -m) in
  x86_64) arch=x86_64 ;;
  aarch64) arch=aarch64 ;;
  *) die "$(uname -m) is not supported" ;;
esac
command -v hyprctl >/dev/null || die "this needs Omarchy on Hyprland"

missing=()
for pair in curl:curl jq:jq socat:socat inotifywait:inotify-tools python3:python \
  sha256sum:coreutils tar:tar parec:libpulse; do
  command -v "${pair%%:*}" >/dev/null || missing+=("${pair##*:}")
done
((${#missing[@]} == 0)) || die "install these first: sudo pacman -S ${missing[*]}"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
bundle=omarchy-ambient-bundle-$arch.tar.gz

say "Downloading $bundle"
curl -fsSL "$release/$bundle" -o "$work/$bundle" || die "could not download $release/$bundle"
curl -fsSL "$release/SHA256SUMS" -o "$work/SHA256SUMS" || die "could not download the checksums"
(cd "$work" && grep -F " $bundle" SHA256SUMS | sha256sum -c --quiet -) >/dev/null 2>&1 ||
  die "$bundle does not match its checksum"
tar -xzf "$work/$bundle" -C "$work"
b=$work/bundle
[[ -f $b/VERSION ]] || die "$bundle is not a bundle"

renderer=$b/selector/omarchy-ttfx-layer
absent=$({ ldd "$renderer" 2>/dev/null || true; } | awk '/not found/ {print $1}' | tr '\n' ' ')
[[ -z $absent ]] || die "the renderer needs libraries this system lacks: $absent"

# What the first install replaces is kept; later runs replace their own files.
first=true
[[ -f $manifest ]] && first=false
if $first; then
  keep "$bindir/omarchy-ambient"
  keep "$bindir/omarchy-ambient-background-select"
  keep "$HOME/.local/lib/omarchy-ambient"
  keep "$HOME/.local/share/omarchy-ambient/sources"
  keep "$config/omarchy/plugins/$plugin_id"
  keep "$cache/omarchy/ambient-selector"
fi

mkdir -p "$bindir" "$selector" "$config/omarchy/ambient/sources" "$config/omarchy/plugins" \
  "$cache/omarchy/ambient-selector"

# Omarchy's own package wins over the copy in the bundle.
if [[ -x /usr/bin/omarchy-ambient ]]; then
  ln -sfn /usr/bin/omarchy-ambient "$bindir/omarchy-ambient"
else
  rm -f "$bindir/omarchy-ambient"
  install -Dm755 "$b/ambient/bin/omarchy-ambient" "$bindir/omarchy-ambient"
  mkdir -p "$HOME/.local/lib" "$HOME/.local/share/omarchy-ambient"
  rm -rf "$HOME/.local/lib/omarchy-ambient" "$HOME/.local/share/omarchy-ambient/sources"
  cp -r "$b/ambient/lib/omarchy-ambient" "$HOME/.local/lib/"
  cp -r "$b/ambient/share/omarchy-ambient/sources" "$HOME/.local/share/omarchy-ambient/"
  : >"$selector/copied-ambient"
fi

cp "$b"/selector/* "$selector/"
ln -sfn "$selector/omarchy-ttfx-layer" "$selector/ttfx-ambient-preview"
command -v omarchy-ttfx-layer >/dev/null || ln -sfn "$selector/omarchy-ttfx-layer" "$bindir/omarchy-ttfx-layer"
cp "$b"/posters/* "$cache/omarchy/ambient-selector/"

known=$(cat "$manifest" 2>/dev/null || true)
: >"$manifest"
for dir in "$b"/sources/*/; do
  id=$(basename "$dir")
  if ! grep -qxF "$id" <<<"$known"; then
    keep "$config/omarchy/ambient/sources/$id"
    keep "$data/omarchy-ambient/$id/bin"
  fi
  rm -rf "$config/omarchy/ambient/sources/$id" "$data/omarchy-ambient/$id/bin"
  cp -r "$dir" "$config/omarchy/ambient/sources/$id"
  mkdir -p "$data/omarchy-ambient/$id/bin"
  ln -sfn "$selector/omarchy-ttfx-layer" "$data/omarchy-ambient/$id/bin/omarchy-ttfx-layer"
  # A laptop on battery pauses a source by default, which looks like a failed start.
  conf=$config/omarchy/ambient/$id.conf
  [[ -e $conf ]] || printf 'on_battery=run\n' >"$conf"
  printf '%s\n' "$id" >>"$manifest"
done

rm -rf "${config:?}/omarchy/plugins/$plugin_id"
cp -r "$b/plugin" "$config/omarchy/plugins/$plugin_id"
chmod +x "$config/omarchy/plugins/$plugin_id/bin/list.sh"
cat >"$bindir/omarchy-ambient-background-select" <<SCRIPT
#!/bin/bash
exec python3 "$selector/background_selector.py" "\$@"
SCRIPT
chmod +x "$bindir/omarchy-ambient-background-select"

# The shell only knows the plugin after a rescan, which takes a moment.
enabled=false
if command -v omarchy-plugin-enable >/dev/null; then
  omarchy-shell -q shell rescanPlugins
  for _ in {1..20}; do
    omarchy-plugin-enable "$plugin_id" >/dev/null 2>&1 && { enabled=true; break; }
    sleep 0.25
  done
fi
$enabled || say "Enable the plugin by hand: omarchy-plugin-enable $plugin_id"
if $first && [[ $("$bindir/omarchy-ambient" installed 2>/dev/null) != "menu=yes idle=yes" ]]; then
  : >"$selector/added-menu"
fi
"$bindir/omarchy-ambient" install >/dev/null 2>&1 || say "Could not add the menu rows: run omarchy-ambient install."

say ""
say "Installed $(<"$b/VERSION")."
say ""
say "Try one:     omarchy-ambient start sand-clock-galaxy"
say "Selector:    omarchy-ambient-background-select screensaver"
say "Back:        omarchy-ambient stop"
[[ :$PATH: == *:"$bindir":* ]] || say "Add $bindir to your PATH."
