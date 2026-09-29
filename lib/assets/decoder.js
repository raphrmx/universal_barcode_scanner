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
// so nothing is fetched from anywhere.
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
      var text = atob(scope.UBS_ZXING_WASM);
      var bytes = new Uint8Array(text.length);
      for (var i = 0; i < text.length; i++) {
        bytes[i] = text.charCodeAt(i);
      }
      // The glue fetches the .wasm from a CDN unless handed the binary.
      prepared = scope.BarcodeDetectionAPI.prepareZXingModule({
        overrides: { wasmBinary: bytes.buffer },
        fireImmediately: true
      });
    }
    return prepared;
  }

  // A detector for [formats], BarcodeDetector names, or every format when
  // null. [loadBundled] brings in the bundled reader's scripts, only when the
  // platform's detector will not do.
  function create(formats, loadBundled) {
    var Native = scope.BarcodeDetector;
    var native = Native && typeof Native.getSupportedFormats === 'function'
      ? Native.getSupportedFormats().then(function (supported) {
        var wanted = formats || EVERY;
        for (var i = 0; i < wanted.length; i++) {
          if (supported.indexOf(wanted[i]) < 0) {
            return null;
          }
        }
        return new Native(formats ? { formats: formats } : undefined);
      }, function () {
        return null;
      })
      : Promise.resolve(null);
    return native.then(function (detector) {
      if (detector) {
        return detector;
      }
      var loaded = loadBundled ? loadBundled() : Promise.resolve();
      return loaded.then(prepare).then(function () {
        return new scope.BarcodeDetectionAPI.BarcodeDetector(
          formats ? { formats: formats } : undefined);
      });
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
    scope.UbsDecoder = { create: create, read: read };
    return;
  }

  // One detector at a time; a new `formats` message replaces it.
  var detector = null;

  scope.onmessage = function (event) {
    var data = event.data || {};
    if (data.type === 'formats') {
      detector = create(data.formats);
      detector.then(function () {
        scope.postMessage({ type: 'ready' });
      }, function (error) {
        scope.postMessage({ type: 'failed', message: String(error) });
      });
      return;
    }
    if (data.type !== 'frame' || !detector) {
      return;
    }
    var frame = data.frame;
    detector.then(function (ready) {
      return read(ready, frame);
    }).then(function (codes) {
      scope.postMessage({ type: 'codes', id: data.id, codes: codes });
    }, function (error) {
      scope.postMessage({ type: 'failed', id: data.id, message: String(error) });
    }).then(function () {
      if (frame && typeof frame.close === 'function') {
        frame.close();
      }
    });
  };
})(self);
