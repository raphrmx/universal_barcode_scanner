import AVFoundation
import Cocoa
import FlutterMacOS

/// macOS entry point of the plugin.
///
/// Same contract as iOS, because the Dart side does not tell the two apart:
/// `scanBarcode` answers with the code read, or nil when a single scan is
/// cancelled; in continuous mode it answers once the scanner is up, pushes
/// `{"session": n, "code": ...}` to the event channel, then
/// `{"session": n, "event": "closed"}`. `close` ends the scan of the session
/// it names, even while the user is still being asked for the camera.
public class UniversalBarcodeScannerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler,
  NSWindowDelegate
{
  private static let methodChannelName = "universal_barcode_scanner"
  private static let eventChannelName = "universal_barcode_scanner/events"
  private static let noSession = -1

  private var eventSink: FlutterEventSink?

  /// The scan in progress: its options, the call still waiting for an
  /// answer, and its window once it has one. A continuous scan answers its
  /// call as soon as the window is up; a single one when it ends.
  private var options: ScannerOptions?
  private var pendingResult: FlutterResult?
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

    registrar.register(
      EmbeddedScannerFactory(messenger: registrar.messenger),
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
      scan(ScannerOptions(arguments: arguments), result: result)
    case "rejectedBeep":
      // The system's sound for something refused.
      NSSound(named: "Basso")?.play()
      result(nil)
    case "rejected":
      let session = (arguments["session"] as? NSNumber)?.intValue ?? Self.noSession
      if let current = options, session == current.session,
        let controller = scannerWindow?.contentViewController as? ScannerViewController
      {
        controller.showRejected(arguments["message"] as? String ?? "")
      }
      result(nil)
    case "scanImage":
      guard let bytes = arguments["bytes"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "invalid_image", message: "No image to read.", details: nil))
        return
      }
      ImageReader.read(
        bytes.data, scanFormat: arguments["scanFormat"] as? String ?? "ALL_FORMATS",
        result: result)
    case "close":
      let session = (arguments["session"] as? NSNumber)?.intValue ?? Self.noSession
      if let current = options, session == Self.noSession || session == current.session {
        finish(current, code: nil, error: nil)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func scan(_ options: ScannerOptions, result: @escaping FlutterResult) {
    guard self.options == nil else {
      result(Self.error("already_active", "A scanner is already open.", options))
      return
    }
    self.options = options
    pendingResult = result

    // Asking before opening the window: a denied permission should say so
    // rather than show a black rectangle.
    CameraAccess.request { [weak self] granted in
      // Closed while the user was being asked: it already answered.
      guard let self = self, self.options?.session == options.session,
        self.scannerWindow == nil
      else { return }
      guard granted else {
        self.refuse(
          options,
          result,
          Self.error(
            "camera_permission_denied",
            "Camera access was denied. Grant it in System Settings, and check "
              + "that the app declares NSCameraUsageDescription.",
            options
          )
        )
        return
      }
      guard AVCaptureDevice.default(for: .video) != nil else {
        self.refuse(
          options,
          result,
          Self.error("camera_unavailable", "No camera is available on this Mac.", options)
        )
        return
      }
      if options.isContinuousScan {
        self.pendingResult = nil
        result(nil)
      }
      self.present(options)
    }
  }

  /// Ends a scan that never opened, through the call that asked for it.
  private func refuse(
    _ options: ScannerOptions,
    _ result: FlutterResult,
    _ error: FlutterError
  ) {
    self.options = nil
    pendingResult = nil
    result(error)
  }

  // MARK: - Scanner window

  private func present(_ options: ScannerOptions) {
    let controller = ScannerViewController(options: options)
    // Every callback checks that it comes from the scan still in charge: a
    // closed scanner may have frames in flight.
    controller.onScanned = { [weak self] barcode in
      guard let self = self, self.options?.session == options.session else { return }
      if options.isContinuousScan {
        self.eventSink?([
          "session": options.session, "code": barcode.value, "format": barcode.format,
        ])
      } else {
        self.finish(options, code: barcode, error: nil)
      }
    }
    controller.onCancelled = { [weak self] in
      self?.finish(options, code: nil, error: nil)
    }
    controller.onFailed = { [weak self] code, message in
      self?.finish(options, code: nil, error: Self.error(code, message, options))
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
    guard let window = notification.object as? NSWindow, window === scannerWindow,
      let current = options
    else { return }
    finish(current, code: nil, error: nil)
  }

  /// Closes the scanner of `scan` and tells Dart how it ended. Does nothing
  /// once that scan is over.
  private func finish(_ scan: ScannerOptions, code: ScannedCode?, error: FlutterError?) {
    guard let current = options, current.session == scan.session else { return }
    options = nil
    let result = pendingResult
    pendingResult = nil

    if let window = scannerWindow {
      scannerWindow = nil
      window.delegate = nil
      (window.contentViewController as? ScannerViewController)?.stop()
      if let host = window.sheetParent {
        host.endSheet(window)
      } else {
        window.close()
      }
    }

    if current.isContinuousScan {
      if let result = result {
        // Closed before its window opened: the call is still waiting.
        if let error = error {
          result(error)
          return
        }
        result(nil)
      } else if let error = error {
        eventSink?(error)
      }
      eventSink?(["session": current.session, "event": "closed"])
    } else if let error = error {
      result?(error)
    } else {
      result?(code?.payload)
    }
  }

  private static func error(_ code: String, _ message: String, _ options: ScannerOptions)
    -> FlutterError
  {
    // The session rides in the details, so the Dart side can tell which
    // scan an error on the event channel belongs to.
    return FlutterError(code: code, message: message, details: options.session)
  }
}

/// The arguments the Dart side sends with `scanBarcode`, or to create an
/// embedded view.
struct ScannerOptions {
  let session: Int
  let lineColor: NSColor
  let cancelLabel: String
  let isContinuousScan: Bool
  let squareWindow: Bool
  /// False for no window: nothing is drawn, and the whole frame is read.
  let hasWindow: Bool
  let scanFormat: String
  let delay: TimeInterval
  /// Least time between two frames for Dart; zero for none.
  let frameInterval: TimeInterval
  /// Scan window asked for by the embedded view, in points.
  let windowSize: CGSize?

  init(arguments: [String: Any]) {
    session = (arguments["session"] as? NSNumber)?.intValue ?? -1
    lineColor = NSColor(hex: arguments["lineColor"] as? String ?? "")
      ?? NSColor.systemRed
    let cancel = arguments["cancelLabel"] as? String ?? ""
    cancelLabel = cancel.isEmpty ? "Cancel" : cancel
    isContinuousScan = arguments["continuous"] as? Bool ?? false
    let window = arguments["scanWindow"] as? String ?? "wide"
    squareWindow = window == "square"
    hasWindow = window != "none"
    scanFormat = arguments["scanFormat"] as? String ?? "ALL_FORMATS"
    let millis = (arguments["delayMillis"] as? NSNumber)?.doubleValue ?? 0
    delay = max(0, millis) / 1000.0
    let frameMillis = (arguments["frameMillis"] as? NSNumber)?.doubleValue ?? 0
    frameInterval = max(0, frameMillis) / 1000.0

    if let width = (arguments["scanWindowWidth"] as? NSNumber)?.doubleValue,
      let height = (arguments["scanWindowHeight"] as? NSNumber)?.doubleValue,
      width > 0, height > 0
    {
      windowSize = CGSize(width: width, height: height)
    } else {
      windowSize = nil
    }
  }

  /// The scan window in `area`, as every platform places it: centred,
  /// `requested` when given, otherwise square for QR codes and wide for
  /// barcodes, capped so a large window does not get a huge one.
  static func window(in area: CGRect, requested: CGSize?, square: Bool) -> CGRect {
    guard area.width > 0, area.height > 0 else { return .zero }
    let size: CGSize
    if let requested = requested {
      size = CGSize(
        width: min(requested.width, area.width),
        height: min(requested.height, area.height)
      )
    } else if square {
      let side = min(min(area.width, area.height) * 0.75, 320)
      size = CGSize(width: side, height: side)
    } else {
      let width = min(area.width * 0.85, 416)
      size = CGSize(width: width, height: min(width * 0.5, area.height * 0.8))
    }
    return CGRect(
      x: area.midX - size.width / 2,
      y: area.midY - size.height / 2,
      width: size.width,
      height: size.height
    )
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
