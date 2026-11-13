#!/usr/bin/env bash
# Build the browser version locally (the same thing GitHub Actions does).
#
#   ./tools/build_web.sh
#
# Result: build/web/index.html  ->  open it through a web server, not with a
# double click (browsers block .wasm/.pck from file://):
#
#   python3 -m http.server 8000 --directory build/web
#
# Requires Godot 4.7.2 + its export templates installed on this machine.
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-godot}"
if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "godot not found - set GODOT=/path/to/godot" >&2
	exit 1
fi

mkdir -p build/web
"$GODOT" --headless --path . --import || true
"$GODOT" --headless --path . --export-release "Web" build/web/index.html
touch build/web/.nojekyll
echo
echo "built: $(du -sh build/web | cut -f1) in build/web"
echo "serve it:  python3 -m http.server 8000 --directory build/web"
echo "then open: http://localhost:8000"
