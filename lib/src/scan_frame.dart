import 'package:flutter/foundation.dart';

/// A frame of the camera, in grey: what the scan window shows, for an app
/// that reads the picture itself, such as the text of a document.
///
/// One byte per pixel, the luminance, rows packed: the Y plane of the
/// camera where it gives one. [quarterTurns] says how to stand it upright,
/// since a phone's camera sees the world sideways.
///
/// ```dart
/// UniversalBarcodeScanner(
///   scanFormat: ScanFormat.none,
///   onFrame: (ScanFrame frame) => reader.add(frame),
///   onCreated: (_) {},
/// );
/// ```
@immutable
class ScanFrame {
  /// A frame of [width] by [height] pixels in [bytes], one byte each.
  const ScanFrame({
    required this.width,
    required this.height,
    required this.bytes,
    this.quarterTurns = 0,
  });

  /// A frame as a platform sends it, or null when it is malformed.
  static ScanFrame? fromWire(Object? data) {
    if (data case {
      'width': final int width,
      'height': final int height,
      'bytes': final Uint8List bytes,
    } when width > 0 && height > 0 && bytes.length >= width * height) {
      final Object? turns = data['quarterTurns'];
      return ScanFrame(
        width: width,
        height: height,
        bytes: bytes,
        quarterTurns: turns is int ? turns % 4 : 0,
      );
    }
    return null;
  }

  /// The width, as the bytes run.
  final int width;

  /// The height, as the bytes run.
  final int height;

  /// The luminance, [width] bytes a row, [height] rows.
  final Uint8List bytes;

  /// The quarter turns clockwise that stand the frame the way the user sees
  /// it, from 0 to 3.
  final int quarterTurns;

  @override
  String toString() => 'ScanFrame(${width}x$height, $quarterTurns turns)';
}
