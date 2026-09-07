/// What the scanner is pointed at.
enum ScanType {
  /// QR codes only.
  qr,

  /// Linear barcodes only.
  barcode,

  /// Whatever the platform scanner reads by default.
  defaultMode,
}

/// Which symbologies the native scanners accept.
enum ScanFormat {
  /// Every symbology the platform supports.
  all('ALL_FORMATS'),

  /// QR codes only.
  onlyQrCode('ONLY_QR_CODE'),

  /// Linear barcodes only.
  onlyBarcode('ONLY_BARCODE');

  const ScanFormat(this.wireName);

  /// Value the Android and iOS scanners expect over the method channel.
  ///
  /// Kept apart from the Dart name so the enum can be renamed without
  /// touching the native side, and the other way round.
  final String wireName;
}

/// Which camera to open.
enum CameraFace {
  /// The rear camera, the one you scan with.
  back,

  /// The front camera.
  front,
}
