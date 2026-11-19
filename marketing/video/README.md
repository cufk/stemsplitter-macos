# Presentationsvideo

En ~63 sekunder lång video på engelska som presenterar StemSplitters funktioner, i appens formspråk.
Upplägget: rubrik och kort per funktion, muspekare som klickar, undertext som följer rösten, avslutning
på orange yta. Ingen musik.

Voice-over: Kokoro (öppen talmodell, Apache 2.0) som körs lokalt — ingen nyckel eller konto behövs.
Röst `af_heart`, ändras med `kokoro_voice` i `script_en.json`. Finns `GOOGLE_TTS_API_KEY` används
Google Cloud Text-to-Speech i stället (`voice`).

## Videor

- `script_en.json` — huvudvideon som presenterar hela appen (~63 s).
- `whats_new_<version>.json` — kort video om nyheterna i en version, t.ex. `whats_new_1.3.json` (kön).
  En ny sådan görs för varje version med nya funktioner (se `CLAUDE.md`).

## Bygga

```sh
pip install kokoro-onnx numpy        # en gång; modellfilerna (~350 MB) hämtas automatiskt
./marketing/video/render.sh                       # → StemSplitter-presentation.mp4
./marketing/video/render.sh whats_new_1.3.json    # → StemSplitter-whats_new_1.3.mp4
```

`./render.sh --new-voice` hämtar rösten på nytt (t.ex. efter ändrat manus eller röst).

## Filer

- `script_en.json` — manus per scen, röst (`voice`) och pauser. `{solo}` m.fl. kopplar ett ord till ett
  klick i animationen; `{pause:1.8}` ger bilden tid att visa något innan rösten fortsätter.
- `tts.py` — skapar en ljudfil per replikdel (`vo_chunks/`) med Kokoro, eller Google om nyckel finns.
- `build.py` — bygger tidslinjen från röstens längd: scenernas tider, tidsomräkning för animationen,
  ordens tider för undertexten, UI-klick och metronom, samt `audio.wav`.
- `video.html` — själva videon (appens fönster, kamera, muspekare), renderas bildruta för bildruta.
- `render.js` — renderar bildrutor med Playwright; `node render.js stills 12,30` ger stillbilder.
- `timeline.json`, `peaks.json` — animationens grundtider och vågformer för demolåten.
