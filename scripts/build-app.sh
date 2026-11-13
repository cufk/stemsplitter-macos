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

# Bygg AppIcon.icns fran Packaging/AppIcon.jpg (sips + iconutil finns pa macOS)
echo "==> Genererar AppIcon.icns"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" -s format png "$ROOT/Packaging/AppIcon.jpg" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z "$((size * 2))" "$((size * 2))" -s format png "$ROOT/Packaging/AppIcon.jpg" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc-signera sa Gatekeeper inte klagar (lokalt bruk)
if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$APP"
    if codesign --verify --deep --strict -v "$APP" 2>/dev/null; then
        echo "==> Signatur verifierad (ad-hoc)"
    else
        echo "==> VARNING: signaturen kunde inte verifieras — Gatekeeper kan blockera appen"
    fi
fi

# Ta bort quarantine om filen kommer fran nedladdning/overforing
xattr -cr "$APP" 2>/dev/null || true

echo "==> Klart: $APP"
echo "    Starta med: open \"$APP\"  (forsta gangen: hogerklicka → Oppna om Gatekeeper klagar)"
