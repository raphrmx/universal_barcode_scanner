# Universal Barcode Scanner Versions

## 1.2.0

### Added

- A sweeping line over the scan square on web, Windows and Linux, so those three look like the
  native scanners rather than a bare camera feed. It hangs inside the scan region the page already
  draws, so it tracks the square even when the library shrinks it to fit the video, and it holds
  still under `prefers-reduced-motion`.
- `lineColor` now reaches web, Windows and Linux, where it used to be ignored. The web host passes
  it in the page's query string; the desktop hosts set it once the page is up.

### Fixed

- On Windows and Linux the webview filled the whole window, stretching the camera across the
  screen. It is capped and centred at 640x480, the same as the web scanner has always been.
- The scanner is sized against the space actually available rather than against the window. A host
  embedding it beside a side menu got a webview wider than its panel, clipped, with a scan square
  that looked stretched.
- The scan square is derived from the viewfinder instead of being fixed at 280 pixels. The library
  drops its shaded region altogether once the square is taller than the video, which is what
  happens on a narrow viewport: mobile web showed a bare camera, with no square and no line. The
  video is also centred when its ratio leaves room in the host box.
- The scanner page no longer forces an aspect ratio on the camera. Forcing one sized the video to a
  shape the host box did not have, which overflowed and raised scrollbars over the preview. The
  page follows the camera's own ratio now, and hides any rounding leftover rather than scrolling
  it.

## 1.1.0

Linux, and one webview for both desktops.

### Added

- Linux, through the same bundled `html5-qrcode` page Windows already used. It works because the
  plugin answers the page's camera permission request on the host side, which is what usually stops
  a webview from scanning on Linux: WebKitGTK denies a media request the embedder does not handle.
  Needs `libwebkit2gtk-4.1-0`, which most desktop installs already carry.

### Changed

- Windows and Linux now share a single implementation, on `webview_all` in place of
  `webview_windows`. That package carries both a WebView2 and a WebKitGTK backend, and is the only
  Linux webview on pub.dev that surfaces the camera permission request instead of letting the engine
  deny it by default.
- `path` is gone with it. It only existed to resolve the bundled page next to the executable, and
  `webview_all` loads it as a Flutter asset directly. What is left is `webview_all` and `web`.

### Fixed

- The bundled page reached for `window.chrome.webview` and compared it to the string `'undefined'`,
  which threw a `TypeError` on any browser without it, Firefox included. It now feature-detects the
  JavaScript channel and falls back to the parent frame on the web.
- The page posted the scanned code to `'*'`, so an embedding parent on another origin would have
  received it. It names its own origin as the target now.

### Known issue on Windows

Building with Visual Studio 2026 fails on `error STL1011`, because the webview dependency pins the
Windows Implementation Library at its 2022 release, whose headers still include
`<experimental/coroutine>`. It is not specific to this release: `webview_windows`, used up to
1.0.0+1, pins the very same version. The README carries the one-line workaround until it is bumped
upstream.

### Note on 1.0.0

The 1.0.0 notes below claim no published Flutter webview grants camera access on Linux. That was
wrong: it held for the two packages checked at the time, not for the ecosystem. `webview_all` does
grant it, which is what made this release possible.

## 1.0.0+1

Add gitlab CI workfown

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
