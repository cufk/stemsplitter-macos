"""Bygger videons tidslinje från voice-overn.

Varje scen: kort paus → repliken (delar med naturliga pauser) → luft. Markeringar som {solo} i manuset
kopplas till tidpunkter i animationen (designtid), så att t.ex. klicket på solo sker när rösten säger det.
Utan inspelade röstdelar (vo_chunks/) används uppskattade längder, för förhandsvisning.
"""
import json, os, re, wave
import numpy as np

SR = 44100
import sys
SCRIPT = sys.argv[1] if len(sys.argv) > 1 else "script_en.json"
S = json.load(open(SCRIPT))
CHUNKS = "vo_chunks/" + os.path.splitext(os.path.basename(SCRIPT))[0]
T = json.load(open("timeline.json"))
BEAT = 60 / 100.0

def chunk_audio(scene, i):
    p = f"{CHUNKS}/{scene}_{i}.wav"
    if not os.path.exists(p): return None
    with wave.open(p) as w:
        x = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2") / 32768.0
        sr = w.getframerate()
    if sr != SR: x = np.interp(np.linspace(0, len(x) - 1, int(len(x) * SR / sr)), np.arange(len(x)), x)
    return x

def clean(text): return re.sub(r"\{[\w:.]+\}", "", text).strip()

real_t = 0.0
scene_pts = []     # (design-start, design-slut, brytpunkter) per scen
warp = []          # [verklig tid, designtid]
captions = []      # {t0, t1, words:[[ord, tid]]}
scenes_out = []
vo_parts = []      # (start, ljud)
estimated = False
for sc in S["scenes"]:
    d0, d1 = sc["design"]
    r0 = real_t
    t = r0 + (0.6 if sc["id"] == "intro" else S["lead"])
    marks = {}
    words = []
    for i, part in enumerate(sc["vo"]):
        pause = re.fullmatch(r"\{pause:([\d.]+)\}", part.strip())
        if pause:            # paus i rösten så att bilden hinner visa det som händer
            t += float(pause.group(1)); continue
        text = clean(part)
        mark_pos = []   # (namn, andel av texten före markeringen)
        for mm in re.finditer(r"\{(\w+)\}", part):
            before = clean(part[: mm.start()])
            mark_pos.append((mm.group(1), len(before) / max(1, len(text))))
        audio = chunk_audio(sc["id"], i)
        if audio is None:
            estimated = True
            dur = len(text.split()) / 2.7 + 0.15
        else:
            dur = len(audio) / SR
            vo_parts.append((t, audio))
        for name, frac in mark_pos: marks[name] = t + dur * frac
        # ordens tider fördelas efter längd inom delen
        ws = text.split(); weights = [len(re.sub(r"\W", "", w)) + 1.5 for w in ws]; acc = 0
        for w, wt in zip(ws, weights):
            words.append([w, round(t + dur * acc / sum(weights), 3)]); acc += wt
        t += dur
        t += S["gap_sentence"] if text.rstrip().endswith((".", "?", "!")) else S["gap_comma"]
    vo_end = t
    # scenens slut: luft efter rösten, men minst så att animationen efter sista markeringen hinner
    last_anchor = max((sc.get("anchors") or {}).values(), default=d0)
    last_mark = max(marks.values(), default=r0)
    min_after = (d1 - last_anchor) * 0.75
    r1 = max(vo_end + S["tail"], last_mark + min_after, r0 + 2.5)
    # brytpunkter för tidsförvrängningen
    pts = [(r0, d0)]
    for name, dt in sorted((sc.get("anchors") or {}).items(), key=lambda kv: kv[1]):
        if name in marks: pts.append((marks[name] + 0.12, dt))   # klicket strax efter ordets början
    pts.append((r1, d1))
    scene_pts.append((d0, d1, [(round(a, 3), b) for a, b in pts]))
    for a, b in pts:
        a = round(a, 3)
        if warp and a <= warp[-1][0]:
            if b == warp[-1][1]: continue          # samma punkt
            # nästa scen kan ligga var som helst i animationens tid: klipp direkt dit
            a = round(warp[-1][0] + 0.02, 3)
        warp.append([a, b])
    # Undertexten visas en mening i taget (som i förlagan): dela orden vid meningsslut
    groups, current = [], []
    for w in words:
        current.append(w)
        if w[0].rstrip("\"'”").endswith((".", "?", "!")):
            groups.append(current); current = []
    if current: groups.append(current)
    for gi, group in enumerate(groups):
        c0 = r0 if gi == 0 else round(group[0][1] - 0.15, 3)
        c1 = r1 if gi == len(groups) - 1 else round(groups[gi + 1][0][1] - 0.15, 3)
        captions.append({"scene": sc["id"], "t0": round(c0, 3), "t1": round(c1, 3), "words": group})
    out = {k: sc[k] for k in ("id", "tag", "title", "sub") if k in sc}
    out.update(t0=d0, t1=d1, caption=" ".join(clean(p) for p in sc["vo"] if not p.startswith("{pause")), real=[round(r0, 3), round(r1, 3)], marks={k: round(v, 3) for k, v in marks.items()})
    scenes_out.append(out)
    real_t = r1

total = round(real_t + 0.4, 3)
warp.append([total, scenes_out[-1]["t1"]])

def design_to_real(d):
    """Verklig tid för en tidpunkt i animationen, inom den scen som innehåller den (None om ingen gör det)."""
    for d0, d1, pts in scene_pts:
        if d0 <= d < d1:
            return float(np.interp(d, [p[1] for p in pts], [p[0] for p in pts]))
    return None

# metronomklick: från klicket i klickscenen till scenens slut, i 100 BPM
metronome = []
click_scene = next((s for s in scenes_out if s["id"] == "click"), None)
if click_scene:
    start = click_scene["marks"].get("click", click_scene["real"][0]) + 0.35
    k = 0
    while start + k * BEAT < click_scene["real"][1] - 0.2:
        metronome.append([round(start + k * BEAT, 3), k % 4 == 0]); k += 1

# Muspekarens klick (animationens tid) — bara de som hör till scener i manuset
UI_CLICKS = [9.9, 30.0, 33.5, 34.6, 37.4, 38.4, 39.0, 41.7, 42.0, 42.45, 48.0, 54.7, 55.35, 58.55,
             102.0, 103.0, 109.6]
ui_clicks = [round(r, 3) for r in (design_to_real(d) for d in UI_CLICKS) if r is not None]

T.update(duration=total, fps=30, scenes=scenes_out, warp=warp, captions=captions, metronome=metronome, uiClicks=ui_clicks,
         introPill=S.get("introPill", "Now on macOS"), version=S.get("version"))
json.dump(T, open("timeline_real.json", "w"), ensure_ascii=False, indent=1)

# ---- ljud: röst + diskreta UI-klick + metronom
n = int(total * SR); audio = np.zeros(n)
for t0, x in vo_parts:
    p = int(t0 * SR); m = min(len(x), n - p); audio[p:p + m] += x[:m]
rng = np.random.default_rng(3)
def tick():
    m = int(0.025 * SR); tt = np.arange(m) / SR
    return (np.sin(2 * np.pi * 2400 * tt) * 0.5 + rng.standard_normal(m) * 0.3) * np.exp(-tt / 0.004) * 0.05
def metro(acc):
    m = int(0.04 * SR); tt = np.arange(m) / SR
    return np.sin(2 * np.pi * (1760 if acc else 1200) * tt) * np.exp(-tt / 0.007) * (0.16 if acc else 0.11)
for t0 in ui_clicks:
    x = tick(); p = int(t0 * SR); audio[p:p + len(x)] += x[: max(0, n - p)]
for t0, acc in metronome:
    x = metro(acc); p = int(t0 * SR); audio[p:p + len(x)] += x[: max(0, n - p)]
if vo_parts:
    peak = np.abs(audio).max(); audio = audio / peak * 0.89
pcm = (np.clip(audio, -1, 1) * 32767).astype("<i2")
with wave.open("audio.wav", "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
print(f"längd {total:.1f} s ({'uppskattad, ingen röst ännu' if estimated else 'från röstinspelningen'})")
for s in scenes_out: print(f"  {s['id']:9s} {s['real'][0]:5.1f}–{s['real'][1]:5.1f}  markeringar {s['marks']}")
