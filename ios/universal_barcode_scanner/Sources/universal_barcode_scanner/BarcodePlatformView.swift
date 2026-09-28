import AVFoundation
import Flutter
import UIKit

/// Builds the embedded scanner views of `UniversalBarcodeScanner`.
final class BarcodeViewFactory: NSObject, FlutterPlatformViewFactory {
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
    return BarcodePlatformView(
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
final class BarcodePlatformView: NSObject, FlutterPlatformView {
  private let container: LayoutReportingView
  private let options: ScanOptions
  private let camera: ScannerCamera
  private let gate: ReadGate
  private let channel: FlutterMethodChannel
  private let previewLayer: AVCaptureVideoPreviewLayer
  private let overlay = ScannerOverlayView()

  private var ready = false
  private var detecting = true
  private var torchOn = false

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

    camera.onCode = { [weak self] code in self?.onCode(code) }
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

  deinit {
    camera.stop()
    channel.setMethodCallHandler(nil)
  }

  func view() -> UIView {
    return container
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
    let window = overlay.scanWindow
    guard ready, window.width > 0, window.height > 0 else { return }
    camera.setRectOfInterest(previewLayer.metadataOutputRectConverted(fromLayerRect: window))
  }

  private func onCode(_ code: String) {
    guard detecting, gate.accept(code) else { return }
    if !options.continuous { detecting = false }
    channel.invokeMethod("onBarcodeDetected", arguments: code)
  }

  private func reportError(_ code: String, _ message: String) {
    channel.invokeMethod("onError", arguments: ["code": code, "message": message])
  }

  private func onMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pauseScanning":
      detecting = false
      result(nil)
    case "resumeScanning":
      // The code that paused a single-shot view counts as new again.
      gate.reset()
      detecting = true
      result(nil)
    case "toggleFlash":
      torchOn = camera.setTorch(!torchOn)
      result(torchOn)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
