import 'dart:math' as math;
import 'dart:typed_data';

/// The shape of a tone's wave.
enum ToneWave {
  /// Soft and pure.
  sine,

  /// Rich in overtones, which a phone's small speaker still plays when it
  /// cannot play the note itself.
  square,
}

/// A short tone, played once at each of [starts]: what a code read or
/// refused sounds like where the package makes the sound itself, in a
/// browser and on Windows.
final class Tone {
  const Tone({
    required this.hertz,
    required this.wave,
    required this.volume,
    required this.starts,
  });

  /// The code read: one high, soft beep.
  static const Tone accepted = Tone(
    hertz: 1800,
    wave: ToneWave.sine,
    volume: 0.2,
    starts: <double>[0],
  );

  /// The code refused: two lower, rougher beeps, with the two pulses of the
  /// vibration. Not lower than this: a phone's speaker plays little under
  /// 500 Hz.
  static const Tone rejected = Tone(
    hertz: 480,
    wave: ToneWave.square,
    volume: 0.12,
    starts: <double>[0, 0.15],
  );

  /// How long each beep lasts, in seconds, faded out rather than cut, which
  /// clicks.
  static const double length = 0.12;

  /// Where the fade ends, from [volume].
  static const double floor = 0.001;

  final double hertz;
  final ToneWave wave;
  final double volume;

  /// When each beep starts, in seconds.
  final List<double> starts;

  /// The tone as a 16-bit mono WAV file.
  Uint8List toWav({int rate = 22050}) {
    final double seconds = starts.reduce(math.max) + length;
    final int frames = (seconds * rate).ceil();
    final ByteData data = ByteData(44 + frames * 2);
    void text(int at, String value) {
      for (int i = 0; i < value.length; i++) {
        data.setUint8(at + i, value.codeUnitAt(i));
      }
    }

    text(0, 'RIFF');
    data.setUint32(4, 36 + frames * 2, Endian.little);
    text(8, 'WAVE');
    text(12, 'fmt ');
    data
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little) // PCM
      ..setUint16(22, 1, Endian.little) // mono
      ..setUint32(24, rate, Endian.little)
      ..setUint32(28, rate * 2, Endian.little)
      ..setUint16(32, 2, Endian.little)
      ..setUint16(34, 16, Endian.little);
    text(36, 'data');
    data.setUint32(40, frames * 2, Endian.little);

    for (int frame = 0; frame < frames; frame++) {
      final double time = frame / rate;
      double sample = 0;
      for (final double start in starts) {
        final double t = time - start;
        if (t < 0 || t >= length) continue;
        final double phase = math.sin(2 * math.pi * hertz * t);
        final double shape = switch (wave) {
          ToneWave.sine => phase,
          ToneWave.square => phase >= 0 ? 1 : -1,
        };
        // The same exponential fade as a browser's gain ramp.
        sample += shape * volume * math.pow(floor / volume, t / length);
      }
      data.setInt16(
        44 + frame * 2,
        (sample.clamp(-1.0, 1.0) * 32767).round(),
        Endian.little,
      );
    }
    return data.buffer.asUint8List();
  }
}
