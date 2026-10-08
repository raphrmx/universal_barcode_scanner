import AVFoundation
import Cocoa
import FlutterMacOS

/// Builds the embedded scanner views of `UniversalBarcodeScanner`.
final class EmbeddedScannerFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    return EmbeddedScannerView(
      viewId: viewId,
      arguments: args as? [String: Any] ?? [:],
      messenger: messenger
    )
  }

  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
    return FlutterStandardMessageCodec.sharedInstance()
  }
}

/// The scanner embedded in a Flutter widget: the camera, the scan window, and
/// a channel for pausing. Same contract as the iOS view.
///
/// Only codes inside the scan window are read. When the view is not
/// continuous, it pauses on the first code until `resumeScanning`. A Mac
/// camera has no torch, so `toggleFlash` always answers false.
final class EmbeddedScannerView: NSView {
  private let options: ScannerOptions
  private let camera: ScannerCamera
  private let gate: ReadGate
  private let channel: FlutterMethodChannel
  private let previewLayer: AVCaptureVideoPreviewLayer
  private let overlay: ScannerOverlay

  private var ready = false
  private var detecting = true

  init(viewId: Int64, arguments: [String: Any], messenger: FlutterBinaryMessenger) {
    // Locals, not properties: nothing on self can be read before super.init.
    let options = ScannerOptions(arguments: arguments)
    let camera = ScannerCamera(
      scanFormat: options.scanFormat,
      frameInterval: options.frameInterval
    )
    self.options = options
    self.camera = camera
    gate = ReadGate(delay: options.delay)
    previewLayer = AVCaptureVideoPreviewLayer(session: camera.session)
    overlay = ScannerOverlay(lineColor: options.lineColor, shown: options.hasWindow)
    channel = FlutterMethodChannel(
      name: "universal_barcode_scanner/view_\(viewId)",
      binaryMessenger: messenger
    )
    super.init(frame: .zero)

    wantsLayer = true
    if let layer = layer {
      layer.backgroundColor = NSColor.black.cgColor
      layer.masksToBounds = true
      previewLayer.videoGravity = .resizeAspectFill
      layer.addSublayer(previewLayer)
      overlay.install(in: layer)
    }

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      self.onMethodCall(call, result: result)
    }
    camera.onCodes = { [weak self] codes in self?.onCodes(codes) }
    camera.onFrame = { [weak self] frame in self?.onFrame(frame) }
    // For Flutter to fade the view in.
    camera.onFirstFrame = { [weak self] in
      self?.channel.invokeMethod("onCameraStarted", arguments: nil)
    }

    // On the next turn of the main loop: a refused permission answers at
    // once, before Flutter has even received this view, and an error sent
    // then would reach no listener.
    DispatchQueue.main.async { [weak self] in self?.requestCamera() }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not used")
  }

  deinit {
    camera.stop()
    channel.setMethodCallHandler(nil)
  }

  override func layout() {
    super.layout()
    layoutLayers()
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    layoutLayers()
  }

  private func requestCamera() {
    CameraAccess.request { [weak self] granted in
      guard let self = self else { return }
      guard granted else {
        self.reportError(
          "camera_permission_denied",
          "Camera access was denied. Grant it in System Settings, and check that the app "
            + "declares NSCameraUsageDescription."
        )
        return
      }
      self.camera.start { [weak self] ready in
        guard let self = self else { return }
        guard ready else {
          self.reportError("camera_unavailable", "No camera could be opened.")
          return
        }
        self.ready = true
        self.updateRegionOfInterest()
      }
    }
  }

  private func layoutLayers() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    previewLayer.frame = bounds
    CATransaction.commit()
    overlay.layout(
      bounds: bounds,
      area: bounds,
      requested: options.windowSize,
      square: options.squareWindow
    )
    // Also when only the view's size changed: the same window then covers
    // another part of the frame.
    updateRegionOfInterest()
  }

  private func updateRegionOfInterest() {
    guard ready else { return }
    camera.readInside(options.hasWindow ? overlay.window : nil, of: previewLayer)
  }

  private func onFrame(_ frame: LumaFrame) {
    guard detecting else { return }
    channel.invokeMethod("onFrame", arguments: frame.payload)
  }

  private func onCodes(_ codes: [ScannedCode]) {
    // Every code of the frame goes through the gate, which follows each one
    // on its own.
    for code in codes {
      guard detecting else { return }
      guard gate.accept(code.value) else { continue }
      if !options.isContinuousScan { setDetecting(false) }
      channel.invokeMethod("onBarcodeDetected", arguments: code.payload)
    }
  }

  /// Reading on or off, the scan line with it.
  private func setDetecting(_ on: Bool) {
    detecting = on
    camera.setReading(on)
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
      result(false)
    case "setZoom":
      // A Mac's camera does not zoom.
      result(1.0)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
