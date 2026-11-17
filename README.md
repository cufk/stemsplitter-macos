# StemSplitter för macOS

En macOS-app som delar upp en **lokal ljudfil** i stems (sång, trummor, bas, övrigt) med lokal AI (Demucs) och låter dig styra volymen per stem — perfekt för att öva instrument eller sång till en låt du själv har rätt att använda.

All bearbetning sker **100 % lokalt på din Mac**. Ingen ljudfil skickas någonstans.

> **Juridisk not:** Appen arbetar bara med ljudfiler som finns lokalt på din dator och som du har rätt att använda (egna inspelningar, eller filer du har licens till). Appen kan inte — och ska inte — hämta musik från streamingtjänster som Deezer/Spotify, eftersom det skulle innebära att kringgå DRM-skydd och kopiera upphovsrättsskyddat material.

## Funktioner

- Välj en lokal ljudfil (WAV, AIFF, CAF, MP3, M4A, AAC, FLAC) via dialog, ⌘O eller drag-and-drop
- Stem-separering lokalt med [Demucs](https://github.com/facebookresearch/demucs) (`htdemucs`: sång / trummor / bas / övrigt), på GPU (MPS) när det går — kan avbrytas
- **Bibliotek** i sidofältet: separerade låtar sparas och öppnas direkt nästa gång (känns igen på innehållet, även om filen flyttats)
- Samplesynkron uppspelning med **volym, mute och solo per stem**
- **Tonläge** (±12 halvtoner) och **tempo** (0,5–2×) oberoende av varandra
- Play/paus, hopp ±5 s, loop och sökning — klicka direkt i en vågform för att hoppa dit
- Export av mixen som WAV med aktuella volymer, mute/solo, tonläge och tempo
- Gränssnitt i macOS 26-stil (Liquid Glass) med reservläge för macOS 14–15

## Krav

- macOS 14 (Sonoma) eller senare — bäst på macOS 26
- Python 3.9–3.12: appen söker själv på python.org:s och Homebrews standardplatser — saknas det får du en dialog som kan ladda ner och installera Python 3.12 från python.org automatiskt
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

## Bygg en fristående .app

```sh
./scripts/build-app.sh
open build/StemSplitter.app
```

Skriptet gor aven `build/StemSplitter.dmg` (fardig att skicka till vänner). Mottagaren dubbelklickar dmg:n, drar appen till Program, och forsta gangen hogerklick → Oppna (eller `xattr -dr com.apple.quarantine /Applications/StemSplitter.app`).

Skriptet kor `swift build -c release` och paketerar binären + `Packaging/Info.plist` + SPM-resursbunten (bootstrap.sh) till `build/StemSplitter.app`, ad-hoc-signar den och verifierar signaturen.

Om Gatekeeper ändå blockerar (t.ex. efter att appen kopierats/nedladdats, `spctl --assess` säger "rejected"):

```sh
xattr -cr build/StemSplitter.app
codesign --force --deep --sign - build/StemSplitter.app
open build/StemSplitter.app
```

Forsta gangen kan du också behöva högerklicka på appen → **Öppna** (eller Systeminställningar → Integritet och säkerhet → "Öppna ändå"). För notarering/distribution utanför din egen Mac krävs ett Apple Developer-konto (Xcode → Product → Archive).

## CI och dev-agent

- `.github/workflows/ci.yml` körs vid push till alla brancher: `swift build`, `swift test`, bygger `.app`/`.dmg` med röktest, sammanfattar kompilatorvarningar och laddar upp `StemSplitter.dmg` som artifact. Dev-agentens Python-tester körs i ett eget jobb.
- `./scripts/verify.sh [--app]` kör samma kontroller lokalt på en Mac.
- `scripts/ci-wait.sh [sha]` väntar på CI för en commit och skriver ut felen om den blir röd.
- Arbetsflödet för utveckling beskrivs i `CLAUDE.md`.
- `dev-agent/` innehåller ett Mistral Workflow (`dev-agent`) som bevakar CI för branchen, hämtar fel-loggar vid röda körningar, låter en LLM föreslå en fix (unified diff), pushar den med `[dev-agent]`-markör och loopar tills CI är grön. Se `dev-agent/README.md` för driftsättning (kräver workspace-secret `github_token`).

## Arkitektur

```
Sources/
  StemSplitterCore/        Ren, testbar logik (ingen UI/AVFoundation):
    Transport              position, sök, hopp och segment för uppspelningen
    MixMath                effektiv volym (mute/solo), klippning, exportlängd, halvtoner → cent
    CacheKey               innehållsbaserad cache-nyckel (FNV-1a över storlek + första/sista MB)
    PeakAccumulator        vågformstoppar i hinkar
    ProjectMeta            project.json: källnamn, datum, modell, cachade vågformer
    PythonVersion          tolkning och stödda versioner (3.9–3.12) + sökvägar att leta på
    StemKind, StemLocator, TimeFormat, ProgressParser, AudioFileSupport
  StemSplitter/            Appen (SwiftUI + AVFoundation):
    StemSplitterApp        fönster, menyer, inställningar, avslutar underprocesser vid stängning
    AppViewModel           tillstånd: avbrytbar laddning, bibliotek, mix, export
    ContentView            NavigationSplitView: bibliotek + spelare, verktygsfält, drag-and-drop
    PlayerView / StemRowView / TransportBar / StatusViews / LibrarySidebar / SettingsView
    Glass                  Liquid Glass på macOS 26, material som reserv
    WaveformView           vågform (Canvas) + spelhuvud som enda vy som följer positionen
    PlaybackEngine         ljudgraf som byggs en gång: spelare → stem-mixer → tonhöjd/tempo
    MixerExporter          offline-rendering genom samma kedja
    SeparationService      Python-miljö + Demucs, med avbrytning och städning
    ProcessRunner          kör processer, strömmar rader, avbryts med Task.cancel()
    ProjectStore           cachen: atomiska projekt, lista, ta bort, storlek
    AudioConverter         valfritt format → 44,1 kHz stereo WAV (inkl. 48 kHz och mono)
    Resources/bootstrap.sh skapar venv och installerar Demucs (Apple Silicon och Intel)
Tests/
  StemSplitterCoreTests/   enhetstester för kärnlogiken (swift-testing)
```

## Så fungerar det

1. Du väljer en lokal ljudfil. En nyckel räknas fram ur filens innehåll; finns låten redan i biblioteket öppnas den direkt.
2. Första gången skapas `~/Library/Application Support/StemSplitter/venv` och Demucs installeras där (torch 2.5.1 på Apple Silicon, 2.2.2 på Intel).
3. Filer som inte är WAV konverteras först till 44,1 kHz stereo-WAV via AVFoundation (så Demucs slipper ffmpeg).
4. Demucs körs lokalt på GPU (MPS) eller CPU. Stems flyttas atomiskt till `projects/<nyckel>/` och arbetsfilerna tas bort.
5. Uppspelningen använder en `AVAudioPlayerNode` per stem → en gemensam mixer → en `AVAudioUnitTimePitch`. Alla spelare startar på samma host-tid.
6. Exporten renderar samma kedja offline, klipper till [-1, 1] och skriver en float32-WAV.
