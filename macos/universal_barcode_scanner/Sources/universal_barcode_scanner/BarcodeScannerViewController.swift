import AVFoundation
import Cocoa
import Vision

/// The scanner itself: a camera preview, a scan window with its sweeping
/// line, and a cancel button that Escape also presses.
///
/// macOS has no equivalent of `AVCaptureMetadataOutput`'s barcode types, so
/// frames go through Vision's `VNDetectBarcodesRequest` instead. That is also
/// what Apple's own samples do on this platform.
class BarcodeScannerViewController: NSViewController {
  /// Called on the main thread with each code worth reporting.
  var onScanned: ((String) -> Void)?
  /// Called when the user closes the scanner without a result.
  var onCancelled: (() -> Void)?
  /// Called with an error code and a message when the camera cannot be used.
  var onFailed: ((String, String) -> Void)?

  private let options: ScannerOptions
  private let session = AVCaptureSession()
  private let output = AVCaptureVideoDataOutput()
  private let frameQueue = DispatchQueue(
    label: "be.comapps.universal_barcode_scanner.frames"
  )
  private let sessionQueue = DispatchQueue(
    label: "be.comapps.universal_barcode_scanner.session"
  )

  private var previewLayer: AVCaptureVideoPreviewLayer?
  private let dimLayer = CAShapeLayer()
  private let outlineLayer = CAShapeLayer()
  private let lineLayer = CALayer()
  private var scanWindow: CGRect = .zero

  // Touched on the frame queue only.
  private var hasResult = false
  private var gate: ReadGate
  /// Where Vision looks, in its normalised space, origin at the bottom left.
  private var regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)

  /// Built once: a request per frame was an allocation per frame.
  private lazy var request: VNDetectBarcodesRequest = {
    let request = VNDetectBarcodesRequest()
    let wanted = self.symbologies
    if !wanted.isEmpty {
      request.symbologies = wanted
    }
    return request
  }()

  init(options: ScannerOptions) {
    self.options = options
    gate = ReadGate(delay: options.delay)
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not used")
  }

  override func loadView() {
    view = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.black.cgColor
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    configureLayers()
    configureCancelButton()

    // Opening the device and committing the configuration both block; the
    // main thread is kept out of it, as it is of startRunning.
    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      let ready = self.configureSession()
      if ready { self.session.startRunning() }
      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        if ready {
          self.updateRegionOfInterest()
        } else {
          self.onFailed?("camera_unavailable", "The camera could not be opened.")
        }
      }
    }
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    layoutLayers()
  }

  override func viewWillDisappear() {
    super.viewWillDisappear()
    stop()
  }

  // MARK: - Capture

  /// Runs on the session queue. False when the camera or the frame output
  /// cannot be added: a preview that runs without decoding would look like a
  /// scanner that never reads anything.
  private func configureSession() -> Bool {
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

  func stop() {
    let capture = session
    sessionQueue.async {
      if capture.isRunning { capture.stopRunning() }
    }
  }

  // MARK: - Chrome

  private func configureLayers() {
    let preview = AVCaptureVideoPreviewLayer(session: session)
    preview.videoGravity = .resizeAspectFill
    view.layer?.addSublayer(preview)
    previewLayer = preview

    dimLayer.fillRule = .evenOdd
    dimLayer.fillColor = NSColor(white: 0, alpha: 0.5).cgColor
    outlineLayer.fillColor = nil
    outlineLayer.strokeColor = NSColor(white: 1, alpha: 0.8).cgColor
    outlineLayer.lineWidth = 2
    lineLayer.backgroundColor = options.lineColor.cgColor
    view.layer?.addSublayer(dimLayer)
    view.layer?.addSublayer(outlineLayer)
    view.layer?.addSublayer(lineLayer)
  }

  /// The window, square for QR codes and wide for barcodes, above the cancel
  /// button's strip.
  private func layoutLayers() {
    let bounds = view.bounds
    let reserved: CGFloat = 56
    let area = CGRect(
      x: 0,
      y: reserved,
      width: bounds.width,
      height: max(0, bounds.height - reserved)
    )
    let size: CGSize
    if options.squareWindow {
      let side = min(area.width, area.height) * 0.75
      size = CGSize(width: side, height: side)
    } else {
      let width = area.width * 0.85
      size = CGSize(width: width, height: min(width * 0.5, area.height * 0.8))
    }
    let window = CGRect(
      x: area.midX - size.width / 2,
      y: area.midY - size.height / 2,
      width: size.width,
      height: size.height
    )

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    previewLayer?.frame = bounds
    dimLayer.frame = bounds
    let path = CGMutablePath()
    path.addRect(bounds)
    path.addRect(window)
    dimLayer.path = path
    outlineLayer.frame = bounds
    outlineLayer.path = CGPath(rect: window, transform: nil)
    lineLayer.frame = CGRect(x: window.minX, y: window.midY, width: window.width, height: 2)
    CATransaction.commit()

    if window != scanWindow {
      scanWindow = window
      sweep()
      updateRegionOfInterest()
    }
  }

  private func sweep() {
    lineLayer.removeAllAnimations()
    guard scanWindow.height > 4,
      !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    else { return }
    let animation = CABasicAnimation(keyPath: "position.y")
    animation.fromValue = scanWindow.minY + 1
    animation.toValue = scanWindow.maxY - 1
    animation.duration = 1.5
    animation.autoreverses = true
    animation.repeatCount = .infinity
    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    animation.isRemovedOnCompletion = false
    lineLayer.add(animation, forKey: "sweep")
  }

  /// Makes Vision look inside the window only, as the other platforms do.
  private func updateRegionOfInterest() {
    guard let preview = previewLayer, scanWindow.width > 0, scanWindow.height > 0 else { return }
    let converted = preview.metadataOutputRectConverted(fromLayerRect: scanWindow)
    guard converted.width > 0, converted.height > 0 else { return }
    // Metadata space has its origin at the top left, Vision's at the bottom
    // left.
    let region = CGRect(
      x: converted.minX,
      y: 1 - converted.maxY,
      width: converted.width,
      height: converted.height
    ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    guard !region.isEmpty else { return }
    frameQueue.async { [weak self] in self?.regionOfInterest = region }
  }

  private func configureCancelButton() {
    let button = NSButton(
      title: options.cancelButtonText,
      target: self,
      action: #selector(cancelClicked)
    )
    button.bezelStyle = .rounded
    // Escape: a sheet has no close button of its own.
    button.keyEquivalent = "\u{1b}"
    button.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(button)

    NSLayoutConstraint.activate([
      button.trailingAnchor.constraint(
        equalTo: view.trailingAnchor,
        constant: -16
      ),
      button.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
    ])
  }

  @objc private func cancelClicked() {
    stop()
    onCancelled?()
  }

  // MARK: - Decoding

  /// Symbologies Vision should look for, from the `scanFormat` the Dart side
  /// sent. Only the ones available since the deployment target are named, so
  /// the list needs no availability guard.
  private var symbologies: [VNBarcodeSymbology] {
    switch options.scanFormat {
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

  /// Runs on the frame queue with the codes of one frame.
  private func handle(_ codes: [String]) {
    guard !hasResult, let first = codes.first else { return }

    if options.isContinuousScan {
      // Every code of the frame goes through the gate, which follows each
      // one on its own.
      for code in codes where gate.accept(code) {
        DispatchQueue.main.async { [weak self] in self?.onScanned?(code) }
      }
      return
    }

    hasResult = true
    stop()
    DispatchQueue.main.async { [weak self] in self?.onScanned?(first) }
  }
}

extension BarcodeScannerViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard !hasResult,
      let buffer = CMSampleBufferGetImageBuffer(sampleBuffer)
    else { return }

    request.regionOfInterest = regionOfInterest
    let handler = VNImageRequestHandler(cvPixelBuffer: buffer, options: [:])
    guard (try? handler.perform([request])) != nil,
      let results = request.results as? [VNBarcodeObservation]
    else { return }

    let codes = results.compactMap { $0.payloadStringValue }.filter { !$0.isEmpty }
    handle(codes)
  }
}

/// Decides which of the codes read frame after frame are worth reporting.
///
/// The same rule as on every other platform: a code held in front of the
/// camera is reported once, and again only after a second out of sight; each
/// code is followed on its own; no two codes are reported less than `delay`
/// apart, and one the delay held back goes out as soon as it allows.
final class ReadGate {
  static let sameCodeGap: TimeInterval = 1.0

  private struct Sighting {
    var seen: TimeInterval
    var reported: Bool
  }

  private let delay: TimeInterval
  private var sightings: [String: Sighting] = [:]
  private var lastEmit: TimeInterval?

  init(delay: TimeInterval) {
    self.delay = max(0, delay)
  }

  func accept(_ value: String, now: TimeInterval = CACurrentMediaTime()) -> Bool {
    sightings = sightings.filter { now - $0.value.seen < ReadGate.sameCodeGap }
    var sighting = sightings[value] ?? Sighting(seen: now, reported: false)
    sighting.seen = now
    if sighting.reported {
      sightings[value] = sighting
      return false
    }
    if let last = lastEmit, now - last < delay {
      sightings[value] = sighting
      return false
    }
    sighting.reported = true
    sightings[value] = sighting
    lastEmit = now
    return true
  }
}
