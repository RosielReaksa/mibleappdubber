const puppeteer = require('puppeteer-core');
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const OUT = 'D:/projectradom/mibleappdubber/shots';

(async () => {
  const browser = await puppeteer.launch({
    executablePath: CHROME, headless: 'new',
    args: ['--no-first-run', '--disable-extensions', '--hide-scrollbars', '--use-gl=swiftshader'],
  });

  // A) Wide desktop viewport
  {
    const page = await browser.newPage();
    await page.setViewport({ width: 1280, height: 900, deviceScaleFactor: 1 });
    const logs = [];
    page.on('console', m => logs.push(`[${m.type()}] ${m.text()}`));
    page.on('pageerror', e => logs.push('[pageerror] ' + e.message));
    await page.goto('http://localhost:8899/', { waitUntil: 'networkidle2', timeout: 90000 });
    await sleep(12000);
    const info = await page.evaluate(() => {
      const fv = document.querySelector('flutter-view');
      return { url: location.href, fv: fv ? fv.getBoundingClientRect().toJSON() : null,
               bodyBg: getComputedStyle(document.body).backgroundColor,
               htmlBg: getComputedStyle(document.documentElement).backgroundColor };
    });
    await page.screenshot({ path: OUT + '/20_wide_1280.png' });
    console.log('WIDE ' + JSON.stringify(info));
    logs.forEach(l => console.log('  ' + l));
    await page.close();
  }

  // B) Splash: capture frames from t=0
  {
    const page = await browser.newPage();
    await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 2 });
    await page.goto('about:blank');
    page.goto('http://localhost:8899/', { waitUntil: 'domcontentloaded', timeout: 60000 }).catch(()=>{});
    for (const ms of [700, 1500, 2500, 4000, 6000, 9000, 13000]) {
      await sleep(ms === 700 ? 700 : 0);
      const cur = await page.evaluate(() => location.href).catch(()=> '?');
      await page.screenshot({ path: `${OUT}/30_splash_t${ms}.png` }).catch(()=>{});
      console.log(`t~${ms} url=${cur}`);
      if (ms !== 13000) await sleep(ms === 700 ? 800 : (ms === 1500 ? 1000 : 1500));
    }
    await page.close();
  }

  // C) Path-based routing (no hash)
  for (const p of ['/login', '/signup', '/onboarding', '/forgot']) {
    const page = await browser.newPage();
    await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 2 });
    const st = [];
    page.on('response', r => { if (r.status() >= 400) st.push(r.status() + ' ' + r.url()); });
    try { await page.goto('http://localhost:8899' + p, { waitUntil: 'networkidle2', timeout: 60000 }); } catch(e) { st.push('goto: ' + e.message); }
    await sleep(9000);
    const u = await page.evaluate(() => location.href).catch(()=>'?');
    await page.screenshot({ path: `${OUT}/40_path_${p.replace('/','')}.png` });
    console.log(`PATH ${p} -> ${u} ${st.join(' | ')}`);
    await page.close();
  }

  await browser.close();
})().catch(e => { console.error('FATAL', e); process.exit(1); });
