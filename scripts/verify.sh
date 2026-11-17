#!/bin/sh
# Lokal verifiering på en Mac — samma steg som CI kör.
# Användning: ./scripts/verify.sh          (bygg + test)
#             ./scripts/verify.sh --app    (även .app/.dmg via build-app.sh)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> swift build";  swift build
echo "==> swift test";   swift test

# dev-agent kräver Python 3.10+ (CI kör 3.12). Xcodes python3 är ofta 3.9 — leta efter en nyare.
PY=""
for candidate in python3.14 python3.13 python3.12 python3.11 python3.10 python3; do
    if command -v "$candidate" >/dev/null 2>&1 \
        && "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
        PY="$candidate"
        break
    fi
done
if [ -n "$PY" ]; then
    echo "==> dev-agent-tester ($("$PY" --version 2>&1))"
    (cd dev-agent && "$PY" -m unittest discover -s tests)
else
    echo "==> HOPPAR ÖVER dev-agent-tester: kräver Python 3.10+ (de körs alltid i CI)"
fi

if [ "${1:-}" = "--app" ]; then
    echo "==> build-app.sh"; ./scripts/build-app.sh
fi
echo "==> Allt grönt"
