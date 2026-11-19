## Vad ändras
<!-- Kort: vad och varför -->

## Automatisk verifiering (CI)
- [ ] `swift build` grönt
- [ ] `swift test` grönt (nya/ändrade tester: …)
- [ ] `.app`/`.dmg` byggs och röktestet passerar
- [ ] Inga nya kompilatorvarningar

## Manuell verifiering på Mac
<!-- Ladda ner StemSplitter-<sha> från CI-körningens Artifacts. Bocka bara det som påverkas. -->
- [ ] Appen startar
- [ ] Välj/dra in en ljudfil → separering körs och framsteg visas
- [ ] Uppspelning: play/paus/stop/loop/sök, stems synkade
- [ ] Volym/mute per stem
- [ ] Pitch och tempo påverkar var sitt
- [ ] BPM visas och stämmer ungefär; klicket ligger på slagen och följer med när tempot ändras
- [ ] Export av mix ger en spelbar WAV
- [ ] Flera låtar/en mapp läggs i kön och separeras efter varandra; klara låtar kan öppnas medan kön arbetar
