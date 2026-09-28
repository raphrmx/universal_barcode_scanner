import 'package:flutter/services.dart';

/// Why the scanner could not open or had to stop.
enum ScannerErrorCode {
  /// The user refused the camera, now or earlier.
  permissionDenied('camera_permission_denied'),

  /// There is no camera, or it could not be started.
  cameraUnavailable('camera_unavailable'),

  /// Another scanner is already on screen.
  alreadyActive('already_active'),

  /// Anything the platform reported that has no code of its own here.
  unknown('unknown');

  const ScannerErrorCode(this.wireName);

  /// Code the native scanners send over the method channel.
  final String wireName;

  /// The value matching [code], or [unknown].
  static ScannerErrorCode fromWire(String code) {
    for (final ScannerErrorCode value in values) {
      if (value.wireName == code) return value;
    }
    return unknown;
  }
}

/// Thrown by `UniversalBarcodeScanner.scan`, and emitted on the stream of
/// `UniversalBarcodeScanner.stream`, when the scanner cannot do its job.
///
/// Only the native scanners raise it: Android, iOS and macOS. The web, Windows
/// and Linux scanner explains a missing camera on its own page instead.
class ScannerException implements Exception {
  /// Creates an exception with a [code] and an optional [message].
  const ScannerException(this.code, [this.message]);

  /// Converts whatever a channel call failed with.
  factory ScannerException.from(Object error) => switch (error) {
    final ScannerException exception => exception,
    final PlatformException exception => ScannerException(
      ScannerErrorCode.fromWire(exception.code),
      exception.message,
    ),
    final MissingPluginException exception => ScannerException(
      ScannerErrorCode.cameraUnavailable,
      exception.message,
    ),
    _ => ScannerException(ScannerErrorCode.unknown, error.toString()),
  };

  /// What went wrong.
  final ScannerErrorCode code;

  /// Detail from the platform, for a log rather than for the user.
  final String? message;

  @override
  String toString() {
    final String? message = this.message;
    return message == null
        ? 'ScannerException(${code.name})'
        : 'ScannerException(${code.name}: $message)';
  }
}
