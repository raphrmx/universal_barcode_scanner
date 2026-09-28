import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:universal_barcode_scanner/src/constants.dart';
import 'package:universal_barcode_scanner/src/enums.dart';
import 'package:universal_barcode_scanner/src/platform/shared.dart';
import 'package:universal_barcode_scanner/src/scanner_bar.dart';
import 'package:universal_barcode_scanner/src/scanner_config.dart';
import 'package:universal_barcode_scanner/src/scanner_controller.dart';
import 'package:universal_barcode_scanner/src/scanner_exception.dart';

/// Barcode and QR code scanner.
///
/// Two ways to use it. As a route, when you just want a code back:
///
/// ```dart
/// final String? code = await UniversalBarcodeScanner.scan(context);
/// ```
///
/// Or as a widget, when the camera has to sit inside your own layout, on
/// every platform:
///
/// ```dart
/// UniversalBarcodeScanner(
///   onScanned: (String code) => debugPrint(code),
///   onCreated: (ScannerController c) => controller = c,
/// );
/// ```
class UniversalBarcodeScanner extends StatelessWidget {
  /// Creates an embedded scanner view.
  const UniversalBarcodeScanner({
    super.key,
    required this.onCreated,
    this.onScanned,
    this.onError,
    this.scanWindowSize,
    this.lineColor = kDefaultLineColor,
    this.scanWindow = ScanWindow.wide,
    this.cameraFace = CameraFace.back,
    this.scanFormat = ScanFormat.all,
    this.scanDelay,
    this.child,
    this.continuous = false,
    this.flip = false,
  });

  /// Called once the view exists, with the controller that drives it.
  final ScannerCreatedCallback onCreated;

  /// Called with every code read.
  final ValueChanged<String>? onScanned;

  /// Called when the camera cannot be used, for instance when the user
  /// refuses it. On the web, Windows and Linux the view also says so itself.
  final ValueChanged<ScannerException>? onError;

  /// Size of the scan window in logical pixels. A code is only read when it
  /// sits entirely inside it. Null picks one from the view and [scanWindow];
  /// ignored with [ScanWindow.none].
  final Size? scanWindowSize;

  /// Colour of the scan line.
  final Color lineColor;

  /// Shape of the scan window: square for QR codes, wide for barcodes, or
  /// none to read the whole view with nothing drawn over it.
  final ScanWindow scanWindow;

  /// Which camera to open.
  final CameraFace cameraFace;

  /// Symbologies to accept.
  final ScanFormat scanFormat;

  /// Least time between two codes when [continuous].
  final Duration? scanDelay;

  /// Drawn over the camera, for instance a manual entry field.
  final Widget? child;

  /// Whether reading continues after the first code. When false, the view
  /// pauses on the first code until `ScannerController.resumeScanning`.
  final bool continuous;

  /// Whether the preview is mirrored.
  final bool flip;

  /// Opens the scanner as a route and returns the code that was read.
  ///
  /// Completes with null when the user backs out without scanning, and with
  /// a [ScannerException] when the camera cannot be used on Android, iOS or
  /// macOS. The route closes itself in every case.
  ///
  /// [bar], [child], [backgroundColor] and [flip] shape the Flutter
  /// page the web, Windows and Linux scanner runs in. Android, iOS and macOS
  /// open a native screen over it and do not use them.
  static Future<String?> scan(
    BuildContext context, {
    Color lineColor = kDefaultLineColor,
    String cancelLabel = 'Cancel',
    bool showTorchButton = false,
    ScanWindow scanWindow = ScanWindow.wide,
    CameraFace cameraFace = CameraFace.back,
    ScanFormat scanFormat = ScanFormat.all,
    ScannerBar? bar,
    bool flip = false,
    Widget? child,
    Color? backgroundColor,
  }) async {
    final NavigatorState navigator = Navigator.of(context);
    ScannerException? failure;
    late final Route<String> route;

    route = _route<String>(
      ScannerPage(
        config: ScannerConfig(
          lineColor: lineColor,
          cancelLabel: cancelLabel,
          showTorchButton: showTorchButton,
          scanWindow: scanWindow,
          cameraFace: cameraFace,
          scanFormat: scanFormat,
        ),
        backgroundColor: backgroundColor,
        bar: bar,
        flip: flip,
        onScanned: (String code) => _leave(navigator, route, code),
        onClose: () => _leave(navigator, route, null),
        onError: (ScannerException error) {
          failure = error;
          _leave(navigator, route, null);
        },
        child: child,
      ),
    );

    final String? code = await navigator.push(route);
    final ScannerException? error = failure;
    if (error != null) throw error;
    return code;
  }

  /// Opens the scanner as a route and emits every code read until it closes.
  ///
  /// A code held in front of the camera is emitted once, and again only after
  /// it has been out of sight for a second. [scanDelay] adds a least time
  /// between any two codes.
  ///
  /// The stream closes when the route goes away, whichever way it goes: the
  /// back button, a system gesture, or a pop from your own code. Cancelling
  /// the subscription closes the route, so `stream(context).first` scans one
  /// code and leaves. A camera that cannot be used on Android, iOS or macOS is
  /// emitted as a [ScannerException] before the stream closes.
  ///
  /// The other parameters are those of [scan].
  static Stream<String> stream(
    BuildContext context, {
    Color lineColor = kDefaultLineColor,
    String cancelLabel = 'Cancel',
    bool showTorchButton = false,
    ScanWindow scanWindow = ScanWindow.wide,
    CameraFace cameraFace = CameraFace.back,
    ScanFormat scanFormat = ScanFormat.all,
    ScannerBar? bar,
    Duration? scanDelay,
    bool flip = false,
    Widget? child,
    Color? backgroundColor,
  }) {
    final NavigatorState navigator = Navigator.of(context);
    late final Route<void> route;

    final StreamController<String> codes = StreamController<String>(
      // The caller stopped listening: nobody is left to read the scanner.
      onCancel: () => _leave<void>(navigator, route, null),
    );

    route = _route<void>(
      ScannerPage(
        config: ScannerConfig(
          lineColor: lineColor,
          cancelLabel: cancelLabel,
          showTorchButton: showTorchButton,
          scanWindow: scanWindow,
          cameraFace: cameraFace,
          scanFormat: scanFormat,
          scanDelay: scanDelay,
          continuous: true,
        ),
        backgroundColor: backgroundColor,
        bar: bar,
        flip: flip,
        onScanned: (String code) {
          if (!codes.isClosed) codes.add(code);
        },
        onClose: () => _leave<void>(navigator, route, null),
        onError: (ScannerException error) {
          if (!codes.isClosed) codes.addError(error);
          _leave<void>(navigator, route, null);
        },
        child: child,
      ),
    );

    // Covers every way out, including those that never reach onClose.
    unawaited(navigator.push(route).whenComplete(codes.close));
    return codes.stream;
  }

  static Route<T> _route<T>(Widget page) => PageRouteBuilder<T>(
    transitionsBuilder:
        (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondary,
          Widget child,
        ) => FadeTransition(opacity: animation, child: child),
    pageBuilder:
        (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondary,
        ) => page,
  );

  /// Takes [route] off the stack, whether or not it is still on top. Does
  /// nothing the second time: a route being popped still counts as present
  /// for a frame, and a second pop would reach the route below it.
  static void _leave<T>(NavigatorState navigator, Route<T> route, T? result) {
    if (_left[route] ?? false) return;
    _left[route] = true;
    if (!route.isActive || !navigator.mounted) return;
    if (route.isCurrent) {
      navigator.pop<T>(result);
    } else {
      // With the result: a code read while another route sat on top of the
      // scanner still reaches the caller.
      navigator.removeRoute<T>(route, result);
    }
  }

  /// Routes [_leave] has already taken down. An expando, so they are not
  /// kept alive by it.
  static final Expando<bool> _left = Expando<bool>('left');

  @override
  Widget build(BuildContext context) {
    return EmbeddedScanner(
      config: ScannerConfig(
        lineColor: lineColor,
        scanWindow: scanWindow,
        cameraFace: cameraFace,
        scanFormat: scanFormat,
        scanDelay: scanDelay,
        continuous: continuous,
      ),
      scanWindowSize: scanWindowSize,
      onScanned: onScanned,
      onError: onError,
      flip: flip,
      onCreated: onCreated,
      child: child,
    );
  }
}
