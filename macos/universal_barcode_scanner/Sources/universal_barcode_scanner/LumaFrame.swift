import AVFoundation
import FlutterMacOS

/// The luminance of a camera frame under the scan window, for Dart to read
/// text in: one byte per pixel, row by row, as the camera sees it.
struct LumaFrame {
  /// The longest side sent: a text line stays sharp enough, a frame small.
  static let maxSide = 1280

  let width: Int
  let height: Int
  let bytes: Data

  /// The luminance plane of `buffer`, a 4:2:0 frame, inside `region`: a
  /// rectangle from 0 to 1 of the frame, origin at the top left, as
  /// `metadataOutputRectConverted` gives it.
  init?(_ buffer: CVPixelBuffer, region: CGRect) {
    guard CVPixelBufferGetPlaneCount(buffer) >= 1 else { return nil }
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }
    let frameWidth = CVPixelBufferGetWidthOfPlane(buffer, 0)
    let frameHeight = CVPixelBufferGetHeightOfPlane(buffer, 0)
    let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)

    let left = max(0, min(frameWidth - 1, Int(region.minX * CGFloat(frameWidth))))
    let top = max(0, min(frameHeight - 1, Int(region.minY * CGFloat(frameHeight))))
    let cropWidth = max(1, min(frameWidth - left, Int(region.width * CGFloat(frameWidth))))
    let cropHeight = max(1, min(frameHeight - top, Int(region.height * CGFloat(frameHeight))))
    // Every step-th pixel each way, past the longest side.
    let step = (max(cropWidth, cropHeight) + LumaFrame.maxSide - 1) / LumaFrame.maxSide
    let outWidth = cropWidth / step
    let outHeight = cropHeight / step
    guard outWidth > 0, outHeight > 0 else { return nil }

    var out = Data(count: outWidth * outHeight)
    let source = base.assumingMemoryBound(to: UInt8.self)
    out.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
      guard let target = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
      for y in 0..<outHeight {
        let row = source + (top + y * step) * stride + left
        let into = target + y * outWidth
        if step == 1 {
          memcpy(into, row, outWidth)
        } else {
          for x in 0..<outWidth {
            into[x] = row[x * step]
          }
        }
      }
    }
    width = outWidth
    height = outHeight
    bytes = out
  }

  /// The frame as the `onFrame` call of the Dart side reads it. A Mac's
  /// camera gives upright frames: no quarter turn.
  var payload: [String: Any] {
    return [
      "width": width,
      "height": height,
      "bytes": FlutterStandardTypedData(bytes: bytes),
      "quarterTurns": 0,
    ]
  }
}
