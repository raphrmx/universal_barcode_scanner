import AVFoundation
import UIKit

/// A capture session reading machine-readable codes, shared by the full-screen
/// scanner and the embedded view.
///
/// Everything that touches the session runs on its own queue: `startRunning`
/// blocks for a few hundred milliseconds, and on the main thread it froze the
/// screen as the scanner opened.
final class ScannerCamera {
  let session = AVCaptureSession()

  /// Called on the main thread with every code read.
  var onCode: ((String) -> Void)?

  private let output = AVCaptureMetadataOutput()
  private let queue = DispatchQueue(label: "be.comapps.universal_barcode_scanner.session")
  private let types: [AVMetadataObject.ObjectType]
  private var input: AVCaptureDeviceInput?
  private var delegate: MetadataDelegate?

  init(types: [AVMetadataObject.ObjectType]) {
    self.types = types
  }

  deinit {
    stop()
  }

  /// Adds the camera at `position`, or the other one when it is missing.
  /// Completes on the main thread with whether a camera could be used.
  func configure(position: AVCaptureDevice.Position, completion: @escaping (Bool) -> Void) {
    queue.async { [weak self] in
      let ready = self?.setUp(position: position) ?? false
      DispatchQueue.main.async { completion(ready) }
    }
  }

  private func setUp(position: AVCaptureDevice.Position) -> Bool {
    let other: AVCaptureDevice.Position = position == .front ? .back : .front
    guard
      let device = ScannerCamera.device(at: position)
        ?? ScannerCamera.device(at: other)
        ?? AVCaptureDevice.default(for: .video),
      let input = try? AVCaptureDeviceInput(device: device)
    else { return false }

    session.beginConfiguration()
    guard session.canAddInput(input), session.canAddOutput(output) else {
      session.commitConfiguration()
      return false
    }
    session.addInput(input)
    session.addOutput(output)
    session.commitConfiguration()
    self.input = input

    // Held weakly by the proxy, so the output never keeps this object alive.
    let delegate = MetadataDelegate(camera: self)
    self.delegate = delegate
    output.setMetadataObjectsDelegate(delegate, queue: .main)
    // Asking for a type the output does not offer raises an exception, as on
    // a simulator; only the available ones are set.
    let available = output.availableMetadataObjectTypes
    output.metadataObjectTypes = types.filter { available.contains($0) }
    return true
  }

  func start() {
    let session = self.session
    let configured = input != nil
    queue.async {
      if configured && !session.isRunning { session.startRunning() }
    }
  }

  func stop() {
    let session = self.session
    queue.async {
      if session.isRunning { session.stopRunning() }
    }
  }

  /// Restricts reading to a rectangle, in the output's normalised space.
  func setRectOfInterest(_ rect: CGRect) {
    guard rect.width > 0, rect.height > 0 else { return }
    let output = self.output
    queue.async { output.rectOfInterest = rect }
  }

  var hasTorch: Bool {
    return input?.device.hasTorch ?? false
  }

  /// Whether there is a camera on each side to switch between.
  var canSwitch: Bool {
    return ScannerCamera.device(at: .front) != nil && ScannerCamera.device(at: .back) != nil
  }

  /// Turns the torch on or off, and returns whether it is now on.
  @discardableResult
  func setTorch(_ on: Bool) -> Bool {
    guard let device = input?.device, device.hasTorch else { return false }
    do {
      try device.lockForConfiguration()
      defer { device.unlockForConfiguration() }
      if on {
        try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
      } else {
        device.torchMode = .off
      }
      return on
    } catch {
      return false
    }
  }

  /// Swaps the front and back cameras. Completes on the main thread.
  func switchCamera(completion: @escaping (Bool) -> Void) {
    queue.async { [weak self] in
      guard let self = self, let current = self.input else {
        DispatchQueue.main.async { completion(false) }
        return
      }
      let target: AVCaptureDevice.Position = current.device.position == .front ? .back : .front
      guard let device = ScannerCamera.device(at: target),
        let next = try? AVCaptureDeviceInput(device: device)
      else {
        DispatchQueue.main.async { completion(false) }
        return
      }
      self.session.beginConfiguration()
      self.session.removeInput(current)
      if self.session.canAddInput(next) {
        self.session.addInput(next)
        self.input = next
      } else {
        self.session.addInput(current)
      }
      self.session.commitConfiguration()
      let switched = self.input === next
      DispatchQueue.main.async { completion(switched) }
    }
  }

  fileprivate func deliver(_ code: String) {
    onCode?(code)
  }

  static func device(at position: AVCaptureDevice.Position) -> AVCaptureDevice? {
    return AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInWideAngleCamera],
      mediaType: .video,
      position: position
    ).devices.first
  }

  /// The capture orientation matching the interface around `view`.
  static func videoOrientation(for view: UIView) -> AVCaptureVideoOrientation {
    let interface: UIInterfaceOrientation
    if #available(iOS 13.0, *) {
      interface = view.window?.windowScene?.interfaceOrientation ?? .portrait
    } else {
      interface = UIApplication.shared.statusBarOrientation
    }
    switch interface {
    case .landscapeLeft:
      return .landscapeLeft
    case .landscapeRight:
      return .landscapeRight
    case .portraitUpsideDown:
      return .portraitUpsideDown
    default:
      return .portrait
    }
  }
}

/// Forwards detections to the camera without retaining it.
private final class MetadataDelegate: NSObject, AVCaptureMetadataOutputObjectsDelegate {
  private weak var camera: ScannerCamera?

  init(camera: ScannerCamera) {
    self.camera = camera
  }

  func metadataOutput(
    _ output: AVCaptureMetadataOutput,
    didOutput metadataObjects: [AVMetadataObject],
    from connection: AVCaptureConnection
  ) {
    for object in metadataObjects {
      if let code = (object as? AVMetadataMachineReadableCodeObject)?.stringValue,
        !code.isEmpty
      {
        camera?.deliver(code)
        return
      }
    }
  }
}

/// The dimmed surround, the window's outline, and the line sweeping it.
final class ScannerOverlayView: UIView {
  var lineColor: UIColor = .red {
    didSet { line.backgroundColor = lineColor.cgColor }
  }
  var squareWindow = true {
    didSet { setNeedsLayout() }
  }
  /// A window of this size, in points, instead of one picked from the shape.
  var windowSize: CGSize? {
    didSet { setNeedsLayout() }
  }
  /// Height kept clear at the bottom, for controls drawn over the camera.
  var bottomInset: CGFloat = 0 {
    didSet { setNeedsLayout() }
  }
  /// Called whenever the window moves or changes size.
  var onWindowChange: ((CGRect) -> Void)?

  private(set) var scanWindow: CGRect = .zero

  private let dim = CAShapeLayer()
  private let outline = CAShapeLayer()
  private let line = CALayer()

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    backgroundColor = .clear

    dim.fillRule = .evenOdd
    dim.fillColor = UIColor(white: 0, alpha: 0.5).cgColor
    outline.fillColor = nil
    outline.strokeColor = UIColor(white: 1, alpha: 0.8).cgColor
    outline.lineWidth = 2
    line.backgroundColor = lineColor.cgColor

    layer.addSublayer(dim)
    layer.addSublayer(outline)
    layer.addSublayer(line)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not used")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let area = CGRect(
      x: 0,
      y: 0,
      width: bounds.width,
      height: max(0, bounds.height - bottomInset)
    )
    let window = ScanOptions.window(in: area, requested: windowSize, square: squareWindow)

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    dim.frame = bounds
    let path = UIBezierPath(rect: bounds)
    path.append(UIBezierPath(rect: window))
    dim.path = path.cgPath
    outline.frame = bounds
    outline.path = UIBezierPath(rect: window).cgPath
    line.frame = CGRect(x: window.minX, y: window.minY, width: window.width, height: 2)
    CATransaction.commit()

    if window != scanWindow {
      scanWindow = window
      sweep()
      onWindowChange?(window)
    }
  }

  private func sweep() {
    line.removeAllAnimations()
    guard scanWindow.height > 4 else { return }
    if UIAccessibility.isReduceMotionEnabled {
      line.position = CGPoint(x: scanWindow.midX, y: scanWindow.midY)
      return
    }
    let animation = CABasicAnimation(keyPath: "position.y")
    animation.fromValue = scanWindow.minY + 1
    animation.toValue = scanWindow.maxY - 1
    animation.duration = 1.5
    animation.autoreverses = true
    animation.repeatCount = .infinity
    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    // Kept across a trip to the background, which otherwise removes it.
    animation.isRemovedOnCompletion = false
    line.add(animation, forKey: "sweep")
  }
}
