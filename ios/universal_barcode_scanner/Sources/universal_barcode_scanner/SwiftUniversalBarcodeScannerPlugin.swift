import AVFoundation
import Flutter
import UIKit

/// Entry point on iOS.
///
/// `scanBarcode` presents the scanner over whatever is on screen. A single
/// scan answers with the code, or nil when cancelled; a continuous one answers
/// once the scanner is up and sends its codes on the event channel, then
/// `{"event": "closed"}`. `close` dismisses whichever scanner is open.
public class SwiftUniversalBarcodeScannerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var pendingResult: FlutterResult?
  private var eventSink: FlutterEventSink?
  private var scanner: BarcodeScannerViewController?
  private var continuous = false

  public static func register(with registrar: FlutterPluginRegistrar) {
    // Nothing here reads a window or a view controller: under the scene life
    // cycle the app delegate has no window yet when plugins register.
    let instance = SwiftUniversalBarcodeScannerPlugin()

    let channel = FlutterMethodChannel(
      name: "universal_barcode_scanner",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: channel)

    let events = FlutterEventChannel(
      name: "universal_barcode_scanner/events",
      binaryMessenger: registrar.messenger()
    )
    events.setStreamHandler(instance)

    registrar.register(
      BarcodeViewFactory(messenger: registrar.messenger()),
      withId: "universal_barcode_scanner/view"
    )
  }

  // MARK: - FlutterStreamHandler

  public func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  // MARK: - FlutterPlugin

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "scanBarcode":
      scan(arguments: call.arguments as? [String: Any] ?? [:], result: result)
    case "close":
      finish(code: nil, error: nil)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func scan(arguments: [String: Any], result: @escaping FlutterResult) {
    guard scanner == nil, pendingResult == nil else {
      result(Self.error(ScanError.alreadyActive, "A scanner is already open."))
      return
    }
    let options = ScanOptions(arguments: arguments)

    CameraAccess.request { [weak self] granted in
      guard let self = self else { return }
      guard granted else {
        result(
          Self.error(
            ScanError.permissionDenied,
            "Camera access was denied. Grant it in Settings, and check that the "
              + "app declares NSCameraUsageDescription."
          )
        )
        return
      }
      guard AVCaptureDevice.default(for: .video) != nil else {
        result(Self.error(ScanError.cameraUnavailable, "No camera is available on this device."))
        return
      }
      guard let host = Self.topViewController() else {
        result(Self.error(ScanError.cameraUnavailable, "No view controller to present from."))
        return
      }
      // The permission prompt may have let another call in.
      guard self.scanner == nil, self.pendingResult == nil else {
        result(Self.error(ScanError.alreadyActive, "A scanner is already open."))
        return
      }
      self.present(options: options, from: host, result: result)
    }
  }

  private func present(
    options: ScanOptions,
    from host: UIViewController,
    result: @escaping FlutterResult
  ) {
    let controller = BarcodeScannerViewController(options: options)
    controller.onCode = { [weak self] code in self?.deliver(code) }
    controller.onCancel = { [weak self] in self?.finish(code: nil, error: nil) }
    controller.onError = { [weak self] code, message in
      self?.finish(code: nil, error: Self.error(code, message))
    }

    scanner = controller
    continuous = options.continuous
    if options.continuous {
      result(nil)
    } else {
      pendingResult = result
    }
    host.present(controller, animated: true)
  }

  private func deliver(_ code: String) {
    if continuous {
      eventSink?(code)
    } else {
      finish(code: code, error: nil)
    }
  }

  /// Dismisses the scanner, then tells Dart how it ended. Does nothing when
  /// no scanner is open.
  private func finish(code: String?, error: FlutterError?) {
    guard let controller = scanner else { return }
    scanner = nil
    let result = pendingResult
    pendingResult = nil
    let wasContinuous = continuous

    let answer = { [weak self] in
      if wasContinuous {
        if let error = error { self?.eventSink?(error) }
        self?.eventSink?(["event": "closed"])
      } else if let error = error {
        result?(error)
      } else {
        result?(code)
      }
    }

    if controller.presentingViewController != nil {
      controller.dismiss(animated: true, completion: answer)
    } else {
      answer()
    }
  }

  private static func error(_ code: String, _ message: String) -> FlutterError {
    return FlutterError(code: code, message: message, details: nil)
  }

  /// The view controller on top of the key window, found when needed rather
  /// than kept from registration: the root can change, and a modal already on
  /// screen can only be presented over, not under.
  private static func topViewController() -> UIViewController? {
    var root: UIViewController?
    if #available(iOS 13.0, *) {
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      let active = scenes.filter { $0.activationState == .foregroundActive }
      let windows = (active.isEmpty ? scenes : active).flatMap { $0.windows }
      root = (windows.first(where: { $0.isKeyWindow }) ?? windows.first)?.rootViewController
    }
    if root == nil {
      root = UIApplication.shared.delegate?.window??.rootViewController
    }
    var top = root
    while let presented = top?.presentedViewController, !presented.isBeingDismissed {
      top = presented
    }
    return top
  }
}
