#!/bin/sh
# Bygger presentationsvideon: röst (Google TTS) → tidslinje → bildrutor → mp4.
# Kräver: python3 med numpy, Node med Playwright (Chromium), ffmpeg.
# Röst: GOOGLE_TTS_API_KEY i miljön (API-nyckel begränsad till Text-to-Speech API).
set -e
cd "$(dirname "$0")"
cp ../../Packaging/AppIcon.png AppIcon.png

if [ ! -d vo_chunks ] || [ "${1:-}" = "--new-voice" ]; then
    echo "==> Hämtar voice-over från Google Text-to-Speech"
    python3 tts.py
fi
echo "==> Bygger tidslinjen från rösten"
python3 build.py

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
    StemSplitter-presentation.mp4
echo "==> Klart: marketing/video/StemSplitter-presentation.mp4"
