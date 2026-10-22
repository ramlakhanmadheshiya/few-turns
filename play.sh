#!/usr/bin/env bash
# Launch Few Turns directly (no Godot editor window).
set -e
cd "$(dirname "$0")"
GODOT="${GODOT:-$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)}"
# Import assets once if the cache is missing (first run / fresh clone).
[ -d .godot/imported ] || "$GODOT" --headless --path . --import >/dev/null 2>&1
exec "$GODOT" --path . "$@"
