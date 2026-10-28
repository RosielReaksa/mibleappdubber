const puppeteer = require('puppeteer-core');
const path = require('path');

const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const OUT = 'D:/projectradom/mibleappdubber/shots';
const BASE = 'http://localhost:8899';

const sleep = (ms) => new Promise(r => setTimeout(r, ms));

(async () => {
  const browser = await puppeteer.launch({
    executablePath: CHROME,
    headless: 'new',
    args: ['--no-first-run', '--disable-extensions', '--hide-scrollbars',
           '--force-device-scale-factor=2', '--use-gl=swiftshader'],
    defaultViewport: { width: 390, height: 844, deviceScaleFactor: 2, isMobile: false, hasTouch: false },
  });

  const targets = process.argv.slice(2);
  for (const t of targets) {
    const [name, url] = t.split('=');
    const page = await browser.newPage();
    const logs = [];
    page.on('console', m => logs.push(`[console.${m.type()}] ${m.text()}`));
    page.on('pageerror', e => logs.push(`[pageerror] ${e.message}`));
    page.on('requestfailed', r => logs.push(`[reqfail] ${r.url()} :: ${r.failure() && r.failure().errorText}`));
    page.on('response', r => { if (r.status() >= 400) logs.push(`[http ${r.status()}] ${r.url()}`); });

    try {
      await page.goto(url, { waitUntil: 'networkidle2', timeout: 90000 });
    } catch (e) { logs.push('[goto] ' + e.message); }

    // Wait for Flutter to paint something into the scene host
    let ready = false;
    for (let i = 0; i < 90; i++) {
      ready = await page.evaluate(() => {
        const gp = document.querySelector('flt-glass-pane');
        if (!gp) return false;
        const sh = gp.querySelector('flt-scene-host');
        return !!sh && sh.children.length > 0;
      }).catch(() => false);
      if (ready) break;
      await sleep(500);
    }
    await sleep(3500); // let animations/fonts settle

    const info = await page.evaluate(() => {
      const gp = document.querySelector('flt-glass-pane');
      const fv = document.querySelector('flutter-view');
      const cv = document.querySelectorAll('canvas');
      return {
        url: location.href,
        title: document.title,
        innerW: window.innerWidth, innerH: window.innerHeight,
        dpr: window.devicePixelRatio,
        flutterView: fv ? fv.getBoundingClientRect().toJSON() : null,
        canvasCount: cv.length,
        canvasSizes: Array.from(cv).map(c => `${c.width}x${c.height} css:${c.getBoundingClientRect().width}x${c.getBoundingClientRect().height}`),
        sceneHostChildren: gp && gp.querySelector('flt-scene-host') ? gp.querySelector('flt-scene-host').children.length : -1,
        bodyBg: getComputedStyle(document.body).backgroundColor,
        scrollW: document.documentElement.scrollWidth,
        scrollH: document.documentElement.scrollHeight,
      };
    }).catch(e => ({ evalError: e.message }));

    const file = path.join(OUT, name + '.png');
    await page.screenshot({ path: file, fullPage: false });
    console.log('\n===== ' + name + ' :: ' + url);
    console.log('INFO ' + JSON.stringify(info));
    console.log('READY ' + ready);
    console.log('LOGCOUNT ' + logs.length);
    logs.slice(0, 40).forEach(l => console.log('  ' + l));
    console.log('SAVED ' + file);
    await page.close();
  }
  await browser.close();
})().catch(e => { console.error('FATAL', e); process.exit(1); });
