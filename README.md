<a alt="ComApps Logo" href="https://comapps.be" target="_blank" rel="noreferrer"><img src="https://www.comapps.be/wp-content/uploads/2026/09/CompleteLogoHorizontalMini.png" style="margin: 15px"></a>

# Universal Barcode Scanner

Barcode and QR code scanning for Flutter, on Android, iOS, macOS, web and Windows, from one
entry point.

<p>
  <img src="https://public.comapps.be/packages/universal_barcode_scanner/ios.webp" alt="Scanning on iOS" height="360">
  &nbsp;&nbsp;
  <img src="https://public.comapps.be/packages/universal_barcode_scanner/android.webp" alt="Scanning on Android" height="360">
</p>
<p>
  <img src="https://public.comapps.be/packages/universal_barcode_scanner/web.webp" alt="Scanning on the web" height="300">
  &nbsp;&nbsp;
  <img src="https://public.comapps.be/packages/universal_barcode_scanner/windows.webp" alt="Scanning on Windows" height="300">
</p>

<sub>iOS and Android above, web and Windows below.</sub>

[![Pub Version](https://img.shields.io/pub/v/universal_barcode_scanner?color=blue)](https://pub.dev/packages/universal_barcode_scanner)
![Maintainer](https://img.shields.io/badge/Maintainer-Raphael-purple)
[![License](https://img.shields.io/badge/Licence-MIT-blue)](/LICENSE)
![Maintenance](https://img.shields.io/badge/Maintained-yes-success)
![Platforms](https://img.shields.io/badge/Platforms-Android,_iOS,_macOS,_Web,_Windows-22375C.svg)

## Platforms

| Platform | How it scans | Embedded view |
| --- | --- | --- |
| Android | Native, Play Services Vision | Yes |
| iOS | Native, AVFoundation | Yes |
| macOS | Native, AVFoundation and Vision | No |
| Web | `html5-qrcode` in an iframe, bundled, no CDN call | No |
| Windows | `html5-qrcode` in a WebView2 | No |

Windows needs the [WebView2 runtime](https://developer.microsoft.com/microsoft-edge/webview2/),
which ships with Windows 11 and with any recent Edge.

Linux is not supported, and the reason is worth stating because the obvious idea does not work.
Reusing the webview approach would be the natural route, but no published Flutter webview grants a
page access to the camera on Linux: `desktop_webview_window` never connects WebKitGTK's
`permission-request` signal, and `webview_cef` implements no `CefPermissionHandler`. Both engines
deny by default, so `getUserMedia` fails whatever the page does. The native route is no better,
since `camera_linux` has been at 0.0.8 since 2023. That is also why no barcode package on pub.dev
covers Linux, `mobile_scanner` included. On Linux the scanner says so rather than failing on a
missing plugin.

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

### iOS

A usage description goes in `ios/Runner/Info.plist`. iOS kills the app without it:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera permission is required for barcode scanning.</string>
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
| `lineColor` | `Color(0xFFFF6666)` | Colour of the scan line. Android, iOS and macOS only. |
| `cancelButtonText` | `'Cancel'` | Label of the cancel button. Android, iOS and macOS only. |
| `isShowFlashIcon` | `false` | Whether the torch toggle is shown. Android and iOS only. |
| `scanType` | `ScanType.barcode` | What the scanner looks for. |
| `cameraFace` | `CameraFace.back` | Which camera to open. |
| `scanFormat` | `ScanFormat.all` | Symbologies to accept. Android, iOS and macOS only; web reads every format. |
| `barcodeAppBar` | `null` | App bar above the scanner. Without one, the camera fills the route. |
| `scanDelay` | `null` | Pause between two reads in continuous mode. |
| `flip` | `false` | Mirrors the preview, for a front camera. |
| `child` | `null` | Drawn over the scanner, for instance a manual entry field. |

## Keep scanning

Same route, but every code read is emitted instead of the first one closing it. The stream closes
by itself when the route goes away, whichever way it goes:

```dart
final StreamSubscription<String> sub =
    UniversalBarcodeScanner.stream(context).listen((String code) {
  debugPrint(code);
});
```

`stream` takes the same parameters as `scan`.

## Embed the camera

To put the camera inside your own layout rather than on its own route. Android and iOS only:

```dart
UniversalBarcodeScanner(
  continuous: true,
  onScanned: (String code) => debugPrint(code),
  onBarcodeViewCreated: (BarcodeViewController controller) {
    this.controller = controller;
  },
);
```

The controller drives the running camera:

```dart
await controller.toggleFlash();
await controller.pauseScanning();
await controller.resumeScanning();
```

| Parameter | Default | Effect |
| --- | --- | --- |
| `onBarcodeViewCreated` | required | Called once the platform view exists. |
| `onScanned` | `null` | Called with every code read. |
| `continuous` | `false` | Whether reading continues after the first code. |
| `scaleWidth`, `scaleHeight` | `null` | Size of the view, or the constraints when null. |
| `scanType`, `cameraFace`, `scanFormat`, `scanDelay`, `flip`, `child` | see above | As in `scan`. |

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

## Coming from simple_barcode_scanner

| Before | Now |
| --- | --- |
| `SimpleBarcodeScanner.scanBarcode(context)` | `UniversalBarcodeScanner.scan(context)` |
| `SimpleBarcodeScanner.streamBarcode(context)` | `UniversalBarcodeScanner.stream(context)` |
| `SimpleBarcodeScanner(...)` | `UniversalBarcodeScanner(...)` |
| `SimpleBarcodeScannerPage(...)` | removed, use `scan` |
| `appBarTitle:`, `centerTitle:` | fields of `BarcodeAppBar` |
| `lineColor: '#ff6666'` | `lineColor: Color(0xFFFF6666)` |
| `delayMillis: 500` | `scanDelay: Duration(milliseconds: 500)` |
| `ScanFormat.ALL_FORMATS` | `ScanFormat.all` |
| `ScanFormat.ONLY_QR_CODE` | `ScanFormat.onlyQrCode` |
| `ScanFormat.ONLY_BARCODE` | `ScanFormat.onlyBarcode` |
| `controller.setOnScanned(cb)` | `controller.onScanned = cb` |
| `import '.../enum.dart'` and friends | one import, `package:universal_barcode_scanner/universal_barcode_scanner.dart` |

The native namespace changed too, so the two packages can no longer be installed side by side in the
same app. That was already true in practice: they declared the same Android package and the same iOS
class, and the build failed on a duplicate.

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

`webview_windows` for the Windows scanner, `path` to resolve the bundled page next to the
executable, and `web` for the iframe. Nothing on Android, iOS or macOS beyond the SDKs.

## Credits

Derived from [simple_barcode_scanner](https://pub.dev/packages/simple_barcode_scanner) by Kunchok
Tashi, which embeds the Android and iOS scanner of
[flutter_barcode_scanner](https://pub.dev/packages/flutter_barcode_scanner) by Amol Gangadhare. Both
are MIT.

## License

MIT, see [LICENSE](LICENSE).
