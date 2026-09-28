import AVFoundation
import UIKit

/// The full-screen scanner: the camera, the scan window, and a bar with the
/// camera switch, the torch and the cancel button.
///
/// It reports and does not decide: the plugin dismisses it and answers Dart.
final class ScannerViewController: UIViewController {
  /// Called with each code worth reporting. A single scan calls it once.
  var onCode: ((String) -> Void)?
  /// Called when the user leaves without a code, or the scanner was taken
  /// off the screen by someone else.
  var onCancel: (() -> Void)?
  /// Called with an error code and a message when the camera cannot be used.
  var onError: ((String, String) -> Void)?

  private let options: ScanOptions
  private let camera: ScannerCamera
  private let gate: ReadGate
  private let previewLayer: AVCaptureVideoPreviewLayer
  private let overlay = ScannerOverlayView()
  private let bar = UIView()
  private let cancelButton = UIButton(type: .system)
  private let flashButton = UIButton(type: .custom)
  private let switchButton = UIButton(type: .custom)

  private var ready = false
  private var finished = false

  private static let barHeight: CGFloat = 72

  init(options: ScanOptions) {
    // Locals, not properties: nothing on self can be read before super.init.
    let camera = ScannerCamera(types: options.metadataTypes)
    self.options = options
    self.camera = camera
    gate = ReadGate(delay: options.delay)
    previewLayer = AVCaptureVideoPreviewLayer(session: camera.session)
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .fullScreen
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not used")
  }

  override var prefersStatusBarHidden: Bool {
    return true
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black

    previewLayer.videoGravity = .resizeAspectFill
    view.layer.addSublayer(previewLayer)

    overlay.lineColor = options.lineColor
    overlay.squareWindow = options.squareWindow
    overlay.isHidden = !options.hasWindow
    overlay.onWindowChange = { [weak self] _ in self?.updateRectOfInterest() }
    view.addSubview(overlay)

    setUpBar()

    camera.onCodes = { [weak self] codes in self?.handle(codes) }
    camera.onRunning = { [weak self] in self?.updateRectOfInterest() }
    camera.onInterrupted = { [weak self] in self?.refreshButtons() }
    camera.configure(position: options.position) { [weak self] ready in
      guard let self = self else { return }
      guard ready else {
        self.fail(ScanError.cameraUnavailable, "No camera could be opened.")
        return
      }
      self.ready = true
      self.refreshButtons()
      self.view.setNeedsLayout()
      if self.view.window != nil { self.camera.start() }
    }
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if ready && !finished { camera.start() }
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    if camera.torchIsOn { camera.setTorch(false) }
    camera.stop()
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    // Dismissed by something other than the plugin: Dart still has to hear
    // that the scan is over.
    if isBeingDismissed && !finished {
      finished = true
      onCancel?()
    }
  }

  override func viewWillTransition(
    to size: CGSize,
    with coordinator: UIViewControllerTransitionCoordinator
  ) {
    super.viewWillTransition(to: size, with: coordinator)
    // A half turn keeps the same bounds and so triggers no layout pass, but
    // the capture orientation still has to follow.
    coordinator.animate(alongsideTransition: nil) { [weak self] _ in
      self?.view.setNeedsLayout()
      self?.view.layoutIfNeeded()
      self?.applyOrientation()
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let bounds = view.bounds
    let barHeight = ScannerViewController.barHeight + view.safeAreaInsets.bottom

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    previewLayer.frame = bounds
    CATransaction.commit()
    applyOrientation()

    overlay.frame = bounds
    overlay.bottomInset = barHeight
    bar.frame = CGRect(x: 0, y: bounds.height - barHeight, width: bounds.width, height: barHeight)

    let row = ScannerViewController.barHeight
    let side = view.safeAreaInsets.left + 12
    let trailing = view.safeAreaInsets.right + 12
    switchButton.frame = CGRect(x: side, y: (row - 48) / 2, width: 48, height: 48)
    flashButton.frame = CGRect(x: (bounds.width - 48) / 2, y: (row - 48) / 2, width: 48, height: 48)
    let cancelWidth = min(160, max(88, cancelButton.intrinsicContentSize.width + 24))
    cancelButton.frame = CGRect(
      x: bounds.width - trailing - cancelWidth,
      y: (row - 48) / 2,
      width: cancelWidth,
      height: 48
    )
  }

  /// Turns the preview with the interface, then converts the window again.
  private func applyOrientation() {
    if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
      connection.videoOrientation = ScannerCamera.videoOrientation(for: view)
    }
    updateRectOfInterest()
  }

  private func setUpBar() {
    bar.backgroundColor = UIColor(white: 0, alpha: 0.85)
    view.addSubview(bar)

    cancelButton.setTitle(options.cancelLabel, for: .normal)
    cancelButton.setTitleColor(.white, for: .normal)
    cancelButton.titleLabel?.font = UIFont.systemFont(ofSize: 17)
    cancelButton.titleLabel?.lineBreakMode = .byTruncatingTail
    cancelButton.contentHorizontalAlignment = .right
    cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
    bar.addSubview(cancelButton)

    flashButton.setImage(ScannerIcons.torch(on: false), for: .normal)
    flashButton.accessibilityLabel = "Torch"
    flashButton.addTarget(self, action: #selector(flashTapped), for: .touchUpInside)
    flashButton.isHidden = true
    bar.addSubview(flashButton)

    switchButton.setImage(ScannerIcons.switchCamera, for: .normal)
    switchButton.accessibilityLabel = "Switch camera"
    switchButton.addTarget(self, action: #selector(switchTapped), for: .touchUpInside)
    switchButton.isHidden = true
    bar.addSubview(switchButton)
  }

  /// Shows the torch as the camera has it, which an interruption changes
  /// behind the app's back.
  private func refreshButtons() {
    let on = camera.torchIsOn
    flashButton.isHidden = !(options.showTorchButton && camera.hasTorch)
    flashButton.setImage(ScannerIcons.torch(on: on), for: .normal)
    // Read out as selected when on.
    flashButton.isSelected = on
    switchButton.isHidden = !camera.canSwitch
  }

  private func updateRectOfInterest() {
    // Without a window the output keeps its default: the whole frame.
    let window = overlay.scanWindow
    guard ready, options.hasWindow, window.width > 0, window.height > 0 else { return }
    camera.setRectOfInterest(previewLayer.metadataOutputRectConverted(fromLayerRect: window))
  }

  private func handle(_ codes: [String]) {
    guard !finished else { return }
    if options.continuous {
      // Every code of the frame goes through the gate, which follows each
      // one on its own.
      for code in codes where gate.accept(code) {
        onCode?(code)
      }
      return
    }
    guard let code = codes.first else { return }
    finished = true
    camera.stop()
    onCode?(code)
  }

  private func fail(_ code: String, _ message: String) {
    guard !finished else { return }
    finished = true
    onError?(code, message)
  }

  /// Called by the plugin when it closes the scanner, so that its own
  /// dismissal is not taken for someone else's.
  func markFinished() {
    finished = true
    camera.stop()
  }

  @objc private func cancelTapped() {
    guard !finished else { return }
    finished = true
    camera.stop()
    onCancel?()
  }

  @objc private func flashTapped() {
    camera.setTorch(!camera.torchIsOn)
    refreshButtons()
  }

  @objc private func switchTapped() {
    // Both, since a switch replaces the device the torch belongs to.
    switchButton.isEnabled = false
    flashButton.isEnabled = false
    camera.switchCamera { [weak self] _ in
      guard let self = self else { return }
      self.switchButton.isEnabled = true
      self.flashButton.isEnabled = true
      self.refreshButtons()
      self.updateRectOfInterest()
    }
  }
}
