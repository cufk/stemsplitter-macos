# StemSplitter — arbetsflöde för utveckling

macOS-app (SwiftUI + AVFoundation, SwiftPM) som delar upp ljudfiler i stems med Demucs lokalt.
Se README.md för funktioner och arkitektur. Skriv commit-meddelanden, kommentarer och UI-text på svenska.

## Branchar
- Standardbranch på GitHub är `vibe/stemsplitter-1c69f9` (den har all aktuell kod; `main` ligger efter).
- Varje ändring görs på en egen branch från standardbranchen: `claude/<kort-beskrivning>`.
- Små, fokuserade commits. PR mot standardbranchen; PR-mallen innehåller checklistan.

## Utvecklingsloopen
1. **Förstå** — läs berörd kod och befintliga tester innan du ändrar något.
2. **Lägg logik i `StemSplitterCore`** när det går (ren Swift + Foundation, ingen UI/AVFoundation).
   Det är den delen som enhetstestas. `StemSplitter`-målet (UI, ljudmotor) ska vara tunt.
3. **Skriv tester först eller samtidigt** i `Tests/StemSplitterCoreTests/` med swift-testing
   (`import Testing`, `@Test`, `#expect`). En buggfix kommer med ett test som hade fångat buggen.
4. **Verifiera**:
   - På en Mac: `./scripts/verify.sh` (bygg + test + dev-agent-tester), `--app` bygger även .app/.dmg.
   - I en Linux-/molnsession finns ingen Swift-toolchain: pusha branchen och kör
     `scripts/ci-wait.sh` — den väntar på CI för HEAD och skriver ut felen om något fallerar.
     Läs felen, rätta, pusha igen. Upprepa tills CI är grön.
5. **Påstå aldrig att något fungerar förrän CI är grön för exakt den commit det gäller.**
   Det som CI inte kan testa (UI, ljud, Demucs-körning) listas som manuella steg i PR:en.

## CI (`.github/workflows/ci.yml`, körs vid push till alla brancher)
- `swift` (macos-latest): `swift build` → `swift test` → `scripts/build-app.sh` → röktest av app-bunten
  (binär, Info.plist, ikon, resursbunt med bootstrap.sh, signatur) → kompilatorvarningar i sammanfattningen
  → `StemSplitter.dmg` laddas upp som artifact (`StemSplitter-<sha>`, 14 dagar) för manuell test.
- `dev-agent` (ubuntu): `python -m unittest discover -s tests` i `dev-agent/`.

## Kända fallgropar
- macOS-SDK:t på runnern ändras: API:er kan bli `async` (t.ex. `scheduleFile`). Bygg aldrig mot antaganden — läs CI-felet.
- Tester kräver hela Xcode, inte bara Command Line Tools.
- Ändra inte `dev-agent/` utan att köra dess tester; den pushar commits märkta `[dev-agent]`.
