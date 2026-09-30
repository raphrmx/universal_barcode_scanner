import AVFoundation
import Cocoa
import Vision

/// The camera and what reads its frames, shared by the scanner window and the
/// embedded view.
///
/// macOS has no equivalent of `AVCaptureMetadataOutput`'s barcode types, so
/// frames go through Vision's `VNDetectBarcodesRequest` instead. That is also
/// what Apple's own samples do on this platform.
final class ScannerCamera: NSObject {
  /// Called on the main thread with the codes of each frame that has any.
  var onCodes: (([ScannedCode]) -> Void)?

  /// Called on the main thread once, when the first frame arrives.
  var onFirstFrame: (() -> Void)?

  let session = AVCaptureSession()
  private let output = AVCaptureVideoDataOutput()
  private let frameQueue = DispatchQueue(
    label: "be.comapps.universal_barcode_scanner.frames"
  )
  private let sessionQueue = DispatchQueue(
    label: "be.comapps.universal_barcode_scanner.session"
  )

  // Touched on the frame queue only.
  /// Where Vision looks, in its normalised space, origin at the bottom left.
  private var regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
  private var reading = true
  private var sawFrame = false
  /// Built once: a request per frame was an allocation per frame.
  private let request: VNDetectBarcodesRequest

  init(scanFormat: String) {
    let request = VNDetectBarcodesRequest()
    let wanted = ScannerCamera.symbologies(for: scanFormat)
    if !wanted.isEmpty {
      request.symbologies = wanted
    }
    self.request = request
    super.init()
  }

  /// Opens the camera and starts it, off the main thread: opening the device
  /// and committing the configuration both block, as startRunning does.
  /// Completes on the main thread, with false when the camera or the frame
  /// output cannot be added: a preview that runs without decoding would look
  /// like a scanner that never reads anything.
  func start(_ completion: @escaping (Bool) -> Void) {
    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      let ready = self.configure()
      if ready { self.session.startRunning() }
      DispatchQueue.main.async { completion(ready) }
    }
  }

  func stop() {
    let capture = session
    sessionQueue.async {
      if capture.isRunning { capture.stopRunning() }
    }
  }

  /// Whether frames go through Vision. Off while an embedded view is paused,
  /// which keeps the camera running for nothing but the preview.
  func setReading(_ on: Bool) {
    frameQueue.async { [weak self] in self?.reading = on }
  }

  /// Makes Vision look inside `window`, in the preview layer's coordinates,
  /// as the other platforms do. Nil reads the whole frame.
  func readInside(_ window: CGRect?, of preview: AVCaptureVideoPreviewLayer) {
    let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
    var region = whole
    if let window = window, window.width > 0, window.height > 0 {
      let converted = preview.metadataOutputRectConverted(fromLayerRect: window)
      guard converted.width > 0, converted.height > 0 else { return }
      // Metadata space has its origin at the top left, Vision's at the bottom
      // left.
      region = CGRect(
        x: converted.minX,
        y: 1 - converted.maxY,
        width: converted.width,
        height: converted.height
      ).intersection(whole)
      guard !region.isEmpty else { return }
    }
    frameQueue.async { [weak self] in self?.regionOfInterest = region }
  }

  /// Runs on the session queue.
  private func configure() -> Bool {
    session.beginConfiguration()
    defer { session.commitConfiguration() }
    // Vision works on every frame it is given; 720p reads a code as well as
    // full HD, for less than half the pixels.
    session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .high

    guard let device = AVCaptureDevice.default(for: .video),
      let input = try? AVCaptureDeviceInput(device: device),
      session.canAddInput(input)
    else { return false }
    session.addInput(input)

    output.alwaysDiscardsLateVideoFrames = true
    output.setSampleBufferDelegate(self, queue: frameQueue)
    guard session.canAddOutput(output) else { return false }
    session.addOutput(output)
    return true
  }

  /// Symbologies Vision should look for, from the `scanFormat` the Dart side
  /// sent; empty for every one. Only the ones available since the deployment
  /// target are named, so the list needs no availability guard.
  static func symbologies(for scanFormat: String) -> [VNBarcodeSymbology] {
    switch scanFormat {
    case "ONLY_QR_CODE":
      return [.qr]
    case "ONLY_BARCODE":
      return [
        .code39, .code39Checksum, .code39FullASCII, .code39FullASCIIChecksum,
        .code93, .code93i, .code128,
        .ean8, .ean13, .upce,
        .i2of5, .i2of5Checksum, .itf14, .pdf417,
      ]
    default:
      return []
    }
  }
}

extension ScannerCamera: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    if !sawFrame {
      sawFrame = true
      DispatchQueue.main.async { [weak self] in self?.onFirstFrame?() }
    }
    guard reading, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

    request.regionOfInterest = regionOfInterest
    let handler = VNImageRequestHandler(cvPixelBuffer: buffer, options: [:])
    guard (try? handler.perform([request])) != nil,
      let results = request.results
    else { return }

    let codes = results.compactMap { result -> ScannedCode? in
      guard let value = result.payloadStringValue, !value.isEmpty else { return nil }
      return ScannedCode(value: value, symbology: result.symbology)
    }
    guard !codes.isEmpty else { return }
    DispatchQueue.main.async { [weak self] in self?.onCodes?(codes) }
  }
}

/// Asks for the camera if needed. Completes on the main thread.
enum CameraAccess {
  static func request(_ completion: @escaping (Bool) -> Void) {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      completion(true)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { granted in
        DispatchQueue.main.async { completion(granted) }
      }
    default:
      completion(false)
    }
  }
}

/// A code read, and the name of its symbology as every platform gives it,
/// the web's BarcodeDetector names.
struct ScannedCode {
  let value: String
  let format: String

  init(value: String, symbology: VNBarcodeSymbology) {
    self.value = value
    switch symbology {
    case .aztec: format = "aztec"
    case .code39, .code39Checksum, .code39FullASCII, .code39FullASCIIChecksum:
      format = "code_39"
    case .code93, .code93i: format = "code_93"
    case .code128: format = "code_128"
    case .dataMatrix: format = "data_matrix"
    case .ean8: format = "ean_8"
    case .ean13: format = "ean_13"
    case .i2of5, .i2of5Checksum, .itf14: format = "itf"
    case .pdf417: format = "pdf417"
    case .qr: format = "qr_code"
    case .upce: format = "upc_e"
    default:
      // Codabar came with macOS 12: by name, so older systems still build.
      format = symbology.rawValue.hasSuffix("Codabar") ? "codabar" : "unknown"
    }
  }

  /// What goes to Dart.
  var payload: [String: String] { ["code": value, "format": format] }
}
