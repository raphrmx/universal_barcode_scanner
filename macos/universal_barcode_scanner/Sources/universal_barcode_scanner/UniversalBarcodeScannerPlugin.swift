import AVFoundation
import Cocoa
import FlutterMacOS

/// macOS entry point of the plugin.
///
/// Mirrors the iOS contract exactly, because the Dart side does not know the
/// two apart: `scanBarcode` answers with the code that was read, with `-1` when
/// a single scan is cancelled, and in continuous mode pushes every code to the
/// event channel and `-2` on cancel.
public class UniversalBarcodeScannerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static let methodChannelName = "universal_barcode_scanner"
  private static let eventChannelName = "universal_barcode_scanner/events"

  /// Sentinel returned when a single scan is cancelled.
  static let noResult = "-1"
  /// Sentinel pushed to the stream when a continuous scan is cancelled.
  static let cancelled = "-2"

  private var pendingResult: FlutterResult?
  private var eventSink: FlutterEventSink?
  private var scannerWindow: NSWindow?

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
    guard call.method == "scanBarcode" else {
      result(FlutterMethodNotImplemented)
      return
    }

    let arguments = call.arguments as? [String: Any] ?? [:]
    let options = ScannerOptions(arguments: arguments)

    // Asking before opening the window: a denied permission should say so
    // rather than show a black rectangle.
    requestCameraAccess { [weak self] granted in
      guard let self = self else { return }
      guard granted else {
        result(
          FlutterError(
            code: "camera_permission_denied",
            message: "Camera access was denied. Grant it in System Settings, "
              + "and check that the app declares NSCameraUsageDescription.",
            details: nil
          )
        )
        return
      }
      guard AVCaptureDevice.default(for: .video) != nil else {
        result(
          FlutterError(
            code: "camera_unavailable",
            message: "No camera is available on this Mac.",
            details: nil
          )
        )
        return
      }

      self.pendingResult = result
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
      self?.deliver(barcode, options: options)
    }
    controller.onCancelled = { [weak self] in
      guard let self = self else { return }
      self.close()
      if options.isContinuousScan {
        self.eventSink?(UniversalBarcodeScannerPlugin.cancelled)
      } else {
        self.pendingResult?(UniversalBarcodeScannerPlugin.noResult)
        self.pendingResult = nil
      }
    }

    let window = NSWindow(contentViewController: controller)
    window.title = "Scan"
    window.styleMask = [.titled, .closable]
    window.setContentSize(NSSize(width: 640, height: 480))
    window.center()
    window.isReleasedWhenClosed = false
    scannerWindow = window

    if let host = NSApplication.shared.mainWindow {
      host.beginSheet(window, completionHandler: nil)
    } else {
      window.makeKeyAndOrderFront(nil)
    }
  }

  private func deliver(_ barcode: String, options: ScannerOptions) {
    if options.isContinuousScan {
      eventSink?(barcode)
      return
    }
    close()
    pendingResult?(barcode)
    pendingResult = nil
  }

  private func close() {
    guard let window = scannerWindow else { return }
    if let host = window.sheetParent {
      host.endSheet(window)
    } else {
      window.close()
    }
    scannerWindow = nil
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
    cancelButtonText = arguments["cancelButtonText"] as? String ?? "Cancel"
    isContinuousScan = arguments["isContinuousScan"] as? Bool ?? false
    scanFormat = arguments["scanFormat"] as? String ?? "ALL_FORMATS"
    let millis = arguments["delayMillis"] as? Int ?? 0
    delay = TimeInterval(millis) / 1000.0
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
