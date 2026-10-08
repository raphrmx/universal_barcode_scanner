/// Shape of the scan window.
///
/// Codes are read inside it; which codes are accepted is [ScanFormat]'s job.
enum ScanWindow {
  /// A square, for QR codes and other two-dimensional codes.
  square,

  /// A wide rectangle, for linear barcodes.
  wide,

  /// No window: nothing is drawn over the camera, and the whole frame is
  /// read. For an app that draws its own guide over the scanner.
  none,
}

/// Which symbologies the scanner accepts, on every platform.
enum ScanFormat {
  /// Every symbology the platform supports.
  all('ALL_FORMATS'),

  /// QR codes only.
  onlyQrCode('ONLY_QR_CODE'),

  /// Linear barcodes only.
  onlyBarcode('ONLY_BARCODE'),

  /// No code at all: the camera only hands its frames to
  /// `UniversalBarcodeScanner.onFrame`, for an app that reads them itself,
  /// such as the text of a document.
  none('NONE');

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

/// A button over the camera, drawn by Flutter wherever the scanner is a
/// Flutter page or view.
enum ScannerButton {
  /// Turns the torch on and off, where the camera has one a page may drive.
  torch,

  /// Stops reading codes and starts again, the camera left running.
  pause,

  /// Mirrors the camera left to right.
  flipHorizontal,

  /// Shows the camera upside down.
  flipVertical,

  /// Goes through 1x, 2x and 3x zoom, as far as the camera can go.
  zoom,

  /// Goes from the camera facing away to the one facing the user, and back.
  switchCamera,
}
