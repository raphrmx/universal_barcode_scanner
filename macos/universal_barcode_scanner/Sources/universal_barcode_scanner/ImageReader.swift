import Foundation
import ImageIO
import Vision
import FlutterMacOS

/// Reads every code in an encoded image, with Vision and without the camera.
///
/// ImageIO opens the bytes, so any format the system decodes will do, and
/// hands over the orientation the EXIF gives: a photo taken sideways reads as
/// it was shot.
enum ImageReader {
  /// Reads [data] off the main thread and answers on it: the codes as they go
  /// to Dart, each once, or a `FlutterError`.
  static func read(_ data: Data, scanFormat: String, result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
      let answer = decode(data, scanFormat: scanFormat)
      DispatchQueue.main.async { result(answer) }
    }
  }

  private static func decode(_ data: Data, scanFormat: String) -> Any {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
      return FlutterError(
        code: "invalid_image", message: "The bytes are not an image this system opens.",
        details: nil)
    }
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let orientation =
      (properties?[kCGImagePropertyOrientation] as? NSNumber)
      .flatMap { CGImagePropertyOrientation(rawValue: $0.uint32Value) } ?? .up

    let request = VNDetectBarcodesRequest()
    let wanted = ScannerCamera.symbologies(for: scanFormat)
    if !wanted.isEmpty {
      request.symbologies = wanted
    }
    do {
      try VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
        .perform([request])
    } catch {
      return FlutterError(code: "unknown", message: error.localizedDescription, details: nil)
    }

    var seen = Set<String>()
    var codes: [[String: String]] = []
    for observation in request.results ?? [] {
      guard let value = observation.payloadStringValue, !value.isEmpty else { continue }
      let code = ScannedCode(value: value, symbology: observation.symbology)
      // Vision may find the same code more than once in one picture.
      if seen.insert(code.format + "\u{0}" + code.value).inserted {
        codes.append(code.payload)
      }
    }
    return codes
  }
}
