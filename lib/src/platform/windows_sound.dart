import 'dart:ffi';
import 'dart:typed_data';

import 'package:universal_barcode_scanner/src/tones.dart';

/// Plays the package's own tones on Windows, where Flutter plays only the
/// system's alert sound, through `PlaySound` of `winmm.dll`. No package:
/// `dart:ffi` reaches it directly.
abstract final class WindowsSound {
  static const int _sndAsync = 0x0001;
  static const int _sndNoDefault = 0x0002;
  static const int _sndMemory = 0x0004;

  static final int Function(Pointer<Uint8>, int, int)? _playSound = () {
    try {
      return DynamicLibrary.open('winmm.dll').lookupFunction<
        Int32 Function(Pointer<Uint8>, IntPtr, Uint32),
        int Function(Pointer<Uint8>, int, int)
      >('PlaySoundW');
    } on Object {
      return null;
    }
  }();

  static final Pointer<Uint8> Function(int, int)? _localAlloc = () {
    try {
      return DynamicLibrary.open('kernel32.dll').lookupFunction<
        Pointer<Uint8> Function(Uint32, IntPtr),
        Pointer<Uint8> Function(int, int)
      >('LocalAlloc');
    } on Object {
      return null;
    }
  }();

  /// Each tone as a WAV file in native memory, made once and kept: an
  /// asynchronous `PlaySound` reads it while it plays.
  static final Map<Tone, Pointer<Uint8>> _files = <Tone, Pointer<Uint8>>{};

  /// Plays [tone], and says whether it could.
  static bool play(Tone tone) {
    final int Function(Pointer<Uint8>, int, int)? playSound = _playSound;
    if (playSound == null) return false;
    final Pointer<Uint8>? file = _files[tone] ?? _load(tone.toWav());
    if (file == null) return false;
    _files[tone] = file;
    return playSound(file, 0, _sndAsync | _sndMemory | _sndNoDefault) != 0;
  }

  static Pointer<Uint8>? _load(Uint8List wav) {
    final Pointer<Uint8> Function(int, int)? localAlloc = _localAlloc;
    if (localAlloc == null) return null;
    // LMEM_FIXED: a plain pointer.
    final Pointer<Uint8> file = localAlloc(0, wav.length);
    if (file == nullptr) return null;
    file.asTypedList(wav.length).setAll(0, wav);
    return file;
  }
}
