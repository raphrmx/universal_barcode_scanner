# Universal Barcode Scanner Versions

## 1.0.0

First release.

Barcode and QR code scanning on Android, iOS, macOS, web and Windows, from a single entry point:
`UniversalBarcodeScanner.scan` for one code, `UniversalBarcodeScanner.stream` to keep reading, and
the widget itself to embed the camera on Android and iOS.

### macOS

macOS is new, and native rather than a webview: `AVCaptureSession` for the camera and Vision's
`VNDetectBarcodesRequest` for the decoding, which is the only path Apple offers there since
`AVCaptureMetadataOutput` reads no barcodes on the Mac. It needs macOS 10.15, an
`NSCameraUsageDescription`, and the `com.apple.security.device.camera` entitlement, all covered in
the README. The embedded view stays Android and iOS only.

Linux is not covered. Neither published Linux webview lets a page reach the camera, since
`desktop_webview_window` does not connect WebKitGTK's `permission-request` signal and `webview_cef`
implements no `CefPermissionHandler`, and both engines deny by default. The native route is no
better, `camera_linux` having stood at 0.0.8 since 2023. The scanner says so on Linux instead of
raising a `MissingPluginException`.

### Dependencies

`permission_handler` is gone. It was pulled in for a single camera status read on Windows, and in
return every app depending on this plugin inherited its Android module, whose current release
forces `compileSdk 37`. The Windows scanner now simply asks through the webview's own permission
prompt and remembers the answer for the scan. What is left is `webview_windows`, `path` and `web`.

### Lineage

The package is a derivative of [simple_barcode_scanner](https://pub.dev/packages/simple_barcode_scanner)
by Kunchok Tashi, which embeds the Android and iOS scanner of
[flutter_barcode_scanner](https://pub.dev/packages/flutter_barcode_scanner) by Amol Gangadhare. Both
are MIT, and their copyright notices are kept in [LICENSE](LICENSE). Coming from either of them,
the API is not the same: see the migration table in the README.

### Fixed since the code it derives from

- On web the scanner registered a new platform view, built a new iframe and opened a new `message`
  listener on every rebuild, and never cancelled any of them. It now sets all three up once and
  tears them down with the widget.
- On web a message from any origin was taken for a scan, so an embedded frame or a browser
  extension could feed the app a barcode of its choosing. Only messages from the page's own origin
  are read now.
- On web the height of the scanner was decided from the viewport width, which squashed the preview
  on a wide, short window.
- On Windows the webview was reinitialised and its message stream resubscribed on every rebuild,
  which delivered a scan several times over.
- On Windows the camera permission was read asynchronously from `build`, so the result never
  arrived in time and the permission dialog was shown even when permission had already been
  granted.
- On Windows the webview controller was disposed twice when leaving through the app bar.
- `UniversalBarcodeScanner.stream` now closes its stream however the route is left, including a
  system back gesture. It used to leak the controller unless the app bar button was used.
- Linux says it is unsupported instead of raising a `MissingPluginException`.
- Cancelling a single scan returned the raw sentinel `'-1'` to the caller, which the documentation
  described as `null`. It is now `null`, and `'-1'` no longer leaks into a continuous stream
  either.
- The native scanner kept a stream field it never assigned, so the cached broadcast stream it was
  meant to reuse was rebuilt on every call.

### Renamed from the code it derives from

The plugin used to register itself under another package's namespace, which made it impossible to
depend on both in one app: two AARs declaring `com.amolg.flutterbarcodescanner` fail to merge, and
two pods declaring `SwiftFlutterBarcodeScannerPlugin` fail to link. Everything now sits under
`be.comapps.universal_barcode_scanner`, and the method channels, event channel and platform view
type are named after this package.
