import 'dart:async';

import 'package:flutter/services.dart';
import 'package:universal_barcode_scanner/src/scan_result.dart';
import 'package:universal_barcode_scanner/src/scanner_config.dart';
import 'package:universal_barcode_scanner/src/scanner_exception.dart';

/// The Android, iOS and macOS scanners, over their method and event channels.
///
/// Every scan carries a session number. `scanBarcode` answers with the code
/// read, or null when the user backs out. In continuous mode it answers as
/// soon as the scanner is up, and the event channel carries
/// `{'session': n, 'code': ...}` for every code, an error whose details are
/// the session for a failure, and `{'session': n, 'event': 'closed'}` at the
/// end. `close` takes the session it means, so a late close or a late event
/// from a scanner that is going away never reaches the next one. No payload
/// is reserved: a code that reads `-1` is a code.
abstract final class NativeScanner {
  static const MethodChannel _channel = MethodChannel(
    'universal_barcode_scanner',
  );

  static const EventChannel _events = EventChannel(
    'universal_barcode_scanner/events',
  );

  static int _lastSession = 0;

  /// A number no earlier scan used.
  static int newSession() => ++_lastSession;

  static Map<String, Object?> _arguments(ScannerConfig config, int session) =>
      <String, Object?>{...config.toNative(), 'session': session};

  /// A code as a scanner answers it: a map with its format, or the bare code
  /// from an older one.
  static ScanResult? _result(Object? answer) {
    final (Object? code, Object? format) = switch (answer) {
      Map<Object?, Object?>() => (answer['code'], answer['format']),
      _ => (answer, null),
    };
    if (code is! String || code.isEmpty) return null;
    return ScanResult(code, format: BarcodeFormat.fromWire(format));
  }

  /// Scans until a code is read, then returns it. Null when the user backs
  /// out; a [ScannerException] when the camera cannot be used.
  static Future<ScanResult?> scan(
    ScannerConfig config, {
    required int session,
  }) async {
    try {
      return _result(
        await _channel.invokeMethod<Object?>(
          'scanBarcode',
          _arguments(config, session),
        ),
      );
    } on Object catch (error) {
      throw ScannerException.from(error);
    }
  }

  /// Opens the scanner and emits every code read until it closes.
  ///
  /// Cancelling the subscription closes the scanner. A failure is emitted as a
  /// [ScannerException], after which the stream closes.
  static Stream<ScanResult> stream(
    ScannerConfig config, {
    required int session,
  }) {
    StreamSubscription<dynamic>? events;
    late final StreamController<ScanResult> codes;

    // Closes without waiting for the platform to acknowledge the end of the
    // event channel: the caller has nothing to wait for.
    void finish() {
      unawaited(events?.cancel());
      events = null;
      if (!codes.isClosed) unawaited(codes.close());
    }

    void fail(Object error) {
      // An error meant for another scan.
      if (error is PlatformException &&
          error.details is int &&
          error.details != session) {
        return;
      }
      if (!codes.isClosed) codes.addError(ScannerException.from(error));
      finish();
    }

    codes = StreamController<ScanResult>(
      onListen: () {
        // Listening first: the native side only has somewhere to send codes
        // once the event channel is open.
        events = _events.receiveBroadcastStream().listen(
          (dynamic event) {
            if (event is! Map || event['session'] != session) return;
            final ScanResult? result = _result(event);
            if (result != null) {
              if (!codes.isClosed) codes.add(result);
            } else if (event['event'] == 'closed') {
              finish();
            }
          },
          onError: fail,
          onDone: finish,
        );
        unawaited(
          _channel
              .invokeMethod<void>('scanBarcode', _arguments(config, session))
              .catchError(fail),
        );
      },
      onCancel: () {
        final bool open = events != null;
        finish();
        if (open) unawaited(close(session));
      },
    );
    return codes.stream;
  }

  /// A short beep, on the platforms whose plugin plays one.
  static Future<void> beep() async {
    try {
      await _channel.invokeMethod<void>('beep');
    } on Object {
      // An older plugin, or no sound to play.
    }
  }

  /// Closes the scanner of [session] if it is still open, even if it is still
  /// being opened. A single scan closed this way completes with null.
  static Future<void> close(int session) async {
    try {
      await _channel.invokeMethod<void>('close', <String, Object?>{
        'session': session,
      });
    } on MissingPluginException {
      // No scanner to close on this platform.
    } on PlatformException {
      // Nothing was open.
    }
  }
}
