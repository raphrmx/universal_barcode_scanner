import 'package:flutter/foundation.dart';

/// The symbology of a code read.
enum BarcodeFormat {
  aztec('aztec'),
  codabar('codabar'),
  code39('code_39'),
  code93('code_93'),
  code128('code_128'),
  dataMatrix('data_matrix'),
  ean8('ean_8'),
  ean13('ean_13'),
  itf('itf'),
  pdf417('pdf417'),
  qrCode('qr_code'),
  upcA('upc_a'),
  upcE('upc_e'),

  /// A symbology this list does not name, or a platform that did not say.
  unknown('unknown');

  const BarcodeFormat(this.wireName);

  /// The name every platform reports it under, as the web's BarcodeDetector
  /// names it.
  final String wireName;

  /// The format named [wire], [unknown] for a name not on the list.
  static BarcodeFormat fromWire(Object? wire) {
    for (final BarcodeFormat format in values) {
      if (format.wireName == wire) return format;
    }
    return unknown;
  }

  /// Whether this is a two-dimensional code rather than a line of bars.
  bool get isTwoDimensional => switch (this) {
    aztec || dataMatrix || pdf417 || qrCode => true,
    _ => false,
  };
}

/// A code read: its text, and the symbology it was printed in.
@immutable
class ScanResult {
  /// A code of [format] reading [text].
  const ScanResult(this.text, {this.format = BarcodeFormat.unknown});

  /// What the code says.
  final String text;

  /// How it was printed.
  final BarcodeFormat format;

  @override
  bool operator ==(Object other) =>
      other is ScanResult && other.text == text && other.format == format;

  @override
  int get hashCode => Object.hash(text, format);

  @override
  String toString() => 'ScanResult($text, ${format.name})';
}
