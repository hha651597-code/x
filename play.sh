#!/bin/sh
# Run the game. Uses a global `godot` if there is one, else the Godot 4.7.2 copy in ~/Tools.
cd "$(dirname "$0")" || exit 1
if command -v godot >/dev/null 2>&1; then
  exec godot --path . "$@"
elif [ -x "$HOME/Tools/godot-4.7.2/Godot.app/Contents/MacOS/Godot" ]; then
  exec "$HOME/Tools/godot-4.7.2/Godot.app/Contents/MacOS/Godot" --path . "$@"
else
  echo "Godot 4.7 not found: install it or open this folder in the Godot editor." >&2
  exit 1
fi
