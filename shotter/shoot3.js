const puppeteer = require('puppeteer-core');
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const OUT = 'D:/projectradom/mibleappdubber/shots';

(async () => {
  const browser = await puppeteer.launch({
    executablePath: CHROME, headless: 'new',
    args: ['--no-first-run','--disable-extensions','--hide-scrollbars','--use-gl=swiftshader'],
  });

  // 1) Direct #/splash
  {
    const page = await browser.newPage();
    await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 2 });
    await page.goto('http://localhost:8899/#/splash', { waitUntil: 'networkidle2', timeout: 90000 });
    await sleep(8000);
    const u = await page.evaluate(() => location.href);
    await page.screenshot({ path: OUT + '/50_route_splash.png' });
    console.log('SPLASH_ROUTE url_after=' + u);
    await page.close();
  }

  // 2) Early frames via CDP screencast on a cold load
  {
    const page = await browser.newPage();
    await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 1 });
    const client = await page.createCDPSession();
    let n = 0;
    const seen = [];
    client.on('Page.screencastFrame', async (f) => {
      n++;
      if (n <= 40) {
        require('fs').writeFileSync(`${OUT}/60_frame_${String(n).padStart(2,'0')}.jpg`, Buffer.from(f.data, 'base64'));
        seen.push(n);
      }
      try { await client.send('Page.screencastFrameAck', { sessionId: f.sessionId }); } catch(e){}
    });
    await client.send('Page.startScreencast', { format: 'jpeg', quality: 80, maxWidth: 390, maxHeight: 844, everyNthFrame: 1 });
    await page.goto('http://localhost:8899/', { waitUntil: 'domcontentloaded', timeout: 60000 }).catch(()=>{});
    await sleep(9000);
    await client.send('Page.stopScreencast').catch(()=>{});
    console.log('FRAMES_CAPTURED=' + n);
    await page.close();
  }

  await browser.close();
})().catch(e => { console.error('FATAL', e); process.exit(1); });
