import 'dart:async';

import 'package:flutter/services.dart';
import 'package:universal_barcode_scanner/src/scanner_config.dart';
import 'package:universal_barcode_scanner/src/scanner_exception.dart';

/// The Android, iOS and macOS scanners, over their method and event channels.
///
/// `scanBarcode` answers with the code read, or null when the user backs out.
/// In continuous mode it answers as soon as the scanner is up, and the event
/// channel carries every code as a string, a failure as an error, and the end
/// of the scan as `{'event': 'closed'}`. No payload is reserved: a code that
/// reads `-1` is a code.
///
/// Derived from https://github.com/AmolGangadhare/flutter_barcode_scanner.
abstract final class NativeScanner {
  static const MethodChannel _channel = MethodChannel(
    'universal_barcode_scanner',
  );

  static const EventChannel _events = EventChannel(
    'universal_barcode_scanner/events',
  );

  /// Scans until a code is read, then returns it. Null when the user backs
  /// out; a [ScannerException] when the camera cannot be used.
  static Future<String?> scan(ScannerConfig config) async {
    try {
      final Object? code = await _channel.invokeMethod<Object?>(
        'scanBarcode',
        config.toNative(),
      );
      return code is String && code.isNotEmpty ? code : null;
    } on Object catch (error) {
      throw ScannerException.from(error);
    }
  }

  /// Opens the scanner and emits every code read until it closes.
  ///
  /// Cancelling the subscription closes the scanner. A failure is emitted as a
  /// [ScannerException], after which the stream closes.
  static Stream<String> stream(ScannerConfig config) {
    StreamSubscription<dynamic>? events;
    late final StreamController<String> codes;

    // Closes without waiting for the platform to acknowledge the end of the
    // event channel: the caller has nothing to wait for.
    void finish() {
      unawaited(events?.cancel());
      events = null;
      if (!codes.isClosed) unawaited(codes.close());
    }

    void fail(Object error) {
      if (!codes.isClosed) codes.addError(ScannerException.from(error));
      finish();
    }

    codes = StreamController<String>(
      onListen: () {
        // Listening first: the native side only has somewhere to send codes
        // once the event channel is open.
        events = _events.receiveBroadcastStream().listen(
          (dynamic event) {
            if (event is String) {
              if (event.isNotEmpty && !codes.isClosed) codes.add(event);
            } else if (event is Map && event['event'] == 'closed') {
              finish();
            }
          },
          onError: fail,
          onDone: finish,
        );
        _channel
            .invokeMethod<void>('scanBarcode', config.toNative())
            .catchError(fail);
      },
      onCancel: () {
        final bool open = events != null;
        finish();
        if (open) unawaited(close());
      },
    );
    return codes.stream;
  }

  /// Closes whichever native scanner is on screen, if any. A single scan in
  /// progress completes with null.
  static Future<void> close() async {
    try {
      await _channel.invokeMethod<void>('close');
    } on MissingPluginException {
      // No scanner to close on this platform.
    } on PlatformException {
      // Nothing was open.
    }
  }
}
