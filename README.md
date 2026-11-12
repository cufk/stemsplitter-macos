# StemSplitter för macOS

En macOS-app som delar upp en **lokal ljudfil** i stems (sång, trummor, bas, övrigt) med lokal AI (Demucs) och låter dig styra volymen per stem — perfekt för att öva instrument eller sång till en låt du själv har rätt att använda.

All bearbetning sker **100 % lokalt på din Mac**. Ingen ljudfil skickas någonstans.

> **Juridisk not:** Appen arbetar bara med ljudfiler som finns lokalt på din dator och som du har rätt att använda (egna inspelningar, eller filer du har licens till). Appen kan inte — och ska inte — hämta musik från streamingtjänster som Deezer/Spotify, eftersom det skulle innebära att kringgå DRM-skydd och kopiera upphovsrättsskyddat material.

## Funktioner

- Välj en lokal ljudfil (WAV, AIFF, CAF, MP3, M4A, AAC, FLAC) via dialog eller drag-and-drop
- Stem-separation lokalt med [Demucs](https://github.com/facebookresearch/demucs) (`htdemucs`: sång / trummor / bas / övrigt)
- Uppspelning med **individuell volym och mute per stem**, synkroniserad uppspelning
- Play / paus / stop / loop och sökning i låten
- Vågformsvisning per stem
- Export av en mixad WAV-fil med dina aktuella volyminställningar

## Krav

- macOS 14 (Sonoma) eller senare
- Python 3.9+ (installera "Command Line Tools for Xcode" eller python.org-paketet om `python3` saknas)
- **Hela Xcode krävs** (från App Store) — Command Line Tools saknar makro-plugins (`SwiftUIMacros`, `TestingMacros`) och XCTest, så varken appen (SwiftUI) eller testerna kan byggas med enbart CLT.
- Internet första gången appen körs: då skapas en virtuell Python-miljö och PyTorch (CPU) + Demucs-modellen laddas ner (någon GB). Därefter fungerar allt offline.

## Bygga och köra

```sh
git clone <repo-url>
cd stemsplitter-macos
swift run            # bygger och startar appen
```

eller öppna `Package.swift` i Xcode och kör målserien `StemSplitter`.

Testa kärnlogiken:

```sh
swift test
```

### Felsökning vid `swift test`

Testerna använder **swift-testing**. Två typiska fel med enbart Command Line Tools (CLT):

- `unable to resolve module dependency: 'XCTest'` — CLT:s SDK saknar XCTest
- `plugin for module 'TestingMacros' not found` — CLT saknar makro-pluginet `libTestingMacros.dylib`, så `@Test`/`#expect` kan inte expanderas

Båda betyder samma sak: **tester kräver hela Xcode**, CLT räcker inte. Så här fixar du det:

1. Installera Xcode från App Store om det saknas (`ls /Applications`).
2. Byt aktivt verktyg och acceptera licensen:
   ```sh
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -license accept
   ```
3. Rensa cache och kör testerna:
   ```sh
   cd ~/stemsplitter-macos
   rm -rf .build
   swift test
   ```

Efter Xcode-installationen: `swift run` startar appen, `swift test` kör testerna.

## Arkitektur

```
Sources/
  StemSplitterCore/        Ren, testbar logik (ingen UI/AVFoundation):
    StemKind               sång/trummor/bas/övrigt + svenska namn
    StemLocator            hittar stem-filer i en katalog
    MixMath                gain/mixning/clamp av ljudkanaler
    TimeFormat             tidsformatering (m:ss)
    ProgressParser         parsar procent från Demucs-utdata
    AudioFileSupport       vilka filändelser som stöds
  StemSplitter/            Själva appen (SwiftUI + AVFoundation):
    StemSplitterApp        appens entry point
    AppViewModel           övergripande tillstånd (idle/busy/ready/failed)
    ContentView            huvudfönster
    StemRowView            en rad per stem (volym, mute, vågform)
    WaveformView           ritning av vågform
    PlaybackEngine         synkroniserad uppspelning via AVAudioEngine
    SeparationService      venv + kör Demucs lokalt, strömmar framsteg
    MixerExporter          exporterar mixad WAV chunk för chunk
    WaveformComputer       beräknar vågformstoppar från en fil
    Resources/bootstrap.sh skapar venv och installerar demucs
Tests/
  StemSplitterCoreTests/   enhetstester för kärnlogiken
```

## Så fungerar det

1. Du väljer en lokal ljudfil.
2. Vid första körningen skapas `~/Library/Application Support/StemSplitter/venv` och Demucs installeras där.
3. Demucs körs lokalt: `demucs -n htdemucs -o <tmp> <fil>` → `sång.wav`, `trummor.wav`, `bas.wav`, `övrigt.wav`.
4. Stemsen kopieras till ett projekt under `~/Library/Application Support/StemSplitter/projects/` och laddas i en `AVAudioEngine` med en `AVAudioPlayerNode` per stem. Alla noder schemaläggs på samma absoluta host-tid, så uppspelningen är samplesynkron.
5. Volym per stem sätts direkt på respektive spelare (`AVAudioPlayerNode.volume`).
6. Export mixar alla stems chunk-för-chunk (sång×gain + trummor×gain + …, klipps till [-1, 1]) och skriver en float32-WAV.
