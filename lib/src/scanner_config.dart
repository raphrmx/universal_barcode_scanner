import 'dart:convert';
import 'dart:ui' show Color, Size;

import 'package:flutter/foundation.dart';
import 'package:universal_barcode_scanner/src/constants.dart';
import 'package:universal_barcode_scanner/src/enums.dart';
import 'package:universal_barcode_scanner/src/scan_frame.dart';
import 'package:universal_barcode_scanner/src/scan_result.dart';
import 'package:universal_barcode_scanner/src/scanner_labels.dart';

/// Everything the scanner itself needs to know, whichever platform runs it.
///
/// What only concerns the Flutter side, such as the app bar or the widget
/// drawn over the camera, stays on the page.
@immutable
class ScannerConfig {
  /// Creates a configuration.
  const ScannerConfig({
    this.lineColor = kDefaultLineColor,
    this.cancelLabel = 'Cancel',
    this.showTorchButton = false,
    this.scanWindow = ScanWindow.wide,
    this.scanWindowSize,
    this.cameraFace = CameraFace.back,
    this.scanFormat = ScanFormat.all,
    this.scanDelay,
    this.continuous = false,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.animate = true,
    this.labels = ScannerLabels.english,
    this.frameInterval,
  });

  /// Colour of the scan line.
  final Color lineColor;

  /// Label of the cancel button on the native scanners.
  final String cancelLabel;

  /// Whether the native scanners show a torch toggle.
  final bool showTorchButton;

  /// Shape of the scan window: square for QR codes, wide for barcodes.
  final ScanWindow scanWindow;

  /// Size of the scan window in logical pixels, or null for one picked from
  /// the view and [scanWindow].
  final Size? scanWindowSize;

  /// Which camera to open.
  final CameraFace cameraFace;

  /// Symbologies to accept.
  final ScanFormat scanFormat;

  /// Least time between two codes in continuous mode.
  final Duration? scanDelay;

  /// Whether reading continues after the first code.
  final bool continuous;

  /// Whether the camera is shown mirrored left to right, as a webcam facing
  /// the user usually is. Only the picture turns: codes read the same.
  final bool flipHorizontal;

  /// Whether the camera is shown upside down.
  final bool flipVertical;

  /// Whether the camera fades in when it starts and turns over when it is
  /// flipped, rather than appearing and flipping at once.
  final bool animate;

  /// The words the scanner shows or says.
  final ScannerLabels labels;

  /// Least time between two frames handed to the app, or null for none.
  final Duration? frameInterval;

  /// This configuration with what the buttons change as given.
  ScannerConfig copyWith({
    bool? flipHorizontal,
    bool? flipVertical,
    CameraFace? cameraFace,
  }) => ScannerConfig(
    lineColor: lineColor,
    cancelLabel: cancelLabel,
    showTorchButton: showTorchButton,
    scanWindow: scanWindow,
    scanWindowSize: scanWindowSize,
    cameraFace: cameraFace ?? this.cameraFace,
    scanFormat: scanFormat,
    scanDelay: scanDelay,
    continuous: continuous,
    flipHorizontal: flipHorizontal ?? this.flipHorizontal,
    flipVertical: flipVertical ?? this.flipVertical,
    animate: animate,
    labels: labels,
    frameInterval: frameInterval,
  );

  /// Milliseconds between two frames for the app, zero when it wants none.
  int get frameMillis => switch (frameInterval) {
    null => 0,
    final Duration interval =>
      interval.inMilliseconds < 1 ? 1 : interval.inMilliseconds,
  };

  /// Milliseconds of [scanDelay], zero when there is none.
  int get delayMillis => scanDelay?.inMilliseconds ?? 0;

  /// Arguments of `scanBarcode` for the Android, iOS and macOS scanners.
  Map<String, Object?> toNative() => <String, Object?>{
    'lineColor': colorToHex(lineColor),
    'cancelLabel': cancelLabel,
    'showTorchButton': showTorchButton,
    'continuous': continuous,
    'scanWindow': scanWindow.name,
    if (scanWindowSize case final Size size) ...<String, Object?>{
      'scanWindowWidth': size.width,
      'scanWindowHeight': size.height,
    },
    'cameraFace': cameraFace.name,
    'scanFormat': scanFormat.wireName,
    'delayMillis': delayMillis,
    // Only when asked for: a plugin from before frames sees what it knows.
    if (frameMillis > 0) 'frameMillis': frameMillis,
  };

  /// Settings of the bundled page, read by its `configure` function on the
  /// desktop and from the query string on the web. [host] is `web` or
  /// `desktop`, which changes what the page tells the user when the camera
  /// does not start.
  ///
  /// The background is always sent, black when null: the desktop page is kept
  /// between two scans and would otherwise keep the previous one's colour.
  Map<String, String> toPage({required String host, Color? background}) =>
      <String, String>{
        'host': host,
        'line': colorToCssHex(lineColor),
        'background': colorToCssHex(background ?? const Color(0xFF000000)),
        'continuous': continuous ? '1' : '0',
        'delay': '$delayMillis',
        'facing': facingToPage(cameraFace),
        'window': scanWindow.name,
        // A full page reads the size asked for; an embedded view sends the
        // window Flutter lays out instead.
        if (scanWindowSize case final Size size) ...windowToPage(size),
        ...flipToPage(flipHorizontal, flipVertical),
        'animate': animate ? '1' : '0',
        'labels': jsonEncode(labels.toPage(host: host)),
        'formats': formatsToPage(scanFormat),
        if (frameMillis > 0) 'frames': '$frameMillis',
      };

  /// Settings of the bundled page run as an embedded view. The camera fills
  /// the view, and the page reads inside [window], the scan window Flutter
  /// draws over it, in logical pixels and centred.
  Map<String, String> toEmbeddedPage({
    required String host,
    required Size window,
  }) => <String, String>{
    ...toPage(host: host),
    'embedded': '1',
    ...windowToPage(window),
  };

  /// The camera the page opens, as `getUserMedia` names it.
  /// What the page calls [format].
  static String formatsToPage(ScanFormat format) => switch (format) {
    ScanFormat.all => 'all',
    ScanFormat.onlyQrCode => 'qr',
    ScanFormat.onlyBarcode => 'barcode',
    ScanFormat.none => 'none',
  };

  /// What the page calls [face].
  static String facingToPage(CameraFace face) =>
      face == CameraFace.front ? 'user' : 'environment';

  /// How the page flips the camera.
  static Map<String, String> flipToPage(bool horizontal, bool vertical) =>
      <String, String>{
        'flipX': horizontal ? '1' : '0',
        'flipY': vertical ? '1' : '0',
      };

  /// The scan window as the page reads it.
  static Map<String, String> windowToPage(Size window) => <String, String>{
    'windowWidth': '${window.width.round()}',
    'windowHeight': '${window.height.round()}',
  };
}

/// A message from the bundled page: a code, the user asking to close, a
/// camera that would not start, or the torch's new state.
///
/// The page posts JSON rather than the bare code, so that no code can be
/// mistaken for a command.
sealed class PageMessage {
  const PageMessage();

  /// Reads what the page posted, or null when it is not one of its messages.
  static PageMessage? parse(Object? data) {
    if (data is! String || data.isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(data);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final Object? image = decoded['image'];
    if (image is int) {
      final Object? codes = decoded['codes'];
      return PageImage(
        image,
        codes is List
            ? <ScanResult>[
                for (final Object? found in codes)
                  if (found case {
                    'code': final String code,
                    'format': final Object? format,
                  } when code.isNotEmpty)
                    ScanResult(code, format: BarcodeFormat.fromWire(format)),
              ]
            : null,
        failed: decoded['failed'] as String?,
        message: decoded['message'] as String?,
      );
    }
    final Object? frame = decoded['frame'];
    if (frame is Map) {
      final Object? data = frame['data'];
      if (data is! String) return null;
      final Uint8List bytes;
      try {
        bytes = base64Decode(data);
      } on FormatException {
        return null;
      }
      final ScanFrame? read = ScanFrame.fromWire(<String, Object?>{
        'width': frame['width'],
        'height': frame['height'],
        'bytes': bytes,
      });
      return read == null ? null : PageFrame(read);
    }
    final Object? code = decoded['code'];
    if (code is String && code.isNotEmpty) {
      return PageCode(code, format: BarcodeFormat.fromWire(decoded['format']));
    }
    if (decoded['close'] == true) return const PageClose();
    final Object? error = decoded['error'];
    if (error is Map) {
      return PageError('${error['code']}', error['message'] as String?);
    }
    final Object? torch = decoded['torch'];
    if (torch is bool) return PageTorch(on: torch);
    final Object? zoom = decoded['zoom'];
    if (zoom is num) return PageZoom(zoom.toDouble());
    if (decoded['ready'] == true) return const PageReady();
    return null;
  }
}

/// A code the page read.
final class PageCode extends PageMessage {
  /// Wraps [code], printed in [format].
  const PageCode(this.code, {this.format = BarcodeFormat.unknown});

  /// The payload.
  final String code;

  /// Its symbology.
  final BarcodeFormat format;
}

/// The zoom the camera applied, in answer to `setZoom`.
final class PageZoom extends PageMessage {
  /// Wraps the zoom applied.
  const PageZoom(this.zoom);

  /// `1` for none.
  final double zoom;
}

/// The user asked the page to close, with the Escape key.
final class PageClose extends PageMessage {
  /// Creates the message.
  const PageClose();
}

/// The camera did not start. [code] is one of the wire names of
/// `ScannerErrorCode`.
final class PageError extends PageMessage {
  /// Wraps an error.
  const PageError(this.code, this.message);

  /// What went wrong.
  final String code;

  /// The browser's own words, for a log.
  final String? message;
}

/// The codes the page read in an image, or why it could not.
final class PageImage extends PageMessage {
  /// The answer to the image [id].
  const PageImage(this.id, this.results, {this.failed, this.message});

  /// The request it answers.
  final int id;

  /// Every code read, null when the page [failed].
  final List<ScanResult>? results;

  /// One of the wire names of `ScannerErrorCode`.
  final String? failed;

  /// The browser's own words, for a log.
  final String? message;
}

/// A frame of the camera, for the app's `onFrame`.
final class PageFrame extends PageMessage {
  /// Wraps [frame].
  const PageFrame(this.frame);

  /// The frame.
  final ScanFrame frame;
}

/// The page has loaded and taken its settings: it takes calls from now on.
final class PageReady extends PageMessage {
  /// Creates the message.
  const PageReady();
}

/// The torch was toggled, or could not be.
final class PageTorch extends PageMessage {
  /// Wraps the torch's state.
  const PageTorch({required this.on});

  /// Whether the torch is now on.
  final bool on;
}
