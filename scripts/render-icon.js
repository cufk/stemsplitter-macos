// Renderar appikonen från Packaging/icon/AppIcon.html (SVG) till PNG.
// Kräver Node och Playwright med Chromium:  npx playwright install chromium
// Användning (från repo-roten): node scripts/render-icon.js
const path = require('path');
const fs = require('fs');
const { chromium } = require('playwright');

const root = path.resolve(__dirname, '..');
const source = 'file://' + path.join(root, 'Packaging/icon/AppIcon.html');

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1024, height: 1024 }, deviceScaleFactor: 1 });
  const outputs = [
    ['', 'Packaging/AppIcon.png'],               // 64 px och uppåt
    ['?small=1', 'Packaging/AppIcon-small.png'], // 16–32 px: färre, tjockare staplar
  ];
  for (const [query, out] of outputs) {
    await page.goto(source + query);
    await page.locator('#s').screenshot({ path: path.join(root, out), omitBackground: true });
    console.log('skrev', out);
  }
  fs.copyFileSync(path.join(root, 'Packaging/AppIcon.png'), path.join(root, 'Sources/StemSplitter/Resources/appicon.png'));
  console.log('kopierade till Sources/StemSplitter/Resources/appicon.png');
  await browser.close();
})();
