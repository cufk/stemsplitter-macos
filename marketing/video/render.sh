#!/bin/sh
# Bygger en video: röst → tidslinje → bildrutor → mp4.
# Användning: ./render.sh [manus.json] [--new-voice]
#   ./render.sh                         huvudvideon (script_en.json)
#   ./render.sh whats_new_1.3.json      "What's new"-video för en version
# Kräver: python3 med numpy, Node med Playwright (Chromium), ffmpeg.
# Röst: Kokoro lokalt (pip install kokoro-onnx), eller Google om GOOGLE_TTS_API_KEY finns.
set -e
cd "$(dirname "$0")"
SCRIPT="script_en.json"
NEW_VOICE=""
for arg in "$@"; do
    case "$arg" in
        --new-voice) NEW_VOICE=1 ;;
        *.json) SCRIPT="$arg" ;;
    esac
done
NAME=$(basename "$SCRIPT" .json)
OUT="StemSplitter-presentation.mp4"
[ "$SCRIPT" != "script_en.json" ] && OUT="StemSplitter-$NAME.mp4"
cp ../../Packaging/AppIcon.png AppIcon.png

if [ ! -d "vo_chunks/$NAME" ] || [ -n "$NEW_VOICE" ]; then
    echo "==> Skapar voice-over ($SCRIPT)"
    python3 tts.py "$SCRIPT"
fi
echo "==> Bygger tidslinjen från rösten"
python3 build.py "$SCRIPT"

FRAMES=$(python3 -c "import json;d=json.load(open('timeline_real.json'));print(int(d['duration']*d['fps']))")
echo "==> Renderar $FRAMES bildrutor"
rm -rf frames
W=4
i=0
while [ $i -lt $W ]; do
    node render.js frames $((i * FRAMES / W)) $(((i + 1) * FRAMES / W)) &
    i=$((i + 1))
done
wait

echo "==> Kodar video"
ffmpeg -v error -y -framerate 30 -i frames/f%05d.jpg -i audio.wav \
    -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart -shortest \
    "$OUT"
echo "==> Klart: marketing/video/$OUT"
