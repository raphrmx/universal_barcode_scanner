import AVFoundation
import UIKit

/// Error codes shared with the Dart side's `ScannerErrorCode`.
enum ScanError {
  static let permissionDenied = "camera_permission_denied"
  static let cameraUnavailable = "camera_unavailable"
  static let alreadyActive = "already_active"
}

/// A code read, and the name of its symbology as every platform gives it,
/// the web's BarcodeDetector names.
struct ScannedCode {
  let value: String
  let format: String

  init(value: String, type: AVMetadataObject.ObjectType) {
    self.value = value
    switch type {
    case .aztec: format = "aztec"
    case .code39, .code39Mod43: format = "code_39"
    case .code93: format = "code_93"
    case .code128: format = "code_128"
    case .dataMatrix: format = "data_matrix"
    case .ean8: format = "ean_8"
    case .ean13: format = "ean_13"
    case .interleaved2of5, .itf14: format = "itf"
    case .pdf417: format = "pdf417"
    case .qr: format = "qr_code"
    case .upce: format = "upc_e"
    default: format = "unknown"
    }
  }

  /// What goes to Dart.
  var payload: [String: String] { ["code": value, "format": format] }
}

/// The arguments the Dart side sends, parsed once.
struct ScanOptions {
  /// Tags every answer and event of this scan; see `NativeScanner`.
  let session: Int
  let lineColor: UIColor
  let cancelLabel: String
  let showTorchButton: Bool
  let continuous: Bool
  /// Square for QR codes, wide for barcodes.
  let squareWindow: Bool
  /// False for no window: nothing is drawn, and the whole frame is read.
  let hasWindow: Bool
  let position: AVCaptureDevice.Position
  let scanFormat: String
  let delay: TimeInterval
  /// Scan window asked for, in points.
  let windowSize: CGSize?
  /// Least time between two frames for Dart; zero for none.
  let frameInterval: TimeInterval

  init(arguments: [String: Any]) {
    session = ScanOptions.session(in: arguments)
    lineColor =
      UIColor(hex: arguments["lineColor"] as? String ?? "")
      ?? UIColor(red: 1, green: 0.4, blue: 0.4, alpha: 1)
    let cancel = arguments["cancelLabel"] as? String ?? ""
    cancelLabel = cancel.isEmpty ? "Cancel" : cancel
    showTorchButton = arguments["showTorchButton"] as? Bool ?? false
    continuous = arguments["continuous"] as? Bool ?? false
    let window = arguments["scanWindow"] as? String ?? "wide"
    squareWindow = window == "square"
    hasWindow = window != "none"
    position = (arguments["cameraFace"] as? String) == "front" ? .front : .back
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

  /// Marks a call that named no session.
  static let noSession = -1

  /// The session a channel call names, or `noSession`.
  static func session(in arguments: [String: Any]) -> Int {
    return (arguments["session"] as? NSNumber)?.intValue ?? noSession
  }

  /// Symbologies to read. Fewer is less work on every frame.
  var metadataTypes: [AVMetadataObject.ObjectType] {
    let barcodes: [AVMetadataObject.ObjectType] = [
      .code128, .code39, .code39Mod43, .code93, .ean13, .ean8,
      .interleaved2of5, .itf14, .pdf417, .upce,
    ]
    switch scanFormat {
    case "NONE":
      // Frames only.
      return []
    case "ONLY_QR_CODE":
      return [.qr]
    case "ONLY_BARCODE":
      return barcodes
    default:
      return barcodes + [.aztec, .dataMatrix, .qr]
    }
  }

  /// The scan window inside `area`: the requested size, or one that suits
  /// the shape.
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

/// Decides which of the codes read frame after frame are worth reporting.
///
/// A code held in front of the camera is read on every frame. It is reported
/// once, and again only after it has been out of sight for `sameCodeGap`. Each
/// code is followed on its own, so two codes in sight are each reported once
/// rather than alternately. No two codes are reported less than `delay` apart;
/// a code the delay held back goes out as soon as the delay allows, if it is
/// still in sight.
final class ReadGate {
  static let sameCodeGap: TimeInterval = 1.0

  private struct Sighting {
    var seen: TimeInterval
    var reported: Bool
  }

  private let delay: TimeInterval
  private var sightings: [String: Sighting] = [:]
  private var lastEmit: TimeInterval?

  init(delay: TimeInterval) {
    self.delay = max(0, delay)
  }

  func accept(_ value: String, now: TimeInterval = CACurrentMediaTime()) -> Bool {
    sightings = sightings.filter { now - $0.value.seen < ReadGate.sameCodeGap }
    var sighting = sightings[value] ?? Sighting(seen: now, reported: false)
    sighting.seen = now
    if sighting.reported {
      sightings[value] = sighting
      return false
    }
    if let last = lastEmit, now - last < delay {
      sightings[value] = sighting
      return false
    }
    sighting.reported = true
    sightings[value] = sighting
    lastEmit = now
    return true
  }

  /// Forgets every code, so the ones in sight are reported again.
  func reset() {
    sightings.removeAll()
    lastEmit = nil
  }
}

/// Asks for the camera if needed. Completes on the main thread.
enum CameraAccess {
  static func request(_ completion: @escaping (Bool) -> Void) {
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
}

extension UIColor {
  /// Reads `#AARRGGBB` or `#RRGGBB`, the two forms the Dart side sends.
  convenience init?(hex: String) {
    var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("#") { value.removeFirst() }
    guard value.count == 6 || value.count == 8,
      let raw = UInt32(value, radix: 16)
    else { return nil }

    let alpha: CGFloat = value.count == 8 ? CGFloat((raw >> 24) & 0xFF) / 255 : 1
    self.init(
      red: CGFloat((raw >> 16) & 0xFF) / 255,
      green: CGFloat((raw >> 8) & 0xFF) / 255,
      blue: CGFloat(raw & 0xFF) / 255,
      alpha: alpha
    )
  }
}
