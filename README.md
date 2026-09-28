# Universal Barcode Scanner

Barcode and QR code scanning for Flutter, on Android, iOS, Linux, macOS, web and Windows, from
one entry point.

<p>
  <img src="https://public.comapps.be/packages/universal_barcode_scanner/ios.webp" alt="Scanning on iOS" height="360">
  &nbsp;&nbsp;
  <img src="https://public.comapps.be/packages/universal_barcode_scanner/web.webp" alt="Scanning on Android" height="360">
</p>

<sub>iOS and Android above, web and Windows below.</sub>

[![Live demo](https://img.shields.io/badge/Live_demo-comapps.web.app-3c9a70)](https://comapps.web.app/universal_barcode_scanner/)
[![Pub Version](https://img.shields.io/pub/v/universal_barcode_scanner?color=0175C2)](https://pub.dev/packages/universal_barcode_scanner)
[![Build](https://img.shields.io/github/actions/workflow/status/raphrmx/universal_barcode_scanner/ci.yml?branch=main&label=build)](https://github.com/raphrmx/universal_barcode_scanner/actions/workflows/ci.yml)
![Maintainer](https://img.shields.io/badge/Maintainer-Raphael_Vrient-733d90)
[![Licence](https://img.shields.io/badge/Licence-MIT-8C6A3F)](LICENSE)
![Platforms](https://img.shields.io/badge/Platforms-Android,_iOS,_macOS,_Windows,_Linux,_Web-22375C.svg)

## Platforms

| Platform | How it scans | Embedded view |
| --- | --- | --- |
| Android | Native, CameraX and ML Kit | Yes |
| iOS | Native, AVFoundation | Yes |
| macOS | Native, AVFoundation and Vision | No |
| Web | `html5-qrcode` in an iframe, bundled, no CDN call | No |
| Windows | `html5-qrcode` in a WebView2 | No |
| Linux | `html5-qrcode` in a WebKitGTK view | No |

Windows needs the [WebView2 runtime](https://developer.microsoft.com/microsoft-edge/webview2/),
which ships with Windows 11 and with any recent Edge. Linux needs WebKitGTK, `libwebkit2gtk-4.1-0`
on Debian and Ubuntu, which most desktop installs already carry.

The same bundled page serves both, and the plugin answers its camera permission request on the host
side. That last part is what usually stops a webview from scanning on Linux: WebKitGTK denies a
media request the embedder does not handle.

## Install

```sh
flutter pub add universal_barcode_scanner
```

Requires Flutter 3.27 or later.

### Android

Camera permission goes in your own manifest, `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

The plugin asks for `minSdkVersion 21` and builds against `compileSdk 34`. Two of its dependencies,
`flutter_plugin_android_lifecycle` and `webview_all_android`, are built against 36, and an app has to
compile against the highest of them:

```gradle
android {
    compileSdk = 36
}
```

### iOS

A usage description goes in `ios/Runner/Info.plist`. iOS kills the app without it:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera permission is required for barcode scanning.</string>
```

### Windows

Nothing to declare, but if you build with Visual Studio 2026 or later the build fails on
`error STL1011` from `<experimental/coroutine>`. That comes from the Windows Implementation Library
pinned by the webview dependency, not from this plugin, and both Windows webviews on pub.dev pin the
same 2022 release. Until it is bumped upstream, add this to your app's `windows/CMakeLists.txt`,
above `add_subdirectory(${FLUTTER_MANAGED_DIR})`:

```cmake
add_compile_definitions(_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)
```

### macOS

Two things, and the scanner fails silently without either. A usage description in
`macos/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera permission is required for barcode scanning.</string>
```

And the camera entitlement in **both** `macos/Runner/DebugProfile.entitlements` and
`macos/Runner/Release.entitlements`, since a macOS app is sandboxed:

```xml
<key>com.apple.security.device.camera</key>
<true/>
```

Requires macOS 10.15 or later.

### Web

Browsers only hand out the camera on a secure origin, so the page must be served over HTTPS.
`localhost` counts as secure during development.

## Scan one code

Opens the scanner as a route and comes back with what it read, or `null` if the user backed out:

```dart
final String? code = await UniversalBarcodeScanner.scan(context);
```

| Parameter | Default | Effect |
| --- | --- | --- |
| `lineColor` | `Color(0xFFFF6666)` | Colour of the scan line, on every platform. |
| `scanFormat` | `ScanFormat.all` | Symbologies to accept, on every platform. Fewer formats also scan faster. |
| `scanType` | `ScanType.barcode` | Shape of the scan window: wide for barcodes, square for QR codes. |
| `cameraFace` | `CameraFace.back` | Which camera to open. |
| `cancelButtonText` | `'Cancel'` | Label of the cancel button. Android, iOS and macOS. |
| `isShowFlashIcon` | `false` | Whether the torch toggle is shown, when the camera has a flash. Android and iOS. |
| `barcodeAppBar` | `null` | App bar above the scanner. Web, Windows and Linux. |
| `child` | `null` | Drawn over the scanner, for instance a manual entry field. Web, Windows and Linux. |
| `backgroundColor` | black | Colour around the camera. Web, Windows and Linux. |
| `flip` | `false` | Mirrors the preview. Web, Windows and Linux. |

Android, iOS and macOS open a native screen over the route, so the parameters that shape the
Flutter page do nothing there.

### When the camera cannot be used

On Android, iOS and macOS, `scan` throws a `ScannerException` and closes the route itself:

```dart
try {
  final String? code = await UniversalBarcodeScanner.scan(context);
} on ScannerException catch (error) {
  switch (error.code) {
    case ScannerErrorCode.permissionDenied: // the user refused the camera
    case ScannerErrorCode.cameraUnavailable: // no camera, or it did not start
    case ScannerErrorCode.alreadyActive: // another scanner is on screen
    case ScannerErrorCode.unknown:
  }
}
```

The scanner shows no dialog of its own: what to tell the user is the app's call. On the web,
Windows and Linux the scanner page says why the camera did not start, and the user backs out.

## Keep scanning

Same route, but every code read is emitted instead of the first one closing it. The stream closes
by itself when the route goes away, whichever way it goes, and cancelling the subscription closes
the route:

```dart
final StreamSubscription<String> sub =
    UniversalBarcodeScanner.stream(context).listen((String code) {
  debugPrint(code);
});
```

A code held in front of the camera is emitted once, and again only after it has been out of sight
for a second. `scanDelay` adds a least time between any two codes. A camera that cannot be used is
emitted as a `ScannerException`, then the stream closes.

`stream` takes the same parameters as `scan`, plus `scanDelay`.

## Embed the camera

To put the camera inside your own layout rather than on its own route. Android and iOS only:

```dart
UniversalBarcodeScanner(
  continuous: true,
  onScanned: (String code) => debugPrint(code),
  onError: (ScannerException error) => debugPrint('$error'),
  onBarcodeViewCreated: (BarcodeViewController controller) {
    this.controller = controller;
  },
);
```

The view asks for the camera permission itself, stops the camera while the app is in the
background, and only reads codes that sit entirely inside its scan window.

The controller drives the running camera:

```dart
final bool torchOn = await controller.toggleFlash();
await controller.pauseScanning();
await controller.resumeScanning();
```

| Parameter | Default | Effect |
| --- | --- | --- |
| `onBarcodeViewCreated` | required | Called once the platform view exists. |
| `onScanned` | `null` | Called with every code read. |
| `onError` | `null` | Called when the camera cannot be used. |
| `continuous` | `false` | When false, the view pauses on the first code until `resumeScanning`. |
| `scanWindowSize` | `null` | Size of the scan window in logical pixels, or one picked from `scanType`. |
| `lineColor`, `scanType`, `cameraFace`, `scanFormat`, `scanDelay`, `flip`, `child` | see above | As in `scan` and `stream`. |

The view fills the constraints it is given.

## App bar

Passing a `BarcodeAppBar` is what makes the scanner show one at all:

```dart
UniversalBarcodeScanner.scan(
  context,
  barcodeAppBar: const BarcodeAppBar(
    appBarTitle: 'Scan',
    centerTitle: false,
    enableBackButton: true,
    backButtonIcon: Icon(Icons.arrow_back_ios),
  ),
);
```

On Android, iOS and macOS the native screen has no app bar.

## Migrating from 1.x

The breaking changes of 2.0 and what to write instead are listed at the top of the
[changelog](CHANGELOG.md).

## Example

`example/` is one app with the three ways to scan, one screen each.

```sh
cd example && flutter run
```

## Tests

```sh
flutter test
```

## Dependencies

`webview_all` for the Windows and Linux scanners, and `web` for the iframe on the web. Android
carries CameraX and the ML Kit barcode model, which is bundled, so the scanner works on a device
with no Play services and downloads nothing on first use. Nothing on iOS or macOS beyond the SDKs.

No design system. The package is written against `package:flutter/widgets.dart` alone, so it sits
under Material, under `material_ui`, or under neither, and imposes none of them on your app. The
scanner bar is drawn here rather than taken from a widget library; `BarcodeAppBar` carries its
colours.

## License

MIT, see [LICENSE](LICENSE).
