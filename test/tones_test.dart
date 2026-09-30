import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_barcode_scanner/src/scan_feedback.dart';
import 'package:universal_barcode_scanner/src/tones.dart';

void main() {
  test('a tone is a mono 16-bit WAV file of its length', () {
    final Uint8List wav = Tone.accepted.toWav(rate: 8000);
    final ByteData data = ByteData.sublistView(wav);

    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(data.getUint16(22, Endian.little), 1);
    expect(data.getUint32(24, Endian.little), 8000);
    expect(data.getUint16(34, Endian.little), 16);
    // 0.12 s at 8000 frames a second, two bytes each.
    expect(data.getUint32(40, Endian.little), 960 * 2);
    expect(wav.length, 44 + 960 * 2);
  });

  test('a refusal beeps twice, with the two pulses of the vibration', () {
    expect(Tone.rejected.starts, hasLength(2));
    expect(
      Tone.rejected.starts[1] * 1000,
      ScanFeedback.rejectedPulseGap.inMilliseconds,
    );
    // Low enough to sound unlike a code read, high enough for a phone.
    expect(Tone.rejected.hertz, lessThan(Tone.accepted.hertz));
    expect(Tone.rejected.hertz, greaterThanOrEqualTo(440));

    final ByteData data = ByteData.sublistView(Tone.rejected.toWav(rate: 8000));
    int sample(double seconds) =>
        data.getInt16(44 + (seconds * 8000).round() * 2, Endian.little).abs();
    // Sound, silence between the two, sound again.
    expect(sample(0.001), greaterThan(1000));
    expect(sample(0.13), 0);
    expect(sample(0.151), greaterThan(1000));
  });
}
