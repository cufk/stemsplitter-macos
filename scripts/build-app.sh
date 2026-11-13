#!/bin/sh
# Bygger en fristående StemSplitter.app i build/
# Anvandning: ./scripts/build-app.sh   (fran repo-roten eller var som helst)
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> swift build -c release"
swift build -c release

APP="$ROOT/build/StemSplitter.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$ROOT/.build/release/StemSplitter" "$APP/Contents/MacOS/StemSplitter"
cp "$ROOT/Packaging/Info.plist" "$APP/Contents/Info.plist"

# SPM-resursbunten (innehaller bootstrap.sh) maste med i Contents/Resources
for bundle in "$ROOT"/.build/release/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

# Ad-hoc-signera sa Gatekeeper inte klagar (lokalt bruk)
if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$APP" 2>/dev/null || true
fi

# Ta bort quarantine om filen kommer fran nedladdning
xattr -d com.apple.quarantine "$APP" 2>/dev/null || true

echo "==> Klart: $APP"
echo "    Starta med: open \"$APP\""
