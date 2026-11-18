#!/bin/sh
# Bygger en fristående StemSplitter.app i build/
# Anvandning: ./scripts/build-app.sh   (fran repo-roten eller var som helst)
set -e
# pipefail så att ett fel i swift build inte döljs av tee
set -o pipefail 2>/dev/null || true

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> swift build -c release"
if ! swift build -c release 2>&1 | tee "$ROOT/.build-release.log"; then
    # Efter en Xcode-/SDK-uppdatering kan de förbyggda systemmodulerna i .build vara inaktuella
    # ("unexpected variant during dependency scanning on module ..."). Rensa dem och försök en gång till.
    if grep -q "unexpected variant during dependency scanning" "$ROOT/.build-release.log"; then
        echo "==> Inaktuell modulcache (troligen efter Xcode-uppdatering) — rensar och bygger om"
        rm -rf "$ROOT/.build/out/ModuleCache.noindex" \
               "$ROOT/.build/out/Intermediates.noindex/SwiftExplicitPrecompiledModules" \
               "$ROOT/.build/out/SDKExplicitPrecompiledModules" \
               "$ROOT/.build/out/SDKStatCaches.noindex" \
               "$ROOT/.build/ModuleCache"
        swift build -c release
    else
        rm -f "$ROOT/.build-release.log"
        exit 1
    fi
fi
rm -f "$ROOT/.build-release.log"

APP="$ROOT/build/StemSplitter.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$ROOT/.build/release/StemSplitter" "$APP/Contents/MacOS/StemSplitter"
cp "$ROOT/Packaging/Info.plist" "$APP/Contents/Info.plist"

# SPM-resursbunten (innehaller bootstrap.sh) maste med i Contents/Resources
for bundle in "$ROOT"/.build/release/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

# Bygg AppIcon.icns från färdiga PNG-filer (form, marginal och skugga finns redan i bilden).
# De minsta storlekarna använder en förenklad variant så att de syns i menyrader och Finder-listor.
echo "==> Genererar AppIcon.icns"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
icon() { sips -z "$1" "$1" -s format png "$ROOT/Packaging/$2" --out "$ICONSET/$3" >/dev/null; }
icon 16   AppIcon-small.png icon_16x16.png
icon 32   AppIcon-small.png icon_16x16@2x.png
icon 32   AppIcon-small.png icon_32x32.png
icon 64   AppIcon.png       icon_32x32@2x.png
icon 128  AppIcon.png       icon_128x128.png
icon 256  AppIcon.png       icon_128x128@2x.png
icon 256  AppIcon.png       icon_256x256.png
icon 512  AppIcon.png       icon_256x256@2x.png
icon 512  AppIcon.png       icon_512x512.png
icon 1024 AppIcon.png       icon_512x512@2x.png
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

# Skapa DMG for enkel delning (innehaller hela .app)
echo "==> Skapar StemSplitter.dmg"
DMG="$ROOT/build/StemSplitter.dmg"
rm -f "$DMG"
hdiutil create -volname StemSplitter -srcfolder "$APP" -ov -format UDZO "$DMG" >/dev/null

echo "==> Klart:"
echo "    $APP"
echo "    $DMG"
echo "    Starta lokalt med: open \"$APP\"  (forsta gangen: hogerklicka → Oppna om Gatekeeper klagar)"
