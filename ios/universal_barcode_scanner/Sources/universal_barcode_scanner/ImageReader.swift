import Foundation
import ImageIO
import Vision
import Flutter

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
    let wanted = visionSymbologies(for: scanFormat)
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

/// Symbologies Vision should look for, from the `scanFormat` the Dart side
/// sent; empty for every one. Only the ones available since the deployment
/// target are named, so the list needs no availability guard.
func visionSymbologies(for scanFormat: String) -> [VNBarcodeSymbology] {
  switch scanFormat {
  case "ONLY_QR_CODE":
    return [.qr]
  case "ONLY_BARCODE":
    return [
      .code39, .code39Checksum, .code39FullASCII, .code39FullASCIIChecksum,
      .code93, .code93i, .code128,
      .ean8, .ean13, .upce,
      .i2of5, .i2of5Checksum, .itf14, .pdf417,
    ]
  default:
    return []
  }
}

extension ScannedCode {
  /// A code Vision read, named as every platform names its symbology.
  init(value: String, symbology: VNBarcodeSymbology) {
    self.value = value
    switch symbology {
    case .aztec: format = "aztec"
    case .code39, .code39Checksum, .code39FullASCII, .code39FullASCIIChecksum:
      format = "code_39"
    case .code93, .code93i: format = "code_93"
    case .code128: format = "code_128"
    case .dataMatrix: format = "data_matrix"
    case .ean8: format = "ean_8"
    case .ean13: format = "ean_13"
    case .i2of5, .i2of5Checksum, .itf14: format = "itf"
    case .pdf417: format = "pdf417"
    case .qr: format = "qr_code"
    case .upce: format = "upc_e"
    default:
      // Codabar came with iOS 15: by name, so older systems still build.
      format = symbology.rawValue.hasSuffix("Codabar") ? "codabar" : "unknown"
    }
  }
}
