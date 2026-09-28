import AVFoundation
import Cocoa
import Vision

/// The scanner itself: a camera preview, a scan line, and a cancel button.
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
  private var lineLayer: CALayer?

  // Touched on the frame queue only.
  private var hasResult = false
  private var lastValue: String?
  private var lastSeen: TimeInterval = 0
  private var lastEmit: TimeInterval?

  /// Built once: a request per frame was an allocation per frame.
  private lazy var request: VNDetectBarcodesRequest = {
    let request = VNDetectBarcodesRequest()
    let wanted = self.symbologies
    if !wanted.isEmpty {
      request.symbologies = wanted
    }
    return request
  }()

  /// A code held in front of the camera is reported once, and again only
  /// after it has been out of sight this long.
  private static let sameCodeGap: TimeInterval = 1.0

  init(options: ScannerOptions) {
    self.options = options
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
    configurePreview()
    configureCancelButton()
    if !configureSession() {
      DispatchQueue.main.async { [weak self] in
        self?.onFailed?("camera_unavailable", "The camera could not be opened.")
      }
    }
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    previewLayer?.frame = view.bounds
    lineLayer?.frame = CGRect(
      x: view.bounds.width * 0.1,
      y: view.bounds.midY,
      width: view.bounds.width * 0.8,
      height: 2
    )
  }

  override func viewWillDisappear() {
    super.viewWillDisappear()
    stop()
  }

  // MARK: - Capture

  private func configureSession() -> Bool {
    session.beginConfiguration()
    // Vision works on every frame it is given; 720p reads a code as well as
    // full HD, for less than half the pixels.
    session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .high

    guard let device = AVCaptureDevice.default(for: .video),
      let input = try? AVCaptureDeviceInput(device: device),
      session.canAddInput(input)
    else {
      session.commitConfiguration()
      return false
    }
    session.addInput(input)

    output.alwaysDiscardsLateVideoFrames = true
    output.setSampleBufferDelegate(self, queue: frameQueue)
    if session.canAddOutput(output) {
      session.addOutput(output)
    }

    session.commitConfiguration()

    // startRunning blocks; keeping it off the main thread stops the window
    // from opening frozen.
    let capture = session
    sessionQueue.async {
      capture.startRunning()
    }
    return true
  }

  func stop() {
    let session = self.session
    sessionQueue.async {
      if session.isRunning { session.stopRunning() }
    }
  }

  // MARK: - Chrome

  private func configurePreview() {
    let layer = AVCaptureVideoPreviewLayer(session: session)
    layer.videoGravity = .resizeAspectFill
    layer.frame = view.bounds
    view.layer?.addSublayer(layer)
    previewLayer = layer

    let line = CALayer()
    line.backgroundColor = options.lineColor.cgColor
    view.layer?.addSublayer(line)
    lineLayer = line
  }

  private func configureCancelButton() {
    let button = NSButton(
      title: options.cancelButtonText,
      target: self,
      action: #selector(cancelClicked)
    )
    button.bezelStyle = .rounded
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

  /// Runs on the frame queue.
  private func handle(_ barcode: String) {
    guard !barcode.isEmpty, !hasResult else { return }

    if options.isContinuousScan {
      let now = CACurrentMediaTime()
      if barcode == lastValue {
        let held = now - lastSeen < Self.sameCodeGap
        lastSeen = now
        if held { return }
      }
      if let last = lastEmit, now - last < options.delay { return }
      lastValue = barcode
      lastSeen = now
      lastEmit = now
      DispatchQueue.main.async { [weak self] in self?.onScanned?(barcode) }
      return
    }

    hasResult = true
    stop()
    DispatchQueue.main.async { [weak self] in self?.onScanned?(barcode) }
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

    let handler = VNImageRequestHandler(cvPixelBuffer: buffer, options: [:])
    guard (try? handler.perform([request])) != nil,
      let results = request.results as? [VNBarcodeObservation]
    else { return }

    for observation in results {
      if let payload = observation.payloadStringValue {
        handle(payload)
        return
      }
    }
  }
}
