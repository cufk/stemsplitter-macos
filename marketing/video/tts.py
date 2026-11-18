"""Skapar voice-overn, en ljudfil per replikdel (vo_chunks/<scen>_<n>.wav). Kör sedan build.py.

Standard: Kokoro, en öppen talmodell (Apache 2.0) som körs lokalt — ingen nyckel behövs.
Modellfilerna hämtas automatiskt till ./kokoro första gången (~350 MB).
Alternativ: Google Cloud Text-to-Speech om GOOGLE_TTS_API_KEY finns (--engine google).

Användning: python3 tts.py [--engine kokoro|google] [--voice af_heart] [--speed 1.0]
"""
import argparse, base64, json, os, re, sys, urllib.request, urllib.error, wave
import numpy as np

ap = argparse.ArgumentParser()
ap.add_argument("--engine", choices=["kokoro", "google"])
ap.add_argument("--voice"); ap.add_argument("--speed", type=float)
args = ap.parse_args()
S = json.load(open("script_en.json"))
engine = args.engine or ("google" if os.environ.get("GOOGLE_TTS_API_KEY") else "kokoro")
speed = args.speed or S.get("speed", 1.0)

def write_wav(path, samples, sr):
    pcm = (np.clip(samples, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr); w.writeframes(pcm.tobytes())

if engine == "kokoro":
    from kokoro_onnx import Kokoro
    voice = args.voice or S.get("kokoro_voice", "af_heart")
    model_dir = os.environ.get("KOKORO_DIR", "kokoro")
    os.makedirs(model_dir, exist_ok=True)
    base = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/"
    for f in ("kokoro-v1.0.onnx", "voices-v1.0.bin"):
        if not os.path.exists(os.path.join(model_dir, f)):
            print("hämtar", f); urllib.request.urlretrieve(base + f, os.path.join(model_dir, f))
    kokoro = Kokoro(os.path.join(model_dir, "kokoro-v1.0.onnx"), os.path.join(model_dir, "voices-v1.0.bin"))
    def synth(text, path):
        samples, sr = kokoro.create(text, voice=voice, speed=speed, lang="en-us")
        # beskär tystnad i kanterna
        idx = np.where(np.abs(samples) > 0.01)[0]
        if len(idx): samples = samples[max(0, idx[0] - int(0.02 * sr)): idx[-1] + int(0.06 * sr)]
        write_wav(path, samples, sr)
else:
    key = os.environ.get("GOOGLE_TTS_API_KEY")
    voice = args.voice or S.get("voice", "en-US-Chirp3-HD-Aoede")
    url = "https://texttospeech.googleapis.com/v1/text:synthesize" + (f"?key={key}" if key else "")
    def synth(text, path):
        body = {"input": {"text": text},
                "voice": {"languageCode": "-".join(voice.split("-")[:2]), "name": voice},
                "audioConfig": {"audioEncoding": "LINEAR16", "sampleRateHertz": 44100, "speakingRate": speed}}
        req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                open(path, "wb").write(base64.b64decode(json.load(r)["audioContent"]))
        except urllib.error.HTTPError as e:
            sys.exit(f"Google Text-to-Speech svarade {e.code}: {e.read().decode()[:400]}")

os.makedirs("vo_chunks", exist_ok=True)
for f in os.listdir("vo_chunks"): os.remove(os.path.join("vo_chunks", f))
for sc in S["scenes"]:
    for i, part in enumerate(sc["vo"]):
        text = re.sub(r"\{[\w:.]+\}", "", part).strip()
        if not text: continue
        synth(text, f"vo_chunks/{sc['id']}_{i}.wav")
        print(f"  {sc['id']}_{i}: {text}")
print(f"klart: {engine}, röst {voice}")
