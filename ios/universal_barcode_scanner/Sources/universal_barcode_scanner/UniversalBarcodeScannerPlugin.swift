import AVFoundation
import AudioToolbox
import Flutter
import UIKit

/// Where a scan stands. UIKit ignores a dismissal asked for while a
/// presentation is still animating, and refuses a presentation while a
/// dismissal is: each stage waits for the previous one.
private enum ScanPhase {
  case requestingAccess, presenting, shown, dismissing
}

/// How a scan ended.
private enum ScanOutcome {
  case code(ScannedCode)
  case cancelled
  case failed(FlutterError)
}

/// One scan, from the call that opened it to its answer.
private final class Scan {
  let options: ScanOptions
  let result: FlutterResult
  var phase = ScanPhase.requestingAccess
  var controller: ScannerViewController?
  /// Decided while the scanner was still appearing, applied once it has.
  var pendingOutcome: ScanOutcome?

  init(options: ScanOptions, result: @escaping FlutterResult) {
    self.options = options
    self.result = result
  }
}

/// Entry point on iOS.
///
/// `scanBarcode` presents the scanner over whatever is on screen. A single
/// scan answers with the code, or nil when cancelled; a continuous one answers
/// once the scanner is up and sends `{"session": n, "code": ...}` on the event
/// channel, then `{"session": n, "event": "closed"}`. `close` ends the scan of
/// the session it names, at whatever stage it is.
public class UniversalBarcodeScannerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var scan: Scan?
  /// A scan asked for while the previous one was being dismissed.
  private var queued: (() -> Void)?

  public static func register(with registrar: FlutterPluginRegistrar) {
    // Nothing here reads a window or a view controller: under the scene life
    // cycle the app delegate has no window yet when plugins register.
    let instance = UniversalBarcodeScannerPlugin()

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
      EmbeddedScannerFactory(messenger: registrar.messenger()),
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
    let arguments = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "scanBarcode":
      requestScan(ScanOptions(arguments: arguments), result: result)
    case "scanImage":
      guard let bytes = arguments["bytes"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "invalid_image", message: "No image to read.", details: nil))
        return
      }
      ImageReader.read(
        bytes.data, scanFormat: arguments["scanFormat"] as? String ?? "ALL_FORMATS",
        result: result)
    case "beep":
      // The short system tone, at the ringer's volume.
      AudioServicesPlaySystemSound(1057)
      result(nil)
    case "close":
      let session = ScanOptions.session(in: arguments)
      if let current = scan,
        session == ScanOptions.noSession || session == current.options.session
      {
        finish(current, .cancelled)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func requestScan(_ options: ScanOptions, result: @escaping FlutterResult) {
    if let current = scan {
      // The previous scanner is on its way out: this one opens once it has
      // gone rather than being refused.
      if current.phase == .dismissing && queued == nil {
        queued = { [weak self] in self?.requestScan(options, result: result) }
      } else {
        result(Self.error(ScanError.alreadyActive, "A scanner is already open.", options))
      }
      return
    }

    let scan = Scan(options: options, result: result)
    self.scan = scan
    CameraAccess.request { [weak self] granted in
      // Closed while the user was being asked: it already answered.
      guard let self = self, self.scan === scan else { return }
      guard granted else {
        self.finish(
          scan,
          .failed(
            Self.error(
              ScanError.permissionDenied,
              "Camera access was denied. Grant it in Settings, and check that the "
                + "app declares NSCameraUsageDescription.",
              options
            )
          )
        )
        return
      }
      guard AVCaptureDevice.default(for: .video) != nil else {
        self.finish(
          scan,
          .failed(Self.error(ScanError.cameraUnavailable, "No camera is available.", options))
        )
        return
      }
      guard let host = Self.topViewController() else {
        self.finish(
          scan,
          .failed(
            Self.error(ScanError.cameraUnavailable, "No view controller to present from.", options)
          )
        )
        return
      }
      self.present(scan, from: host)
    }
  }

  private func present(_ scan: Scan, from host: UIViewController) {
    let controller = ScannerViewController(options: scan.options)
    // Every callback checks that it comes from the scanner still in charge:
    // a closed one may have frames in flight.
    controller.onCode = { [weak self, weak controller] code in
      guard let self = self, let current = self.scan, current.controller === controller else {
        return
      }
      if current.options.continuous {
        self.eventSink?([
          "session": current.options.session, "code": code.value, "format": code.format,
        ])
      } else {
        self.finish(current, .code(code))
      }
    }
    controller.onCancel = { [weak self, weak controller] in
      guard let self = self, let current = self.scan, current.controller === controller else {
        return
      }
      self.finish(current, .cancelled)
    }
    controller.onError = { [weak self, weak controller] code, message in
      guard let self = self, let current = self.scan, current.controller === controller else {
        return
      }
      self.finish(current, .failed(Self.error(code, message, current.options)))
    }

    scan.controller = controller
    scan.phase = .presenting
    if scan.options.continuous { scan.result(nil) }
    host.present(controller, animated: true) { [weak self] in
      self?.didPresent(scan)
    }
  }

  private func didPresent(_ scan: Scan) {
    guard self.scan === scan, scan.phase == .presenting else { return }
    scan.phase = .shown
    if let outcome = scan.pendingOutcome {
      finish(scan, outcome)
    }
  }

  /// Takes the scanner down, then gives Dart the outcome.
  private func finish(_ scan: Scan, _ outcome: ScanOutcome) {
    guard self.scan === scan else { return }
    switch scan.phase {
    case .requestingAccess:
      self.scan = nil
      answer(scan, outcome)
      runQueued()
    case .presenting:
      // Dismissing now would be ignored; done once the scanner is up.
      if scan.pendingOutcome == nil { scan.pendingOutcome = outcome }
    case .shown:
      scan.phase = .dismissing
      scan.controller?.markFinished()
      let done = { [weak self] in
        guard let self = self else { return }
        if self.scan === scan { self.scan = nil }
        self.answer(scan, outcome)
        self.runQueued()
      }
      // From the presenter: asked of the scanner itself, a dismissal would
      // only close whatever it presents in turn.
      if let presenter = scan.controller?.presentingViewController {
        presenter.dismiss(animated: true, completion: done)
      } else {
        done()
      }
    case .dismissing:
      break
    }
  }

  private func answer(_ scan: Scan, _ outcome: ScanOutcome) {
    let session = scan.options.session
    if scan.options.continuous {
      if scan.phase == .requestingAccess {
        // Never presented: the call itself is still waiting for its answer.
        if case .failed(let error) = outcome {
          scan.result(error)
          return
        }
        scan.result(nil)
      } else if case .failed(let error) = outcome {
        eventSink?(error)
      }
      eventSink?(["session": session, "event": "closed"])
      return
    }
    switch outcome {
    case .code(let code):
      scan.result(code.payload)
    case .cancelled:
      scan.result(nil)
    case .failed(let error):
      scan.result(error)
    }
  }

  private func runQueued() {
    let next = queued
    queued = nil
    next?()
  }

  private static func error(_ code: String, _ message: String, _ options: ScanOptions)
    -> FlutterError
  {
    // The session rides in the details, so the Dart side can tell which
    // scan an error on the event channel belongs to.
    return FlutterError(code: code, message: message, details: options.session)
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
