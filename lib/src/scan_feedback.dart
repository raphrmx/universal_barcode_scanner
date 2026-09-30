import 'dart:async';

import 'package:flutter/services.dart';
import 'package:universal_barcode_scanner/src/platform/shared.dart'
    show playBeep;

/// What signals a code read: a short vibration, a short beep, or both.
abstract final class ScanFeedback {
  /// Signals one code read as asked.
  static void play({required bool vibrate, required bool beep}) {
    // A phone vibrates, a browser on a phone too; elsewhere nothing happens.
    if (vibrate) unawaited(HapticFeedback.mediumImpact());
    if (beep) playBeep();
  }

  /// Signals a code the validator refused: a heavier vibration, and no beep.
  static void rejected({required bool vibrate}) {
    if (vibrate) unawaited(HapticFeedback.heavyImpact());
  }
}
