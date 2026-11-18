"""Hämtar voice-overn från Google Cloud Text-to-Speech, en ljudfil per replikdel (vo_chunks/<scen>_<n>.wav).

Nyckel: miljövariabeln GOOGLE_TTS_API_KEY (en API-nyckel begränsad till Text-to-Speech API).
Röst: "voice" i script_en.json, t.ex. en-US-Chirp3-HD-Aoede. Kör sedan build.py.
Användning: python3 tts.py [--voice en-US-Chirp3-HD-Charon] [--rate 1.0]
"""
import argparse, base64, json, os, re, sys, urllib.request, urllib.error

ap = argparse.ArgumentParser()
ap.add_argument("--voice"); ap.add_argument("--rate", type=float, default=1.0)
args = ap.parse_args()
S = json.load(open("script_en.json"))
voice = args.voice or S["voice"]
key = os.environ.get("GOOGLE_TTS_API_KEY")
url = "https://texttospeech.googleapis.com/v1/text:synthesize" + (f"?key={key}" if key else "")

def synth(text):
    body = {"input": {"text": text},
            "voice": {"languageCode": "-".join(voice.split("-")[:2]), "name": voice},
            "audioConfig": {"audioEncoding": "LINEAR16", "sampleRateHertz": 44100, "speakingRate": args.rate}}
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return base64.b64decode(json.load(r)["audioContent"])
    except urllib.error.HTTPError as e:
        sys.exit(f"Google Text-to-Speech svarade {e.code}: {e.read().decode()[:400]}")

os.makedirs("vo_chunks", exist_ok=True)
for sc in S["scenes"]:
    for i, part in enumerate(sc["vo"]):
        text = re.sub(r"\{[\w:.]+\}", "", part).strip()
        if not text: continue
        open(f"vo_chunks/{sc['id']}_{i}.wav", "wb").write(synth(text))
        print(f"{sc['id']}_{i}: {text}")
print(f"klart med rösten {voice}")
