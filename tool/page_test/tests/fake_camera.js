// Runs in the page before its own scripts. The camera is a canvas with an
// EAN-13 drawn on it, what the page posts to its host is kept, and workers
// are counted, with a way to spoil the frames they are handed.
//
// Options: `at` places the code ('center' or 'corner'), `spoil` is how many
// frames reach the worker unreadable, `worker: false` removes workers,
// `bitmap: false` removes createImageBitmap, and
// `native` stands in for the platform's BarcodeDetector: the formats it
// claims to read, and the text it answers with.
function fakeCamera(options) {
  options = options || {};
  const EAN = '4006381333931';

  const L = ['0001101', '0011001', '0010011', '0111101', '0100011',
    '0110001', '0101111', '0111011', '0110111', '0001011'];
  const G = ['0100111', '0110011', '0011011', '0100001', '0011101',
    '0111001', '0000101', '0010001', '0001001', '0010111'];
  const R = L.map((bits) => bits.replace(/./g, (bit) => (bit === '0' ? '1' : '0')));
  const PARITY = ['LLLLLL', 'LLGLGG', 'LLGGLG', 'LLGGGL', 'LGLLGG',
    'LGGLLG', 'LGGGLL', 'LGLGLG', 'LGLGGL', 'LGGLGL'];

  function modules(code) {
    const digits = code.split('').map(Number);
    const parity = PARITY[digits[0]];
    let bits = '101';
    for (let i = 1; i <= 6; i++) {
      bits += (parity[i - 1] === 'L' ? L : G)[digits[i]];
    }
    bits += '01010';
    for (let i = 7; i <= 12; i++) {
      bits += R[digits[i]];
    }
    return bits + '101';
  }

  const canvas = document.createElement('canvas');
  canvas.width = 1280;
  canvas.height = 720;
  const context = canvas.getContext('2d');
  const bits = modules(EAN);
  const module = 4;
  const width = bits.length * module;
  const height = 180;

  function draw(at) {
    context.fillStyle = '#fff';
    context.fillRect(0, 0, canvas.width, canvas.height);
    const x = at === 'corner' ? 30 : (canvas.width - width) / 2;
    const y = at === 'corner' ? 30 : (canvas.height - height) / 2;
    context.fillStyle = '#000';
    for (let i = 0; i < bits.length; i++) {
      if (bits[i] === '1') {
        context.fillRect(x + i * module, y, module, height);
      }
    }
  }
  draw(options.at || 'center');
  // A canvas stream sends frames as the canvas changes: a pixel that flips
  // keeps them coming.
  let tick = false;
  setInterval(() => {
    tick = !tick;
    context.fillStyle = tick ? '#fff' : '#fefefe';
    context.fillRect(canvas.width - 1, canvas.height - 1, 1, 1);
  }, 50);

  navigator.mediaDevices.getUserMedia = () => Promise.resolve(canvas.captureStream(30));
  navigator.mediaDevices.enumerateDevices = () => Promise.resolve([
    { kind: 'videoinput', deviceId: 'fake', label: 'Fake camera', groupId: 'fake' }
  ]);

  // A PNG, as base64, with each of [codes] drawn one under the other.
  function imageOf(codes) {
    const image = document.createElement('canvas');
    image.width = width + 120;
    image.height = codes.length * (height + 80) + 80;
    const draws = image.getContext('2d');
    draws.fillStyle = '#fff';
    draws.fillRect(0, 0, image.width, image.height);
    draws.fillStyle = '#000';
    codes.forEach((code, row) => {
      const pattern = modules(code);
      for (let i = 0; i < pattern.length; i++) {
        if (pattern[i] === '1') {
          draws.fillRect(60 + i * module, 80 + row * (height + 80), module, height);
        }
      }
    });
    return image.toDataURL('image/png').split(',')[1];
  }

  window.__camera = { draw: draw, ean: EAN, imageOf: imageOf };
  window.__posts = [];
  window.addEventListener('message', (event) => {
    try {
      window.__posts.push(JSON.parse(event.data));
    } catch (error) {
      /* not the page's */
    }
  });

  if (options.bitmap === false) {
    window.createImageBitmap = undefined;
  }

  window.__workers = 0;
  window.__spoil = options.spoil || 0;
  if (options.worker === false) {
    delete window.Worker;
    window.Worker = undefined;
  } else {
    const Real = window.Worker;
    window.Worker = function (url, workerOptions) {
      window.__workers++;
      const worker = new Real(url, workerOptions);
      const post = worker.postMessage.bind(worker);
      worker.postMessage = function (message, transfer) {
        if (message && message.type === 'frame' && window.__spoil > 0) {
          window.__spoil--;
          if (message.frame && typeof message.frame.close === 'function') {
            message.frame.close();
          }
          return post({ type: 'frame', id: message.id, frame: null });
        }
        return post(message, transfer);
      };
      return worker;
    };
  }

  if (options.native) {
    const native = options.native;
    window.BarcodeDetector = class {
      static getSupportedFormats() {
        return Promise.resolve(native.formats);
      }

      detect(frame) {
        return Promise.resolve([{ rawValue: native.text, format: 'qr_code' }]);
      }
    };
  } else {
    delete window.BarcodeDetector;
  }
}

module.exports = { fakeCamera };
