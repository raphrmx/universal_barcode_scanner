import AVFoundation
import Cocoa
import Vision

/// The scanner itself: a camera preview, a scan line, and a cancel button.
///
/// macOS has no equivalent of `AVCaptureMetadataOutput`'s barcode types, so
/// frames go through Vision's `VNDetectBarcodesRequest` instead. That is also
/// what Apple's own samples do on this platform.
class BarcodeScannerViewController: NSViewController {
  /// Called with every code read. In continuous mode it fires repeatedly.
  var onScanned: ((String) -> Void)?
  /// Called when the user closes the scanner without a result.
  var onCancelled: (() -> Void)?

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
  private var lastScanAt: Date = .distantPast
  private var hasResult = false

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
    configureSession()
    configurePreview()
    configureCancelButton()
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

  private func configureSession() {
    session.beginConfiguration()
    session.sessionPreset = .high

    if let device = AVCaptureDevice.default(for: .video),
      let input = try? AVCaptureDeviceInput(device: device),
      session.canAddInput(input)
    {
      session.addInput(input)
    }

    output.alwaysDiscardsLateVideoFrames = true
    output.setSampleBufferDelegate(self, queue: frameQueue)
    if session.canAddOutput(output) {
      session.addOutput(output)
    }

    session.commitConfiguration()

    // startRunning blocks; keeping it off the main thread stops the window
    // from opening frozen.
    sessionQueue.async { [weak self] in
      self?.session.startRunning()
    }
  }

  private func stop() {
    guard session.isRunning else { return }
    sessionQueue.async { [weak self] in
      self?.session.stopRunning()
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
        .i2of5, .i2of5Checksum, .itf14,
      ]
    default:
      return []
    }
  }

  private func handle(_ barcode: String) {
    guard !barcode.isEmpty else { return }

    if options.isContinuousScan {
      // delayMillis throttles the stream, otherwise a code sitting in front of
      // the camera is read on every single frame.
      guard Date().timeIntervalSince(lastScanAt) >= options.delay else { return }
      lastScanAt = Date()
      DispatchQueue.main.async { [weak self] in self?.onScanned?(barcode) }
      return
    }

    guard !hasResult else { return }
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

    let request = VNDetectBarcodesRequest { [weak self] request, _ in
      guard let self = self,
        let results = request.results as? [VNBarcodeObservation]
      else { return }

      for observation in results {
        if let payload = observation.payloadStringValue {
          self.handle(payload)
          return
        }
      }
    }

    let wanted = symbologies
    if !wanted.isEmpty {
      request.symbologies = wanted
    }

    let handler = VNImageRequestHandler(cvPixelBuffer: buffer, options: [:])
    try? handler.perform([request])
  }
}
