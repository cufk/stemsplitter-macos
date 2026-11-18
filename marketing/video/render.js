// node render.js stills t1,t2,...   eller   node render.js frames <start> <end> <workerId>
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
const dir = __dirname;
const TL = JSON.parse(fs.readFileSync(path.join(dir, fs.existsSync(path.join(dir, 'timeline_real.json')) ? 'timeline_real.json' : 'timeline.json')));
const PK = JSON.parse(fs.readFileSync(path.join(dir, 'peaks.json')));
const VO = [];
(async () => {
  const [mode, a, b] = process.argv.slice(2);
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  page.on('pageerror', e => console.error('pageerror', e.message));
  await page.addInitScript(([tl, pk, vo]) => { window.TIMELINE = tl; window.PEAKS = pk; window.VO = vo; }, [TL, PK, VO]);
  await page.goto('file://' + path.join(dir, 'video.html'));
  await page.evaluate(() => document.fonts.ready);
  if (mode === 'stills') {
    fs.mkdirSync(path.join(dir, 'stills'), { recursive: true });
    for (const t of a.split(',').map(Number)) {
      await page.evaluate(t => window.render(t), t);
      await page.screenshot({ path: path.join(dir, 'stills', `t${String(t).padStart(5, '0')}.png`) });
    }
  } else {
    const fps = TL.fps; fs.mkdirSync(path.join(dir, 'frames'), { recursive: true });
    for (let f = Number(a); f < Number(b); f++) {
      await page.evaluate(t => window.render(t), f / fps);
      await page.screenshot({ path: path.join(dir, 'frames', `f${String(f).padStart(5, '0')}.jpg`), type: 'jpeg', quality: 92 });
    }
  }
  await browser.close();
})();
