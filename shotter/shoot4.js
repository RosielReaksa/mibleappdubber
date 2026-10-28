const puppeteer = require('puppeteer-core');
const fs = require('fs');
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const OUT = 'D:/projectradom/mibleappdubber/shots';

(async () => {
  const browser = await puppeteer.launch({
    executablePath: CHROME, headless: 'new',
    args: ['--no-first-run','--disable-extensions','--hide-scrollbars','--use-gl=swiftshader'],
  });
  const page = await browser.newPage();
  await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 1 });
  const client = await page.createCDPSession();
  await client.send('Network.enable');
  await client.send('Network.setCacheDisabled', { cacheDisabled: true });
  // throttle so the splash is visible longer
  await client.send('Network.emulateNetworkConditions', {
    offline: false, latency: 300, downloadThroughput: 400 * 1024, uploadThroughput: 200 * 1024,
  });
  let n = 0;
  client.on('Page.screencastFrame', async (f) => {
    n++;
    if (n <= 60) fs.writeFileSync(`${OUT}/70_slow_${String(n).padStart(2,'0')}.jpg`, Buffer.from(f.data, 'base64'));
    try { await client.send('Page.screencastFrameAck', { sessionId: f.sessionId }); } catch(e){}
  });
  await client.send('Page.startScreencast', { format: 'jpeg', quality: 85, maxWidth: 390, maxHeight: 844, everyNthFrame: 1 });
  await page.goto('http://localhost:8899/#/splash', { waitUntil: 'domcontentloaded', timeout: 120000 }).catch(e=>console.log('goto', e.message));
  await sleep(30000);
  await client.send('Page.stopScreencast').catch(()=>{});
  console.log('FRAMES=' + n + ' finalUrl=' + await page.evaluate(()=>location.href));
  await page.close();
  await browser.close();
})().catch(e => { console.error('FATAL', e); process.exit(1); });
