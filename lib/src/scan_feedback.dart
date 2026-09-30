import 'dart:async';

import 'package:flutter/services.dart';
import 'package:universal_barcode_scanner/src/platform/shared.dart'
    show playBeep, playRejectedBeep;

/// What signals a code read: a short vibration, a short beep, or both.
abstract final class ScanFeedback {
  /// Signals one code read as asked.
  static void play({required bool vibrate, required bool beep}) {
    // A phone vibrates, a browser on a phone too; elsewhere nothing happens.
    if (vibrate) unawaited(HapticFeedback.mediumImpact());
    if (beep) playBeep();
  }

  /// Time between the two pulses of a refusal, felt and shown.
  static const Duration rejectedPulseGap = Duration(milliseconds: 150);

  /// Signals a code the validator refused: two pulses, which the red edge
  /// over the camera flashes with, and a lower sound than for a code read.
  static void rejected({required bool vibrate, required bool beep}) {
    if (beep) playRejectedBeep();
    if (!vibrate) return;
    unawaited(HapticFeedback.heavyImpact());
    Timer(rejectedPulseGap, () => unawaited(HapticFeedback.heavyImpact()));
  }
}
