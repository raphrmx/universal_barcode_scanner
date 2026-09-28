import AVFoundation
import Cocoa
import FlutterMacOS

/// macOS entry point of the plugin.
///
/// Same contract as iOS, because the Dart side does not tell the two apart:
/// `scanBarcode` answers with the code read, or nil when a single scan is
/// cancelled; in continuous mode it answers once the scanner is up, pushes
/// every code to the event channel, then `{"event": "closed"}`. `close`
/// closes whichever scanner is open.
public class UniversalBarcodeScannerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler,
  NSWindowDelegate
{
  private static let methodChannelName = "universal_barcode_scanner"
  private static let eventChannelName = "universal_barcode_scanner/events"

  private var pendingResult: FlutterResult?
  private var eventSink: FlutterEventSink?
  private var scannerWindow: NSWindow?
  private var continuous = false

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = UniversalBarcodeScannerPlugin()

    let channel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: registrar.messenger
    )
    registrar.addMethodCallDelegate(instance, channel: channel)

    let events = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: registrar.messenger
    )
    events.setStreamHandler(instance)
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
    guard scannerWindow == nil, pendingResult == nil else {
      result(Self.error("already_active", "A scanner is already open."))
      return
    }
    let options = ScannerOptions(arguments: arguments)

    // Asking before opening the window: a denied permission should say so
    // rather than show a black rectangle.
    requestCameraAccess { [weak self] granted in
      guard let self = self else { return }
      guard granted else {
        result(
          Self.error(
            "camera_permission_denied",
            "Camera access was denied. Grant it in System Settings, and check "
              + "that the app declares NSCameraUsageDescription."
          )
        )
        return
      }
      guard AVCaptureDevice.default(for: .video) != nil else {
        result(Self.error("camera_unavailable", "No camera is available on this Mac."))
        return
      }
      guard self.scannerWindow == nil, self.pendingResult == nil else {
        result(Self.error("already_active", "A scanner is already open."))
        return
      }

      self.continuous = options.isContinuousScan
      if options.isContinuousScan {
        result(nil)
      } else {
        self.pendingResult = result
      }
      self.present(options: options)
    }
  }

  private func requestCameraAccess(_ completion: @escaping (Bool) -> Void) {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      completion(true)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { granted in
        DispatchQueue.main.async { completion(granted) }
      }
    default:
      completion(false)
    }
  }

  // MARK: - Scanner window

  private func present(options: ScannerOptions) {
    let controller = BarcodeScannerViewController(options: options)
    controller.onScanned = { [weak self] barcode in
      guard let self = self else { return }
      if self.continuous {
        self.eventSink?(barcode)
      } else {
        self.finish(code: barcode, error: nil)
      }
    }
    controller.onCancelled = { [weak self] in
      self?.finish(code: nil, error: nil)
    }
    controller.onFailed = { [weak self] code, message in
      self?.finish(code: nil, error: Self.error(code, message))
    }

    let window = NSWindow(contentViewController: controller)
    window.title = "Scan"
    window.styleMask = [.titled, .closable]
    window.setContentSize(NSSize(width: 640, height: 480))
    window.center()
    window.isReleasedWhenClosed = false
    // The title bar's close button is a way out too.
    window.delegate = self
    scannerWindow = window

    if let host = NSApplication.shared.mainWindow {
      host.beginSheet(window, completionHandler: nil)
    } else {
      window.makeKeyAndOrderFront(nil)
    }
  }

  public func windowWillClose(_ notification: Notification) {
    guard let window = notification.object as? NSWindow, window === scannerWindow else { return }
    finish(code: nil, error: nil)
  }

  /// Closes the scanner and tells Dart how it ended. Does nothing when no
  /// scanner is open.
  private func finish(code: String?, error: FlutterError?) {
    guard let window = scannerWindow else { return }
    scannerWindow = nil
    window.delegate = nil
    (window.contentViewController as? BarcodeScannerViewController)?.stop()
    if let host = window.sheetParent {
      host.endSheet(window)
    } else {
      window.close()
    }

    if continuous {
      if let error = error { eventSink?(error) }
      eventSink?(["event": "closed"])
    } else {
      let result = pendingResult
      pendingResult = nil
      if let error = error {
        result?(error)
      } else {
        result?(code)
      }
    }
  }

  private static func error(_ code: String, _ message: String) -> FlutterError {
    return FlutterError(code: code, message: message, details: nil)
  }
}

/// The arguments the Dart side sends with `scanBarcode`.
struct ScannerOptions {
  let lineColor: NSColor
  let cancelButtonText: String
  let isContinuousScan: Bool
  let scanFormat: String
  let delay: TimeInterval

  init(arguments: [String: Any]) {
    lineColor = NSColor(hex: arguments["lineColor"] as? String ?? "")
      ?? NSColor.systemRed
    let cancel = arguments["cancelButtonText"] as? String ?? ""
    cancelButtonText = cancel.isEmpty ? "Cancel" : cancel
    isContinuousScan = arguments["continuous"] as? Bool ?? false
    scanFormat = arguments["scanFormat"] as? String ?? "ALL_FORMATS"
    let millis = (arguments["delayMillis"] as? NSNumber)?.doubleValue ?? 0
    delay = max(0, millis) / 1000.0
  }
}

extension NSColor {
  /// Reads `#AARRGGBB` or `#RRGGBB`, the two forms the Dart side sends.
  convenience init?(hex: String) {
    var value = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if value.hasPrefix("#") { value.removeFirst() }
    guard value.count == 6 || value.count == 8,
      let raw = UInt32(value, radix: 16)
    else { return nil }

    let alpha: CGFloat = value.count == 8
      ? CGFloat((raw & 0xFF00_0000) >> 24) / 255.0
      : 1.0
    self.init(
      srgbRed: CGFloat((raw & 0x00FF_0000) >> 16) / 255.0,
      green: CGFloat((raw & 0x0000_FF00) >> 8) / 255.0,
      blue: CGFloat(raw & 0x0000_00FF) / 255.0,
      alpha: alpha
    )
  }
}
