import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:universal_barcode_scanner/src/constants.dart';
import 'package:universal_barcode_scanner/src/enums.dart';
import 'package:universal_barcode_scanner/src/platform/shared.dart';
import 'package:universal_barcode_scanner/src/scan_feedback.dart';
import 'package:universal_barcode_scanner/src/scan_result.dart';
import 'package:universal_barcode_scanner/src/scanner_bar.dart';
import 'package:universal_barcode_scanner/src/scanner_button_style.dart';
import 'package:universal_barcode_scanner/src/scanner_buttons.dart';
import 'package:universal_barcode_scanner/src/scanner_config.dart';
import 'package:universal_barcode_scanner/src/scanner_controller.dart';
import 'package:universal_barcode_scanner/src/scanner_exception.dart';
import 'package:universal_barcode_scanner/src/scanner_labels.dart';
import 'package:universal_barcode_scanner/src/scanner_verdict.dart';

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
/// Decides whether a code read is one the app takes. A code refused is not
/// handed on: the scanner says so over the camera and reads on.
typedef ScanValidator = bool Function(ScanResult result);

class UniversalBarcodeScanner extends StatefulWidget {
  /// Creates an embedded scanner view.
  const UniversalBarcodeScanner({
    super.key,
    required this.onCreated,
    this.onScanned,
    this.onResult,
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
    this.animate = true,
    this.labels = ScannerLabels.english,
    this.vibrate = false,
    this.beep = false,
    this.buttonStyle = const ScannerButtonStyle(),
    this.validator,
  });

  /// Called once the view exists, with the controller that drives it. On
  /// Android, iOS and macOS a camera switched by [ScannerButton.switchCamera]
  /// is a new native view, so this is called again with its controller.
  final ScannerCreatedCallback onCreated;

  /// Called with every code read.
  final ValueChanged<String>? onScanned;

  /// Called with every code read, with the symbology it was printed in.
  final ValueChanged<ScanResult>? onResult;

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
  /// Changing it applies at once, without restarting the camera.
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

  /// Whether the camera turns over when flipped, and fades in when it starts
  /// on the web, Windows and Linux, rather than changing at once. Off anyway
  /// when the platform asks for reduced motion.
  final bool animate;

  /// The words of the buttons, for screen readers, and of the page the web,
  /// Windows and Linux view writes when the camera will not start. English
  /// by default; [ScannerLabels.french], [ScannerLabels.dutch] and
  /// [ScannerLabels.german] are ready to use.
  final ScannerLabels labels;

  /// Whether the phone vibrates for each code read, where it can.
  final bool vibrate;

  /// Whether a short beep sounds for each code read.
  final bool beep;

  /// How [buttons] look: their size, colours and shape.
  final ScannerButtonStyle buttonStyle;

  /// Decides which codes count. A code it refuses reaches neither
  /// [onScanned] nor [onResult]: the view shows `ScannerLabels.rejected` over
  /// the camera and reads on, and when not [continuous] it pauses on the
  /// first code accepted. A code held in front of the camera is refused once,
  /// not on every frame. Null takes every code.
  ///
  /// Changing it, null included, applies at once, without restarting the
  /// camera.
  final ScanValidator? validator;

  /// Whether a scanner animates: when asked to, and the platform does not
  /// ask for reduced motion.
  static bool _animates(BuildContext context, bool animate) =>
      animate && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

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
  /// macOS. The route closes itself in every case. [scanResult] does the
  /// same and also says which symbology the code was printed in.
  ///
  /// [bar], [child], [backgroundColor], [flip], `flipVertical`, `buttons`,
  /// `buttonsAlignment`, `animate` and `labels` shape the Flutter page the
  /// web, Windows and Linux scanner runs in. Android, iOS and macOS open a
  /// native screen over it and do not use them, except that
  /// [ScannerButton.torch] in `buttons` shows the native torch button as
  /// [showTorchButton] does.
  ///
  /// `buttons` puts a group of buttons over the camera, placed by
  /// `buttonsAlignment`, down the right side by default; it runs across when
  /// not centred on the left or the right. `animate`, on by default, has the
  /// camera fade in when it starts and turn over when flipped, and is off
  /// anyway when the platform asks for reduced motion. `labels` holds the
  /// words of the buttons and of the page, English by default. `vibrate` and
  /// `beep` signal each code read. `buttonStyle` sets the look of the buttons
  /// and of the close button. `scanWindowSize` sets the size of the scan
  /// window in logical pixels, on every platform.
  ///
  /// `validator` decides which codes count. A code it refuses does not close
  /// the scanner: it says `ScannerLabels.rejected`, over the camera or on the
  /// native screen, and reads on until a code is accepted.
  static Future<String?> scan(
    BuildContext context, {
    Color lineColor = kDefaultLineColor,
    @Deprecated('Use ScannerBar.cancelLabel. Removed in 3.0.0.')
    String? cancelLabel,
    bool showTorchButton = false,
    ScanWindow scanWindow = ScanWindow.wide,
    Size? scanWindowSize,
    CameraFace cameraFace = CameraFace.back,
    ScanFormat scanFormat = ScanFormat.all,
    ScannerBar? bar,
    bool? flip,
    bool flipVertical = false,
    Widget? child,
    Color? backgroundColor,
    Set<ScannerButton> buttons = const <ScannerButton>{},
    AlignmentGeometry buttonsAlignment = Alignment.centerRight,
    bool animate = true,
    ScannerLabels labels = ScannerLabels.english,
    bool vibrate = false,
    bool beep = false,
    ScannerButtonStyle buttonStyle = const ScannerButtonStyle(),
    ScanValidator? validator,
  }) async {
    final ScanResult? result = await _scanOnce(
      context,
      _Options(
        lineColor: lineColor,
        cancelLabel: cancelLabel,
        showTorchButton: showTorchButton,
        scanWindow: scanWindow,
        scanWindowSize: scanWindowSize,
        cameraFace: cameraFace,
        scanFormat: scanFormat,
        bar: bar,
        flip: flip,
        flipVertical: flipVertical,
        child: child,
        backgroundColor: backgroundColor,
        buttons: buttons,
        buttonsAlignment: buttonsAlignment,
        animate: animate,
        labels: labels,
        vibrate: vibrate,
        beep: beep,
        buttonStyle: buttonStyle,
        validator: validator,
      ),
    );
    return result?.text;
  }

  /// [scan], with the symbology the code was printed in.
  static Future<ScanResult?> scanResult(
    BuildContext context, {
    Color lineColor = kDefaultLineColor,
    bool showTorchButton = false,
    ScanWindow scanWindow = ScanWindow.wide,
    Size? scanWindowSize,
    CameraFace cameraFace = CameraFace.back,
    ScanFormat scanFormat = ScanFormat.all,
    ScannerBar? bar,
    bool? flip,
    bool flipVertical = false,
    Widget? child,
    Color? backgroundColor,
    Set<ScannerButton> buttons = const <ScannerButton>{},
    AlignmentGeometry buttonsAlignment = Alignment.centerRight,
    bool animate = true,
    ScannerLabels labels = ScannerLabels.english,
    bool vibrate = false,
    bool beep = false,
    ScannerButtonStyle buttonStyle = const ScannerButtonStyle(),
    ScanValidator? validator,
  }) => _scanOnce(
    context,
    _Options(
      lineColor: lineColor,
      showTorchButton: showTorchButton,
      scanWindow: scanWindow,
      scanWindowSize: scanWindowSize,
      cameraFace: cameraFace,
      scanFormat: scanFormat,
      bar: bar,
      flip: flip,
      flipVertical: flipVertical,
      child: child,
      backgroundColor: backgroundColor,
      buttons: buttons,
      buttonsAlignment: buttonsAlignment,
      animate: animate,
      labels: labels,
      vibrate: vibrate,
      beep: beep,
      buttonStyle: buttonStyle,
      validator: validator,
    ),
  );

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
  /// emitted as a [ScannerException] before the stream closes. [resultStream]
  /// does the same with the symbology of each code.
  ///
  /// The other parameters are those of [scan].
  static Stream<String> stream(
    BuildContext context, {
    Color lineColor = kDefaultLineColor,
    @Deprecated('Use ScannerBar.cancelLabel. Removed in 3.0.0.')
    String? cancelLabel,
    bool showTorchButton = false,
    ScanWindow scanWindow = ScanWindow.wide,
    Size? scanWindowSize,
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
    bool animate = true,
    ScannerLabels labels = ScannerLabels.english,
    bool vibrate = false,
    bool beep = false,
    ScannerButtonStyle buttonStyle = const ScannerButtonStyle(),
    ScanValidator? validator,
  }) => _scanMany(
    context,
    _Options(
      lineColor: lineColor,
      cancelLabel: cancelLabel,
      showTorchButton: showTorchButton,
      scanWindow: scanWindow,
      scanWindowSize: scanWindowSize,
      cameraFace: cameraFace,
      scanFormat: scanFormat,
      bar: bar,
      scanDelay: scanDelay,
      flip: flip,
      flipVertical: flipVertical,
      child: child,
      backgroundColor: backgroundColor,
      buttons: buttons,
      buttonsAlignment: buttonsAlignment,
      animate: animate,
      labels: labels,
      vibrate: vibrate,
      beep: beep,
      buttonStyle: buttonStyle,
      validator: validator,
    ),
  ).map((ScanResult result) => result.text);

  /// [stream], with the symbology of each code.
  static Stream<ScanResult> resultStream(
    BuildContext context, {
    Color lineColor = kDefaultLineColor,
    bool showTorchButton = false,
    ScanWindow scanWindow = ScanWindow.wide,
    Size? scanWindowSize,
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
    bool animate = true,
    ScannerLabels labels = ScannerLabels.english,
    bool vibrate = false,
    bool beep = false,
    ScannerButtonStyle buttonStyle = const ScannerButtonStyle(),
    ScanValidator? validator,
  }) => _scanMany(
    context,
    _Options(
      lineColor: lineColor,
      showTorchButton: showTorchButton,
      scanWindow: scanWindow,
      scanWindowSize: scanWindowSize,
      cameraFace: cameraFace,
      scanFormat: scanFormat,
      bar: bar,
      scanDelay: scanDelay,
      flip: flip,
      flipVertical: flipVertical,
      child: child,
      backgroundColor: backgroundColor,
      buttons: buttons,
      buttonsAlignment: buttonsAlignment,
      animate: animate,
      labels: labels,
      vibrate: vibrate,
      beep: beep,
      buttonStyle: buttonStyle,
      validator: validator,
    ),
  );

  /// Every code in an image: a photo picked from the gallery, a file, an
  /// asset, a screenshot. [bytes] are the image as encoded, PNG, JPEG or any
  /// format the platform opens, and [scanFormat] limits which symbologies
  /// count.
  ///
  /// No camera and no permission are involved. The answer is empty when the
  /// image holds no code; a [ScannerException] with
  /// [ScannerErrorCode.invalidImage] means the bytes are no image. ML Kit reads
  /// it on Android and Vision on iOS and macOS, and the scanner page does on
  /// the web, Windows and Linux, off the app's thread where it can.
  ///
  /// ```dart
  /// final List<ScanResult> codes = await UniversalBarcodeScanner.scanImage(
  ///   await file.readAsBytes(),
  /// );
  /// ```
  static Future<List<ScanResult>> scanImage(
    List<int> bytes, {
    ScanFormat scanFormat = ScanFormat.all,
  }) => readImage(
    bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
    scanFormat,
  );

  /// One code, or null when the user backs out.
  static Future<ScanResult?> _scanOnce(
    BuildContext context,
    _Options options,
  ) async {
    final NavigatorState navigator = Navigator.of(context);
    ScannerException? failure;
    late final Route<ScanResult> route;
    final ScanVerdicts verdicts = ScanVerdicts();

    route = _route<ScanResult>(
      options.page(
        context,
        continuous: false,
        verdicts: verdicts,
        onScanned: (ScanResult result) {
          if (!options.accepts(result, verdicts)) return;
          ScanFeedback.play(vibrate: options.vibrate, beep: options.beep);
          _leave(navigator, route, result);
        },
        onClose: () => _leave(navigator, route, null),
        onError: (ScannerException error) {
          failure = error;
          _leave(navigator, route, null);
        },
      ),
    );

    final ScanResult? result = await navigator.push(route);
    final ScannerException? error = failure;
    if (error != null) throw error;
    return result;
  }

  /// Every code until the route goes away.
  static Stream<ScanResult> _scanMany(BuildContext context, _Options options) {
    final NavigatorState navigator = Navigator.of(context);
    late final Route<void> route;

    final StreamController<ScanResult> results = StreamController<ScanResult>(
      // The caller stopped listening: nobody is left to read the scanner.
      onCancel: () => _leave<void>(navigator, route, null),
    );
    final ScanVerdicts verdicts = ScanVerdicts();

    route = _route<void>(
      options.page(
        context,
        continuous: true,
        verdicts: verdicts,
        onScanned: (ScanResult result) {
          if (results.isClosed) return;
          if (!options.accepts(result, verdicts)) return;
          ScanFeedback.play(vibrate: options.vibrate, beep: options.beep);
          results.add(result);
        },
        onClose: () => _leave<void>(navigator, route, null),
        onError: (ScannerException error) {
          if (!results.isClosed) results.addError(error);
          _leave<void>(navigator, route, null);
        },
      ),
    );

    // Covers every way out, including those that never reach onClose.
    unawaited(navigator.push(route).whenComplete(results.close));
    return results.stream;
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
    // The view follows its config, so a rebuild is all it takes.
    onFlip: (bool horizontal, bool vertical) => setState(() {}),
    onSwitchCamera: () => setState(() {
      _face = _face == CameraFace.front ? CameraFace.back : CameraFace.front;
    }),
  );

  /// The camera open, as asked for or as the button switched it.
  late CameraFace _face = widget.cameraFace;

  /// The view's controller, to pause it on the first code accepted when not
  /// continuous.
  ScannerController? _controller;

  /// The verdict on each code read, for the view to show.
  final ScanVerdicts _verdicts = ScanVerdicts();

  /// Whether a code was accepted by a view that is not continuous: it holds
  /// until resumed.
  bool _holding = false;

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
    if (widget.cameraFace != oldWidget.cameraFace) _face = widget.cameraFace;
  }

  @override
  void dispose() {
    _controller?.isPaused.removeListener(_onPaused);
    _buttons.dispose();
    _verdicts.dispose();
    super.dispose();
  }

  void _onCreated(ScannerController controller) {
    _controller?.isPaused.removeListener(_onPaused);
    _controller = controller;
    controller.isPaused.addListener(_onPaused);
    _holding = false;
    _buttons.controller = controller;
    controller.onResult = _onResult;
    widget.onCreated(controller);
  }

  /// Resumed, by the app or by the pause button: codes count again.
  void _onPaused() {
    if (!(_controller?.isPaused.value ?? true)) _holding = false;
  }

  /// Every code the view reads comes here, `onScanned` included, so the
  /// validator sees each one first.
  void _onResult(ScanResult result) {
    // A code read in the moment before the pause lands.
    if (_holding) return;
    final ScanValidator? validator = widget.validator;
    if (validator != null && !validator(result)) {
      _verdicts.rejected();
      ScanFeedback.rejected(vibrate: widget.vibrate, beep: widget.beep);
      return;
    }
    // The view always reads on, so that continuous and the validator can
    // change without restarting the camera: it pauses here instead, on the
    // first code accepted.
    if (!widget.continuous) {
      _holding = true;
      unawaited(_controller?.pauseScanning());
    }
    _verdicts.accepted();
    ScanFeedback.play(vibrate: widget.vibrate, beep: widget.beep);
    widget.onScanned?.call(result.text);
    widget.onResult?.call(result);
  }

  @override
  Widget build(BuildContext context) {
    final UniversalBarcodeScanner widget = this.widget;
    final Widget scanner = EmbeddedScanner(
      config: ScannerConfig(
        lineColor: widget.lineColor,
        scanWindow: widget.scanWindow,
        cameraFace: _face,
        scanFormat: widget.scanFormat,
        scanDelay: widget.scanDelay,
        continuous: true,
        flipHorizontal: _buttons.flipHorizontal,
        flipVertical: _buttons.flipVertical,
        animate: UniversalBarcodeScanner._animates(context, widget.animate),
        labels: widget.labels,
      ),
      scanWindowSize: widget.scanWindowSize,
      onError: widget.onError,
      onCreated: _onCreated,
      child: widget.child,
    );
    // Always a Stack, and the same children first, so that a validator or
    // buttons coming and going keep the camera's view where it is.
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        scanner,
        ScannerVerdict(
          verdicts: _verdicts,
          rejectedLabel: widget.labels.rejected,
        ),
        if (widget.buttons.isNotEmpty)
          ScannerButtonsOverlay(
            state: _buttons,
            buttons: widget.buttons,
            labels: widget.labels,
            style: widget.buttonStyle,
            alignment: widget.buttonsAlignment,
            inset: const EdgeInsets.all(8),
          ),
      ],
    );
  }
}

/// What `scan`, `scanResult`, `stream` and `resultStream` are given, for the
/// page they all open.
class _Options {
  const _Options({
    required this.lineColor,
    required this.showTorchButton,
    required this.scanWindow,
    required this.scanWindowSize,
    required this.cameraFace,
    required this.scanFormat,
    required this.bar,
    required this.flip,
    required this.flipVertical,
    required this.child,
    required this.backgroundColor,
    required this.buttons,
    required this.buttonsAlignment,
    required this.animate,
    required this.labels,
    required this.vibrate,
    required this.beep,
    required this.buttonStyle,
    this.cancelLabel,
    this.scanDelay,
    this.validator,
  });

  final Color lineColor;
  final String? cancelLabel;
  final bool showTorchButton;
  final ScanWindow scanWindow;
  final Size? scanWindowSize;
  final CameraFace cameraFace;
  final ScanFormat scanFormat;
  final ScannerBar? bar;
  final Duration? scanDelay;
  final bool? flip;
  final bool flipVertical;
  final Widget? child;
  final Color? backgroundColor;
  final Set<ScannerButton> buttons;
  final AlignmentGeometry buttonsAlignment;
  final bool animate;
  final ScannerLabels labels;
  final bool vibrate;
  final bool beep;
  final ScannerButtonStyle buttonStyle;
  final ScanValidator? validator;

  /// The page, reading on after each code when [continuous] or when a
  /// [validator] has to see every code until one is accepted.
  ScannerPage page(
    BuildContext context, {
    required bool continuous,
    required ValueChanged<ScanResult> onScanned,
    required VoidCallback onClose,
    required ValueChanged<ScannerException> onError,
    ScanVerdicts? verdicts,
  }) => ScannerPage(
    config: ScannerConfig(
      lineColor: lineColor,
      cancelLabel: cancelLabel ?? bar?.cancelLabel ?? 'Cancel',
      // The native screens have a torch button of their own.
      showTorchButton: showTorchButton || buttons.contains(ScannerButton.torch),
      scanWindow: scanWindow,
      scanWindowSize: scanWindowSize,
      cameraFace: cameraFace,
      scanFormat: scanFormat,
      scanDelay: scanDelay,
      continuous: continuous || validator != null,
      flipHorizontal: flip ?? UniversalBarcodeScanner.flipsByDefault,
      flipVertical: flipVertical,
      animate: UniversalBarcodeScanner._animates(context, animate),
      labels: labels,
    ),
    backgroundColor: backgroundColor,
    bar: bar,
    buttons: buttons,
    buttonsAlignment: buttonsAlignment,
    buttonStyle: buttonStyle,
    verdicts: verdicts,
    onScanned: onScanned,
    onClose: onClose,
    onError: onError,
    child: child,
  );

  /// Whether [result] counts. The verdict goes to [verdicts], for the page
  /// to show, and a refusal is felt when [vibrate] and heard when [beep].
  bool accepts(ScanResult result, ScanVerdicts verdicts) {
    final ScanValidator? validator = this.validator;
    if (validator == null || validator(result)) {
      verdicts.accepted();
      return true;
    }
    verdicts.rejected();
    ScanFeedback.rejected(vibrate: vibrate, beep: beep);
    return false;
  }
}
