// Reads codes out of camera frames for barcode.html.
//
// Loaded two ways. As a worker, it answers the page's messages and keeps the
// decoding off the page's thread, which on the web is the Flutter app's own.
// In the page, where a worker cannot be started (a desktop webview on
// file://), it defines `UbsDecoder` for the page to call directly.
//
// The platform's own BarcodeDetector is used where it reads every format
// asked for, Chrome on Android and macOS among them. Anywhere else it is the
// bundled one: zxing-cpp compiled to WebAssembly, fed from zxing-reader-wasm.js
// so nothing is fetched from anywhere. The page makes that choice before
// starting a worker, which only ever runs the bundled one.
(function (scope) {
  'use strict';

  var inWorker = typeof WorkerGlobalScope !== 'undefined'
    && scope instanceof WorkerGlobalScope;
  if (inWorker) {
    importScripts('barcode-detector.js', 'zxing-reader-wasm.js');
  }

  // What `formats: all` needs the platform's detector to read before it is
  // preferred to the bundled one.
  var EVERY = ['qr_code', 'codabar', 'code_39', 'code_93', 'code_128',
    'ean_13', 'ean_8', 'itf', 'pdf417', 'upc_a', 'upc_e'];

  var prepared = null;

  // The bundled reader, compiled once for the page or the worker.
  function prepare() {
    if (!prepared) {
      var text = scope.UBS_ZXING_WASM;
      // Read once, then let go: 1.5 MB nothing needs any more.
      scope.UBS_ZXING_WASM = null;
      var bytes;
      if (typeof Uint8Array.fromBase64 === 'function') {
        bytes = Uint8Array.fromBase64(text);
      } else {
        var binary = atob(text);
        bytes = new Uint8Array(binary.length);
        for (var i = 0; i < binary.length; i++) {
          bytes[i] = binary.charCodeAt(i);
        }
      }
      // The glue fetches the .wasm from a CDN unless handed the binary.
      prepared = scope.BarcodeDetectionAPI.prepareZXingModule({
        overrides: { wasmBinary: bytes.buffer },
        fireImmediately: true
      });
    }
    return prepared;
  }

  // The platform's own detector for [formats], BarcodeDetector names, or
  // every format when null. Null when there is none, or when it does not
  // read every format asked for.
  function native(formats) {
    var Native = scope.BarcodeDetector;
    if (!Native || typeof Native.getSupportedFormats !== 'function') {
      return Promise.resolve(null);
    }
    return Promise.resolve(Native.getSupportedFormats()).then(function (supported) {
      var wanted = formats || EVERY;
      for (var i = 0; i < wanted.length; i++) {
        if (supported.indexOf(wanted[i]) < 0) {
          return null;
        }
      }
      return new Native(formats ? { formats: formats } : undefined);
    }, function () {
      return null;
    });
  }

  // The bundled detector for [formats]. [loadBundled] brings in its scripts
  // first, where they are not loaded yet.
  function bundled(formats, loadBundled) {
    var loaded = loadBundled ? loadBundled() : Promise.resolve();
    return loaded.then(prepare).then(function () {
      return new scope.BarcodeDetectionAPI.BarcodeDetector(
        formats ? { formats: formats } : undefined);
    });
  }

  // Every code in [frame], an ImageBitmap or an ImageData: its text and
  // its format, in BarcodeDetector's names.
  function read(detector, frame) {
    return detector.detect(frame).then(function (codes) {
      var found = [];
      for (var i = 0; i < codes.length; i++) {
        if (codes[i].rawValue) {
          found.push({ text: codes[i].rawValue, format: codes[i].format });
        }
      }
      return found;
    });
  }

  if (!inWorker) {
    scope.UbsDecoder = { native: native, bundled: bundled, read: read };
    return;
  }

  // The page only starts a worker when the platform's detector will not do,
  // so the worker reads with the bundled one. A `formats` message replaces
  // the detector; the reader compiled for the first serves every other.
  var detector = null;

  scope.onmessage = function (event) {
    var data = event.data || {};
    if (data.type === 'formats') {
      var built = bundled(data.formats);
      detector = built;
      built.then(function () {
        scope.postMessage({ type: 'formats', seq: data.seq });
      }, function (error) {
        scope.postMessage({ type: 'formats', seq: data.seq, error: String(error) });
      });
      return;
    }
    if (data.type !== 'frame') {
      return;
    }
    var frame = data.frame;
    // Every frame is answered, read or not, so the page never waits on one.
    (detector || Promise.reject(new Error('No formats asked for yet.')))
      .then(function (ready) {
        return read(ready, frame);
      }).then(function (codes) {
        scope.postMessage({ type: 'codes', id: data.id, codes: codes });
      }, function (error) {
        scope.postMessage({ type: 'codes', id: data.id, error: String(error) });
      }).then(function () {
        if (frame && typeof frame.close === 'function') {
          frame.close();
        }
      });
  };
})(self);
