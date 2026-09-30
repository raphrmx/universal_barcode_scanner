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

  /// What says a code was refused, while it shows.
  private var rejection: NSView?

  /// Says a code was read but refused by the Dart side's validator:
  /// [message] near the bottom for two seconds, read out by VoiceOver.
  func showRejected(_ message: String) {
    guard !message.isEmpty, isViewLoaded else { return }
    rejection?.removeFromSuperview()

    let label = NSTextField(labelWithString: message)
    label.textColor = .white
    label.font = .systemFont(ofSize: 14, weight: .semibold)
    label.alignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false

    let pill = NSView()
    pill.wantsLayer = true
    pill.layer?.backgroundColor =
      NSColor(red: 0.706, green: 0.137, blue: 0.094, alpha: 0.9).cgColor
    pill.layer?.cornerRadius = 16
    pill.translatesAutoresizingMaskIntoConstraints = false
    pill.addSubview(label)
    view.addSubview(pill)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 16),
      label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -16),
      label.topAnchor.constraint(equalTo: pill.topAnchor, constant: 8),
      label.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -8),
      pill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      pill.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -48),
    ])
    rejection = pill
    NSAccessibility.post(
      element: pill, notification: .announcementRequested,
      userInfo: [
        .announcement: message,
        .priority: NSAccessibilityPriorityLevel.high.rawValue,
      ])
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak pill] in
      pill?.removeFromSuperview()
    }
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
