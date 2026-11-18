# Presentationsvideo

En ~75 sekunder lång video på engelska som presenterar StemSplitters funktioner, i appens formspråk.
Upplägget: rubrik och kort per funktion, muspekare som klickar, undertext som följer rösten, avslutning
på orange yta. Voice-over från Google Cloud Text-to-Speech, ingen musik.

## Bygga

```sh
export GOOGLE_TTS_API_KEY=...        # API-nyckel begränsad till Text-to-Speech API
./marketing/video/render.sh           # → marketing/video/StemSplitter-presentation.mp4
```

`./render.sh --new-voice` hämtar rösten på nytt (t.ex. efter ändrat manus eller röst).

## Filer

- `script_en.json` — manus per scen, röst (`voice`) och pauser. `{solo}` m.fl. kopplar ett ord till ett
  klick i animationen; `{pause:1.8}` ger bilden tid att visa något innan rösten fortsätter.
- `tts.py` — hämtar en ljudfil per replikdel från Google (`vo_chunks/`).
- `build.py` — bygger tidslinjen från röstens längd: scenernas tider, tidsomräkning för animationen,
  ordens tider för undertexten, UI-klick och metronom, samt `audio.wav`.
- `video.html` — själva videon (appens fönster, kamera, muspekare), renderas bildruta för bildruta.
- `render.js` — renderar bildrutor med Playwright; `node render.js stills 12,30` ger stillbilder.
- `timeline.json`, `peaks.json` — animationens grundtider och vågformer för demolåten.
