import AVFoundation
import Flutter
import UIKit

/// Builds the embedded scanner views of `UniversalBarcodeScanner`.
final class EmbeddedScannerFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    return EmbeddedScannerView(
      frame: frame,
      viewId: viewId,
      arguments: args as? [String: Any] ?? [:],
      messenger: messenger
    )
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }
}

/// A view that says when its layout changes.
private final class LayoutReportingView: UIView {
  var onLayout: (() -> Void)?

  override func layoutSubviews() {
    super.layoutSubviews()
    onLayout?()
  }
}

/// The scanner embedded in a Flutter widget: the camera, the scan window, and
/// a channel for the torch and for pausing.
///
/// Only codes inside the scan window are read. When the view is not
/// continuous, it pauses on the first code until `resumeScanning`.
final class EmbeddedScannerView: NSObject, FlutterPlatformView {
  private let container: LayoutReportingView
  private let options: ScanOptions
  private let camera: ScannerCamera
  private let gate: ReadGate
  private let channel: FlutterMethodChannel

  /// Whether Flutter has been told the camera shows frames.
  private var announcedStart = false
  private let previewLayer: AVCaptureVideoPreviewLayer
  private let overlay = ScannerOverlayView()

  private var ready = false
  private var detecting = true
  private var orientationObserver: NSObjectProtocol?

  init(
    frame: CGRect,
    viewId: Int64,
    arguments: [String: Any],
    messenger: FlutterBinaryMessenger
  ) {
    // Locals, not properties: nothing on self can be read before super.init.
    let options = ScanOptions(arguments: arguments)
    let camera = ScannerCamera(types: options.metadataTypes)
    self.options = options
    self.camera = camera
    gate = ReadGate(delay: options.delay)
    previewLayer = AVCaptureVideoPreviewLayer(session: camera.session)
    container = LayoutReportingView(frame: frame)
    channel = FlutterMethodChannel(
      name: "universal_barcode_scanner/view_\(viewId)",
      binaryMessenger: messenger
    )
    super.init()

    container.backgroundColor = .black
    container.clipsToBounds = true
    previewLayer.videoGravity = .resizeAspectFill
    container.layer.addSublayer(previewLayer)

    overlay.lineColor = options.lineColor
    overlay.squareWindow = options.squareWindow
    overlay.isHidden = !options.hasWindow
    overlay.windowSize = options.windowSize
    overlay.onWindowChange = { [weak self] _ in self?.updateRectOfInterest() }
    container.addSubview(overlay)
    container.onLayout = { [weak self] in self?.layout() }

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      self.onMethodCall(call, result: result)
    }

    camera.onCodes = { [weak self] codes in self?.onCodes(codes) }
    camera.onRunning = { [weak self] in
      guard let self = self else { return }
      self.updateRectOfInterest()
      // Running, or the first frame's format known: the preview shows
      // frames. Said once, for Flutter to fade the view in.
      if !self.announcedStart {
        self.announcedStart = true
        self.channel.invokeMethod("onCameraStarted", arguments: nil)
      }
    }

    // A half turn keeps the same bounds and so triggers no layout pass, but
    // the capture orientation still has to follow.
    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    orientationObserver = NotificationCenter.default.addObserver(
      forName: UIDevice.orientationDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      // After the interface has turned, which follows the device.
      DispatchQueue.main.async { self?.layout() }
    }

    // On the next turn of the main loop: a refused or restricted permission
    // answers at once, before Flutter has even received this view, and an
    // error sent then would reach no listener.
    DispatchQueue.main.async { [weak self] in self?.requestCamera() }
  }

  deinit {
    if let observer = orientationObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    UIDevice.current.endGeneratingDeviceOrientationNotifications()
    camera.stop()
    channel.setMethodCallHandler(nil)
  }

  func view() -> UIView {
    return container
  }

  private func requestCamera() {
    CameraAccess.request { [weak self] granted in
      guard let self = self else { return }
      guard granted else {
        self.reportError(ScanError.permissionDenied, "Camera access was denied.")
        return
      }
      self.camera.configure(position: self.options.position) { [weak self] ready in
        guard let self = self else { return }
        guard ready else {
          self.reportError(ScanError.cameraUnavailable, "No camera could be opened.")
          return
        }
        self.ready = true
        self.camera.start()
        self.layout()
      }
    }
  }

  private func layout() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    previewLayer.frame = container.bounds
    if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
      connection.videoOrientation = ScannerCamera.videoOrientation(for: container)
    }
    CATransaction.commit()
    overlay.frame = container.bounds
    updateRectOfInterest()
  }

  private func updateRectOfInterest() {
    // Without a window the output keeps its default: the whole frame.
    let window = overlay.scanWindow
    guard ready, options.hasWindow, window.width > 0, window.height > 0 else { return }
    camera.setRectOfInterest(previewLayer.metadataOutputRectConverted(fromLayerRect: window))
  }

  private func onCodes(_ codes: [ScannedCode]) {
    // Every code of the frame goes through the gate, which follows each one
    // on its own.
    for code in codes {
      guard detecting else { return }
      guard gate.accept(code.value) else { continue }
      if !options.continuous { setDetecting(false) }
      channel.invokeMethod("onBarcodeDetected", arguments: code.payload)
    }
  }

  /// Reading on or off, the scan line with it.
  private func setDetecting(_ on: Bool) {
    detecting = on
    overlay.paused = !on
  }

  private func reportError(_ code: String, _ message: String) {
    channel.invokeMethod("onError", arguments: ["code": code, "message": message])
  }

  private func onMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pauseScanning":
      setDetecting(false)
      result(nil)
    case "resumeScanning":
      // The code that paused a single-shot view counts as new again.
      gate.reset()
      setDetecting(true)
      result(nil)
    case "toggleFlash":
      // From the camera's own state, which an interruption changes behind
      // the app's back.
      result(camera.setTorch(!camera.torchIsOn))
    case "setZoom":
      let wanted = (call.arguments as? NSNumber)?.doubleValue ?? 1
      result(camera.setZoom(CGFloat(wanted)))
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
