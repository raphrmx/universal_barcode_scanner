import AVFoundation
import UIKit

/// A capture session reading machine-readable codes, shared by the full-screen
/// scanner and the embedded view.
///
/// Everything that touches the session runs on its own queue: `startRunning`
/// blocks for a few hundred milliseconds, and on the main thread it froze the
/// screen as the scanner opened. The device input lives on that queue too; the
/// main thread only sees `device`, a copy published once the queue is done
/// with it.
final class ScannerCamera {
  let session = AVCaptureSession()

  /// Called on the main thread with the codes of a frame, in no set order.
  var onCodes: (([String]) -> Void)?
  /// Called on the main thread once the camera runs, and whenever its format
  /// changes: the moments a rectangle of interest can be converted.
  var onRunning: (() -> Void)?
  /// Called on the main thread when the session was interrupted, which turns
  /// the torch off behind the app's back.
  var onInterrupted: (() -> Void)?

  /// The camera in use. Main thread only.
  private(set) var device: AVCaptureDevice?

  private let output = AVCaptureMetadataOutput()
  private let queue = DispatchQueue(label: "be.comapps.universal_barcode_scanner.session")
  private let types: [AVMetadataObject.ObjectType]
  /// Session queue only.
  private var input: AVCaptureDeviceInput?
  private var delegate: MetadataDelegate?
  private var observers: [NSObjectProtocol] = []

  init(types: [AVMetadataObject.ObjectType]) {
    self.types = types
    observe()
  }

  deinit {
    observers.forEach { NotificationCenter.default.removeObserver($0) }
    stop()
  }

  private func observe() {
    let center = NotificationCenter.default
    observers = [
      // Media services were reset, or the session failed: it does not
      // restart by itself.
      center.addObserver(
        forName: .AVCaptureSessionRuntimeError,
        object: session,
        queue: .main
      ) { [weak self] _ in
        self?.start()
      },
      center.addObserver(
        forName: .AVCaptureSessionWasInterrupted,
        object: session,
        queue: .main
      ) { [weak self] _ in
        self?.onInterrupted?()
      },
      center.addObserver(
        forName: .AVCaptureInputPortFormatDescriptionDidChange,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.onRunning?()
      },
    ]
  }

  /// Adds the camera at `position`, or the other one when it is missing.
  /// Completes on the main thread with whether a camera could be used.
  func configure(position: AVCaptureDevice.Position, completion: @escaping (Bool) -> Void) {
    queue.async { [weak self] in
      let device = self?.setUp(position: position)
      DispatchQueue.main.async {
        self?.device = device
        completion(device != nil)
      }
    }
  }

  private func setUp(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
    let other: AVCaptureDevice.Position = position == .front ? .back : .front
    guard
      let device = ScannerCamera.device(at: position)
        ?? ScannerCamera.device(at: other)
        ?? AVCaptureDevice.default(for: .video),
      let input = try? AVCaptureDeviceInput(device: device)
    else { return nil }

    session.beginConfiguration()
    guard session.canAddInput(input), session.canAddOutput(output) else {
      session.commitConfiguration()
      return nil
    }
    session.addInput(input)
    session.addOutput(output)
    if #available(iOS 16.0, *), session.isMultitaskingCameraAccessSupported {
      // Keeps scanning in Split View, Slide Over and Stage Manager, where
      // the session would otherwise be interrupted.
      session.isMultitaskingCameraAccessEnabled = true
    }
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
    return device
  }

  func start() {
    queue.async { [weak self] in
      guard let self = self, self.input != nil else { return }
      if !self.session.isRunning { self.session.startRunning() }
      DispatchQueue.main.async { [weak self] in self?.onRunning?() }
    }
  }

  func stop() {
    let capture = session
    queue.async {
      if capture.isRunning { capture.stopRunning() }
    }
  }

  /// Restricts reading to a rectangle, in the output's normalised space.
  func setRectOfInterest(_ rect: CGRect) {
    guard rect.width > 0, rect.height > 0 else { return }
    let metadata = output
    queue.async { metadata.rectOfInterest = rect }
  }

  var hasTorch: Bool {
    return device?.hasTorch ?? false
  }

  /// Whether the torch is on, as the camera itself reports it.
  var torchIsOn: Bool {
    return device?.torchMode == .on
  }

  /// Whether there is a camera on each side to switch between.
  var canSwitch: Bool {
    return ScannerCamera.device(at: .front) != nil && ScannerCamera.device(at: .back) != nil
  }

  /// Turns the torch on or off, and returns whether it is now on.
  @discardableResult
  func setTorch(_ on: Bool) -> Bool {
    guard let device = device, device.hasTorch else { return false }
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
      guard let wanted = ScannerCamera.device(at: target),
        let next = try? AVCaptureDeviceInput(device: wanted)
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
      let inUse = self.input?.device
      DispatchQueue.main.async { [weak self] in
        self?.device = inUse
        completion(inUse === wanted)
      }
    }
  }

  fileprivate func deliver(_ codes: [String]) {
    onCodes?(codes)
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
    // Every code of the frame: the gate follows each one on its own.
    let codes = metadataObjects.compactMap { object -> String? in
      guard let code = (object as? AVMetadataMachineReadableCodeObject)?.stringValue,
        !code.isEmpty
      else { return nil }
      return code
    }
    if !codes.isEmpty { camera?.deliver(codes) }
  }
}
