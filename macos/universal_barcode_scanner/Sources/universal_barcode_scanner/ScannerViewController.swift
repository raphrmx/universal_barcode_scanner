import AVFoundation
import Cocoa

/// The scanner window's content: a camera preview, a scan window with its
/// sweeping line, and a cancel button that Escape also presses.
class ScannerViewController: NSViewController {
  /// Called on the main thread with each code worth reporting.
  var onScanned: ((ScannedCode) -> Void)?
  /// Called when the user closes the scanner without a result.
  var onCancelled: (() -> Void)?
  /// Called with an error code and a message when the camera cannot be used.
  var onFailed: ((String, String) -> Void)?

  private let options: ScannerOptions
  private let camera: ScannerCamera
  private let gate: ReadGate
  private let overlay: ScannerOverlay
  private var previewLayer: AVCaptureVideoPreviewLayer?
  private var ready = false
  private var hasResult = false

  init(options: ScannerOptions) {
    self.options = options
    camera = ScannerCamera(scanFormat: options.scanFormat)
    gate = ReadGate(delay: options.delay)
    overlay = ScannerOverlay(lineColor: options.lineColor, shown: options.hasWindow)
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

    camera.onCodes = { [weak self] codes in self?.handle(codes) }
    camera.start { [weak self] ready in
      guard let self = self else { return }
      if ready {
        self.ready = true
        self.updateRegionOfInterest()
      } else {
        self.onFailed?("camera_unavailable", "The camera could not be opened.")
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

  func stop() {
    camera.stop()
  }

  // MARK: - Chrome

  private func configureLayers() {
    let preview = AVCaptureVideoPreviewLayer(session: camera.session)
    preview.videoGravity = .resizeAspectFill
    view.layer?.addSublayer(preview)
    previewLayer = preview
    if let layer = view.layer {
      overlay.install(in: layer)
    }
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

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    previewLayer?.frame = bounds
    CATransaction.commit()

    if overlay.layout(
      bounds: bounds, area: area, requested: options.windowSize, square: options.squareWindow)
    {
      updateRegionOfInterest()
    }
  }

  private func updateRegionOfInterest() {
    guard ready, let preview = previewLayer else { return }
    camera.readInside(options.hasWindow ? overlay.window : nil, of: preview)
  }

  private func configureCancelButton() {
    let button = NSButton(
      title: options.cancelLabel,
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

  /// Runs on the main thread with the codes of one frame.
  private func handle(_ codes: [ScannedCode]) {
    guard !hasResult, let first = codes.first else { return }

    if options.isContinuousScan {
      // Every code of the frame goes through the gate, which follows each
      // one on its own.
      for code in codes where gate.accept(code.value) {
        onScanned?(code)
      }
      return
    }

    hasResult = true
    stop()
    onScanned?(first)
  }
}
