// barcode.html in a browser: what it reads, where it reads, and on which
// thread, with a camera drawn on a canvas.
const { test, expect } = require('@playwright/test');
const { fakeCamera } = require('./fake_camera');

const EAN = '4006381333931';

// Opens the page as the web host does, reading continuously.
async function open(page, camera, query) {
  await page.addInitScript(fakeCamera, camera || {});
  const params = new URLSearchParams(Object.assign({
    start: '1',
    host: 'web',
    continuous: '1',
    formats: 'all',
    window: 'wide'
  }, query || {}));
  await page.goto(`/barcode.html?${params}`);
}

function codes(page) {
  return page.evaluate(() => window.__posts.filter((p) => p.code));
}

async function expectRead(page, text) {
  await expect.poll(async () => (await codes(page)).map((p) => p.code), {
    timeout: 20000
  }).toContain(text);
}

// Reading for a while and finding nothing.
async function expectNothingFor(page, ms) {
  await page.waitForTimeout(ms);
  expect(await codes(page)).toEqual([]);
}

// Whether the bundled reader was loaded into the page itself, which only
// happens when no worker reads for it.
function readsInPage(page) {
  return page.evaluate(() => !!document.querySelector('script[src="zxing-reader-wasm.js"]'));
}

test('reads an EAN-13 in a worker, with its format', async ({ page }) => {
  await open(page);
  await expectRead(page, EAN);
  expect((await codes(page))[0].format).toBe('ean_13');
  expect(await page.evaluate(() => window.__workers)).toBe(1);
  expect(await readsInPage(page)).toBe(false);
});

test('reads only inside the scan window', async ({ page }) => {
  await open(page, { at: 'corner' });
  // Started, and reading: the corner is outside the box.
  await expect.poll(() => page.evaluate(() => window.__workers)).toBe(1);
  await expectNothingFor(page, 3000);
  // The same code in the middle is read.
  await page.evaluate(() => window.__camera.draw('center'));
  await expectRead(page, EAN);
});

test('reads the whole frame without a window', async ({ page }) => {
  await open(page, { at: 'corner' }, { window: 'none' });
  await expectRead(page, EAN);
});

test('reads inside the window an embedded view draws', async ({ page }) => {
  await page.setViewportSize({ width: 640, height: 360 });
  await open(page, { at: 'corner' }, {
    embedded: '1',
    windowWidth: '300',
    windowHeight: '120'
  });
  await expectNothingFor(page, 3000);
  await page.evaluate(() => window.__camera.draw('center'));
  await expectRead(page, EAN);
});

test('mirrors the camera on screen and still reads', async ({ page }) => {
  await open(page, {}, { flipX: '1', animate: '0' });
  await expectRead(page, EAN);
  const transform = await page.evaluate(
    () => getComputedStyle(document.querySelector('video')).transform);
  expect(transform.startsWith('matrix(-1')).toBe(true);
});

test('keeps its worker when the formats change', async ({ page }) => {
  await open(page, {}, { formats: 'qr' });
  await expect.poll(() => page.evaluate(() => window.__workers)).toBe(1);
  // QR codes only: the EAN-13 is not one.
  await expectNothingFor(page, 3000);
  await page.evaluate(() => window.configure({
    host: 'web',
    continuous: '1',
    formats: 'barcode',
    window: 'wide'
  }));
  await expectRead(page, EAN);
  expect(await page.evaluate(() => window.__workers)).toBe(1);
  expect(await readsInPage(page)).toBe(false);
});

test('keeps its worker through a few unreadable frames', async ({ page }) => {
  await open(page, { spoil: 3 });
  await expectRead(page, EAN);
  expect(await page.evaluate(() => window.__workers)).toBe(1);
  expect(await readsInPage(page)).toBe(false);
});

test('reads by itself once its worker keeps failing', async ({ page }) => {
  await open(page, { spoil: 1000 });
  await expectRead(page, EAN);
  expect(await readsInPage(page)).toBe(true);
});

test('reads by itself where no worker can run', async ({ page }) => {
  await open(page, { worker: false });
  await expectRead(page, EAN);
  expect(await readsInPage(page)).toBe(true);
});

test("uses the platform's detector when it reads every format", async ({ page }) => {
  const every = ['qr_code', 'codabar', 'code_39', 'code_93', 'code_128',
    'ean_13', 'ean_8', 'itf', 'pdf417', 'upc_a', 'upc_e'];
  await open(page, { native: { formats: every, text: 'native' } });
  await expectRead(page, 'native');
  expect(await page.evaluate(() => window.__workers)).toBe(0);
  expect(await readsInPage(page)).toBe(false);
});

test("still uses a worker when the platform's detector misses a format", async ({ page }) => {
  await open(page, { native: { formats: ['qr_code'], text: 'native' } });
  await expectRead(page, EAN);
  expect(await page.evaluate(() => window.__workers)).toBe(1);
  expect(await readsInPage(page)).toBe(false);
});

test("lets go of the bundled reader's text once compiled", async ({ page }) => {
  await open(page, { worker: false });
  await expectRead(page, EAN);
  expect(await page.evaluate(() => window.UBS_ZXING_WASM)).toBeNull();
});

test('reads pixels off a canvas without createImageBitmap', async ({ page }) => {
  await open(page, { bitmap: false });
  await expectRead(page, EAN);
  // A few frames later, the canvas has kept its size and still reads.
  await page.evaluate(() => { window.__posts = []; });
  await page.evaluate(() => window.configure({
    host: 'web',
    continuous: '1',
    formats: 'all',
    window: 'wide'
  }));
  await expectRead(page, EAN);
});

// What the host posts, as the web host does to its iframe.
function call(page, name) {
  return page.evaluate((call) => window.postMessage(
    JSON.stringify({ call: call, args: [] }), window.location.origin), name);
}

function sweep(page) {
  return page.evaluate(() => document.getElementById('ubs-scan-line')
    .getAnimations()[0].playState);
}

// Where the line is in its sweep. A pause takes hold on the next frame,
// until which the time still moves: it is read once it has.
function sweepTime(page) {
  return page.evaluate(async () => {
    const animation = document.getElementById('ubs-scan-line').getAnimations()[0];
    await animation.ready;
    return animation.currentTime;
  });
}

test('stops the scan line while paused, and reads nothing', async ({ page }) => {
  await open(page, { at: 'corner' });
  await expect.poll(() => sweep(page)).toBe('running');

  await call(page, 'pauseScanning');
  await expect.poll(() => sweep(page)).toBe('paused');
  const stoppedAt = await sweepTime(page);
  await page.evaluate(() => window.__camera.draw('center'));
  await expectNothingFor(page, 1500);
  expect(await sweepTime(page)).toBe(stoppedAt);

  await call(page, 'resumeScanning');
  await expect.poll(() => sweep(page)).toBe('running');
  await expectRead(page, EAN);
});

