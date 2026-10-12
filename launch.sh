#!/usr/bin/env bash
# libresim double-click launcher (used by "Start libresim.desktop" / "Start libresim.command").
#   - Everything is already set up  -> starts the game right away, no terminal.
#   - First time (or data missing)  -> opens a terminal window that runs ./run.sh, which asks
#     before installing anything, downloads and builds the data, then starts the game.
# It also puts libresim into your applications menu, so you can start it from there too.
# Not needed from a terminal: ./run.sh does the same and takes game options.
#   ./launch.sh --register-only   only add the applications-menu entry
set -u
cd "$(dirname "$(readlink -f "$0")")"
ROOT=$PWD
mkdir -p data

godot_bin() {
  for g in "$HOME/.local/bin/godot" "$(command -v godot 2>/dev/null)" /Applications/Godot.app/Contents/MacOS/Godot; do
    [[ -n $g && -x $g ]] && { echo "$g"; return 0; }
  done
  return 1
}

ready() {  # Godot found, the project imported once, and the key data files built
  godot_bin >/dev/null || return 1
  [[ -d game/.godot/imported ]] || return 1
  for f in data/processed/terrain/meta.json data/processed/runways.json data/processed/airports.json data/processed/airport_ops.json; do
    [[ -s $f ]] || return 1
  done
}

# Menu entry with absolute paths + a custom icon on the launcher file in this folder (Linux).
install_menu_entry() {
  [[ $(uname) == Linux ]] || return 0
  local dir="$HOME/.local/share/applications" f="$HOME/.local/share/applications/libresim.desktop"
  mkdir -p "$dir"
  local want
  want=$(cat <<DESK
[Desktop Entry]
Type=Application
Name=libresim
GenericName=Flight Simulator
Comment=Open-source Cessna 172 flight simulator, Mumbai to Kochi
Exec="$ROOT/launch.sh"
Icon=$ROOT/game/branding/icon.png
Terminal=false
Categories=Game;Simulation;
DESK
)
  if [[ ! -f $f ]] || [[ $(cat "$f") != "$want" ]]; then
    printf '%s\n' "$want" > "$f"
    command -v update-desktop-database >/dev/null && update-desktop-database "$dir" >/dev/null 2>&1
  fi
  if command -v gio >/dev/null && [[ -f "$ROOT/Start libresim.desktop" ]]; then
    gio set "$ROOT/Start libresim.desktop" metadata::custom-icon "file://$ROOT/game/branding/icon.png" >/dev/null 2>&1
    gio set "$ROOT/Start libresim.desktop" metadata::trusted true >/dev/null 2>&1
  fi
}

register() {  # remember where the game lives, so the launcher file works wherever the file manager starts it
  mkdir -p "$HOME/.config/libresim" && printf '%s' "$ROOT" > "$HOME/.config/libresim/root"
  install_menu_entry
}

say() {  # a message the player can see even without a terminal
  echo "$*" >> data/run.log
  if command -v notify-send >/dev/null; then notify-send "libresim" "$*"
  elif command -v zenity >/dev/null; then zenity --info --title=libresim --text="$*" 2>/dev/null; fi
}

open_in_terminal() {  # run ./run.sh in a terminal window the user can read and answer
  local cmd='cd "$1" && ./run.sh; echo; read -rp "libresim setup finished. Press Enter to close this window. "'
  local t
  for t in x-terminal-emulator gnome-terminal kgx konsole xfce4-terminal cosmic-term alacritty kitty xterm; do
    command -v "$t" >/dev/null || continue
    case $t in
      gnome-terminal) exec gnome-terminal -- bash -c "$cmd" _ "$ROOT" ;;
      xfce4-terminal) exec xfce4-terminal -e "bash -c '$cmd' _ '$ROOT'" ;;
      *)              exec "$t" -e bash -c "$cmd" _ "$ROOT" ;;
    esac
  done
  say "libresim needs a one-time setup but no terminal program was found. Open a terminal in $ROOT and run ./run.sh"
  exit 1
}

if [[ ${LIBRESIM_DRY:-} ]]; then   # for tests: say what would happen (to stdout, or to the file named)
  out=$LIBRESIM_DRY; [[ $out == 1 ]] && out=/dev/stdout
  if ready; then echo "ready: would start the game" >> "$out"; else echo "not ready: would open a terminal for ./run.sh" >> "$out"; fi
  exit 0
fi

if [[ ${1:-} == --register-only ]]; then register; exit 0; fi

if ready; then
  register
  GODOT=$(godot_bin)
  if [[ $(uname) == Darwin ]]; then
    exec "$GODOT" --path game -- "$@" >> data/run.log 2>&1
  fi
  setsid -f "$GODOT" --path game -- "$@" >> data/run.log 2>&1
else
  register
  open_in_terminal
fi
