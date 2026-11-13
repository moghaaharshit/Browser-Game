#!/usr/bin/env bash
# One command deploy:  ./tools/deploy_github.sh https://github.com/<you>/<repo>.git
#
# Creates the commit, adds the remote and pushes.  Then (only the first time):
#   repo -> Settings -> Pages -> Build and deployment -> Source: GitHub Actions
# GitHub builds the web version and publishes it at
#   https://<you>.github.io/<repo>/
set -euo pipefail
cd "$(dirname "$0")/.."

REMOTE="${1:-}"
if [ -z "$REMOTE" ]; then
	echo "usage: $0 https://github.com/<you>/<repo>.git"
	exit 1
fi

if [ ! -d .git ]; then
	git init -b main
fi
git add -A
git commit -m "Neon City Drive - procedural island, 8 vehicles, phone controls" || echo "(nothing new to commit)"
if git remote get-url origin >/dev/null 2>&1; then
	git remote set-url origin "$REMOTE"
else
	git remote add origin "$REMOTE"
fi
git push -u origin HEAD:main
echo
echo "pushed. Now open: $REMOTE -> Settings -> Pages -> Source: GitHub Actions"
