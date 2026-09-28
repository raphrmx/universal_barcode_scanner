import AVFoundation
import UIKit

/// Where the flash and camera icons live.
///
/// Swift Package Manager puts a target's resources in `Bundle.module`, while
/// CocoaPods leaves them alongside the class. Asking for the bundle instead of
/// naming one keeps both builds working.
var resourceBundle: Bundle {
  #if SWIFT_PACKAGE
    return Bundle.module
  #else
    return Bundle(for: BarcodeScannerViewController.self)
  #endif
}

/// The full-screen scanner: the camera, the scan window, and a bar with the
/// camera switch, the torch and the cancel button.
///
/// It reports and does not decide: the plugin dismisses it and answers Dart.
final class BarcodeScannerViewController: UIViewController {
  /// Called with each code worth reporting. A single scan calls it once.
  var onCode: ((String) -> Void)?
  /// Called when the user leaves without a code.
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
  private var torchOn = false

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
    overlay.onWindowChange = { [weak self] _ in self?.updateRectOfInterest() }
    view.addSubview(overlay)

    setUpBar()

    camera.onCode = { [weak self] code in self?.handle(code) }
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
      self.updateRectOfInterest()
    }
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if ready && !finished { camera.start() }
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    if torchOn { torchOn = camera.setTorch(false) }
    camera.stop()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let bounds = view.bounds
    let barHeight = BarcodeScannerViewController.barHeight + view.safeAreaInsets.bottom

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    previewLayer.frame = bounds
    if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
      connection.videoOrientation = ScannerCamera.videoOrientation(for: view)
    }
    CATransaction.commit()

    overlay.frame = bounds
    overlay.bottomInset = barHeight
    bar.frame = CGRect(x: 0, y: bounds.height - barHeight, width: bounds.width, height: barHeight)

    let row = BarcodeScannerViewController.barHeight
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

    // The preview's geometry changed with the rotation: the window has to be
    // converted again even where it kept its place on screen.
    updateRectOfInterest()
  }

  private func setUpBar() {
    bar.backgroundColor = UIColor(white: 0, alpha: 0.85)
    view.addSubview(bar)

    cancelButton.setTitle(options.cancelButtonText, for: .normal)
    cancelButton.setTitleColor(.white, for: .normal)
    cancelButton.titleLabel?.font = UIFont.systemFont(ofSize: 17)
    cancelButton.contentHorizontalAlignment = .right
    cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
    bar.addSubview(cancelButton)

    flashButton.setImage(icon("ic_flash_off"), for: .normal)
    flashButton.accessibilityLabel = "Torch"
    flashButton.addTarget(self, action: #selector(flashTapped), for: .touchUpInside)
    flashButton.isHidden = true
    bar.addSubview(flashButton)

    switchButton.setImage(icon("ic_switch_camera"), for: .normal)
    switchButton.accessibilityLabel = "Switch camera"
    switchButton.addTarget(self, action: #selector(switchTapped), for: .touchUpInside)
    switchButton.isHidden = true
    bar.addSubview(switchButton)
  }

  private func icon(_ name: String) -> UIImage? {
    return UIImage(named: name, in: resourceBundle, compatibleWith: nil)
  }

  private func refreshButtons() {
    flashButton.isHidden = !(options.showFlashIcon && camera.hasTorch)
    flashButton.setImage(icon(torchOn ? "ic_flash_on" : "ic_flash_off"), for: .normal)
    switchButton.isHidden = !camera.canSwitch
  }

  private func updateRectOfInterest() {
    let window = overlay.scanWindow
    guard ready, window.width > 0, window.height > 0 else { return }
    camera.setRectOfInterest(previewLayer.metadataOutputRectConverted(fromLayerRect: window))
  }

  private func handle(_ code: String) {
    guard !finished else { return }
    if options.continuous {
      if gate.accept(code) { onCode?(code) }
      return
    }
    finished = true
    camera.stop()
    onCode?(code)
  }

  private func fail(_ code: String, _ message: String) {
    guard !finished else { return }
    finished = true
    onError?(code, message)
  }

  @objc private func cancelTapped() {
    guard !finished else { return }
    finished = true
    camera.stop()
    onCancel?()
  }

  @objc private func flashTapped() {
    torchOn = camera.setTorch(!torchOn)
    refreshButtons()
  }

  @objc private func switchTapped() {
    switchButton.isEnabled = false
    camera.switchCamera { [weak self] _ in
      guard let self = self else { return }
      self.switchButton.isEnabled = true
      self.torchOn = false
      self.refreshButtons()
      self.updateRectOfInterest()
    }
  }
}
