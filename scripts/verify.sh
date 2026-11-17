#!/bin/sh
# Lokal verifiering på en Mac — samma steg som CI kör.
# Användning: ./scripts/verify.sh          (bygg + test)
#             ./scripts/verify.sh --app    (även .app/.dmg via build-app.sh)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> swift build";  swift build
echo "==> swift test";   swift test
echo "==> dev-agent-tester"
(cd dev-agent && python3 -m unittest discover -s tests)

if [ "${1:-}" = "--app" ]; then
    echo "==> build-app.sh"; ./scripts/build-app.sh
fi
echo "==> Allt grönt"
