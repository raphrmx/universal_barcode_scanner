/// Shape of the scan window on the native scanners.
///
/// It only draws the window: which codes are accepted is [ScanFormat]'s job.
enum ScanType {
  /// A square window, for QR codes.
  qr,

  /// A wide window, for linear barcodes.
  barcode,

  /// Same as [qr].
  defaultMode,
}

/// Which symbologies the scanner accepts, on every platform.
enum ScanFormat {
  /// Every symbology the platform supports.
  all('ALL_FORMATS'),

  /// QR codes only.
  onlyQrCode('ONLY_QR_CODE'),

  /// Linear barcodes only.
  onlyBarcode('ONLY_BARCODE');

  const ScanFormat(this.wireName);

  /// Value the native scanners expect over the method channel.
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
