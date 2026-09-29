import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:universal_barcode_scanner/src/constants.dart';
import 'package:universal_barcode_scanner/src/enums.dart';
import 'package:universal_barcode_scanner/src/platform/shared.dart';
import 'package:universal_barcode_scanner/src/scanner_bar.dart';
import 'package:universal_barcode_scanner/src/scanner_buttons.dart';
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
class UniversalBarcodeScanner extends StatefulWidget {
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
    this.flip,
    this.flipVertical = false,
    this.buttons = const <ScannerButton>{},
    this.buttonsAlignment = Alignment.centerRight,
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

  /// Whether the camera is shown mirrored left to right. Null mirrors it
  /// where the camera is a webcam facing the user, as [flipsByDefault] says.
  /// Only the picture turns: codes read the same.
  ///
  /// It can change while the view runs: the camera keeps going.
  final bool? flip;

  /// Whether the camera is shown upside down, for a camera mounted that way.
  final bool flipVertical;

  /// Buttons drawn over the camera, on every platform: the torch, pausing,
  /// and each flip. None by default.
  ///
  /// They drive the view as its controller would, and the flips start from
  /// [flip] and [flipVertical].
  final Set<ScannerButton> buttons;

  /// Where [buttons] sit over the camera. Along the side when centred on the
  /// left or the right, across otherwise.
  final AlignmentGeometry buttonsAlignment;

  /// Whether a scanner left without a `flip` mirrors the camera: on a desktop
  /// and in a desktop browser, where the camera is a webcam facing the user,
  /// and not on a phone or a tablet, where it faces away.
  static bool get flipsByDefault => switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => false,
    _ => true,
  };

  /// Opens the scanner as a route and returns the code that was read.
  ///
  /// Completes with null when the user backs out without scanning, and with
  /// a [ScannerException] when the camera cannot be used on Android, iOS or
  /// macOS. The route closes itself in every case.
  ///
  /// [bar], [child], [backgroundColor], [flip], `flipVertical`, `buttons`
  /// and `buttonsAlignment` shape the Flutter page the web, Windows and Linux
  /// scanner runs in. Android, iOS and macOS open a native screen over it and
  /// do not use them, except that [ScannerButton.torch] in `buttons` shows
  /// the native torch button as [showTorchButton] does.
  ///
  /// `buttons` puts a group of buttons over the camera: the torch, pausing,
  /// and each flip. `buttonsAlignment` places it, down the right side by
  /// default, [Alignment.centerRight]; it runs across when not centred on the
  /// left or the right.
  static Future<String?> scan(
    BuildContext context, {
    Color lineColor = kDefaultLineColor,
    @Deprecated('Use ScannerBar.cancelLabel. Removed in 3.0.0.')
    String? cancelLabel,
    bool showTorchButton = false,
    ScanWindow scanWindow = ScanWindow.wide,
    CameraFace cameraFace = CameraFace.back,
    ScanFormat scanFormat = ScanFormat.all,
    ScannerBar? bar,
    bool? flip,
    bool flipVertical = false,
    Widget? child,
    Color? backgroundColor,
    Set<ScannerButton> buttons = const <ScannerButton>{},
    AlignmentGeometry buttonsAlignment = Alignment.centerRight,
  }) async {
    final NavigatorState navigator = Navigator.of(context);
    ScannerException? failure;
    late final Route<String> route;

    route = _route<String>(
      ScannerPage(
        config: ScannerConfig(
          lineColor: lineColor,
          cancelLabel: cancelLabel ?? bar?.cancelLabel ?? 'Cancel',
          showTorchButton:
              showTorchButton || buttons.contains(ScannerButton.torch),
          scanWindow: scanWindow,
          cameraFace: cameraFace,
          scanFormat: scanFormat,
          flipHorizontal: flip ?? flipsByDefault,
          flipVertical: flipVertical,
        ),
        backgroundColor: backgroundColor,
        bar: bar,
        buttons: buttons,
        buttonsAlignment: buttonsAlignment,
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
    @Deprecated('Use ScannerBar.cancelLabel. Removed in 3.0.0.')
    String? cancelLabel,
    bool showTorchButton = false,
    ScanWindow scanWindow = ScanWindow.wide,
    CameraFace cameraFace = CameraFace.back,
    ScanFormat scanFormat = ScanFormat.all,
    ScannerBar? bar,
    Duration? scanDelay,
    bool? flip,
    bool flipVertical = false,
    Widget? child,
    Color? backgroundColor,
    Set<ScannerButton> buttons = const <ScannerButton>{},
    AlignmentGeometry buttonsAlignment = Alignment.centerRight,
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
          cancelLabel: cancelLabel ?? bar?.cancelLabel ?? 'Cancel',
          showTorchButton:
              showTorchButton || buttons.contains(ScannerButton.torch),
          scanWindow: scanWindow,
          cameraFace: cameraFace,
          scanFormat: scanFormat,
          scanDelay: scanDelay,
          continuous: true,
          flipHorizontal: flip ?? flipsByDefault,
          flipVertical: flipVertical,
        ),
        backgroundColor: backgroundColor,
        bar: bar,
        buttons: buttons,
        buttonsAlignment: buttonsAlignment,
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
  State<UniversalBarcodeScanner> createState() =>
      _UniversalBarcodeScannerState();
}

class _UniversalBarcodeScannerState extends State<UniversalBarcodeScanner> {
  late final ScannerButtons _buttons = ScannerButtons(
    flipHorizontal: widget.flip ?? UniversalBarcodeScanner.flipsByDefault,
    flipVertical: widget.flipVertical,
    // The view follows its config's flip, so a rebuild is all it takes.
    onFlip: (bool horizontal, bool vertical) => setState(() {}),
  );

  @override
  void didUpdateWidget(UniversalBarcodeScanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Flips set by the app win over the buttons, but only when they change.
    if (widget.flip != oldWidget.flip ||
        widget.flipVertical != oldWidget.flipVertical) {
      _buttons.setFlip(
        horizontal: widget.flip ?? UniversalBarcodeScanner.flipsByDefault,
        vertical: widget.flipVertical,
      );
    }
  }

  @override
  void dispose() {
    _buttons.dispose();
    super.dispose();
  }

  void _onCreated(ScannerController controller) {
    _buttons.controller = controller;
    widget.onCreated(controller);
  }

  void _onScanned(String code) {
    // A view that is not continuous pauses on its own after a code.
    if (!widget.continuous) _buttons.pausedByScanner();
    widget.onScanned?.call(code);
  }

  @override
  Widget build(BuildContext context) {
    final UniversalBarcodeScanner widget = this.widget;
    final Widget scanner = EmbeddedScanner(
      config: ScannerConfig(
        lineColor: widget.lineColor,
        scanWindow: widget.scanWindow,
        cameraFace: widget.cameraFace,
        scanFormat: widget.scanFormat,
        scanDelay: widget.scanDelay,
        continuous: widget.continuous,
        flipHorizontal: _buttons.flipHorizontal,
        flipVertical: _buttons.flipVertical,
      ),
      scanWindowSize: widget.scanWindowSize,
      onScanned: _onScanned,
      onError: widget.onError,
      onCreated: _onCreated,
      child: widget.child,
    );
    if (widget.buttons.isEmpty) return scanner;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        scanner,
        ScannerButtonsOverlay(
          state: _buttons,
          buttons: widget.buttons,
          alignment: widget.buttonsAlignment,
          inset: const EdgeInsets.all(8),
        ),
      ],
    );
  }
}
