import AVFoundation
import Flutter

/// The luminance of a camera frame under the scan window, for Dart to read
/// text in: one byte per pixel, row by row, upright.
struct LumaFrame {
  /// The longest side sent: a text line stays sharp enough, a frame small.
  static let maxSide = 1280

  let width: Int
  let height: Int
  let bytes: Data

  /// The luminance plane of `buffer`, an upright 4:2:0 frame, under
  /// `window`: a rectangle of a preview of `preview` points that fills its
  /// bounds with the frame (aspect fill), mirrored when `mirrored`. An empty
  /// window or preview takes what the preview shows, or the whole frame.
  init?(_ buffer: CVPixelBuffer, window: CGRect, preview: CGSize, mirrored: Bool) {
    guard CVPixelBufferGetPlaneCount(buffer) >= 1 else { return nil }
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }
    let frameWidth = CVPixelBufferGetWidthOfPlane(buffer, 0)
    let frameHeight = CVPixelBufferGetHeightOfPlane(buffer, 0)
    let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)

    let crop = LumaFrame.crop(
      frame: CGSize(width: frameWidth, height: frameHeight),
      window: window,
      preview: preview,
      mirrored: mirrored
    )
    let left = max(0, min(frameWidth - 1, Int(crop.minX)))
    let top = max(0, min(frameHeight - 1, Int(crop.minY)))
    let cropWidth = max(1, min(frameWidth - left, Int(crop.width)))
    let cropHeight = max(1, min(frameHeight - top, Int(crop.height)))
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

  /// The rectangle of a `frame` of pixels under `window`, a rectangle of a
  /// preview of `preview` points showing the frame in aspect fill.
  static func crop(frame: CGSize, window: CGRect, preview: CGSize, mirrored: Bool) -> CGRect {
    let whole = CGRect(origin: .zero, size: frame)
    guard preview.width > 0, preview.height > 0 else { return whole }
    let scale = max(preview.width / frame.width, preview.height / frame.height)
    let offsetX = (preview.width - frame.width * scale) / 2
    let offsetY = (preview.height - frame.height * scale) / 2
    let shown = window.width > 0 && window.height > 0
      ? window
      : CGRect(origin: .zero, size: preview)
    var x = (shown.minX - offsetX) / scale
    let y = (shown.minY - offsetY) / scale
    let width = shown.width / scale
    let height = shown.height / scale
    // The preview mirrors the frame: the window's left is the frame's right.
    if mirrored { x = frame.width - x - width }
    return CGRect(x: x, y: y, width: width, height: height).intersection(whole)
  }

  /// The frame as the `onFrame` call of the Dart side reads it. The frame is
  /// upright already: no quarter turn.
  var payload: [String: Any] {
    return [
      "width": width,
      "height": height,
      "bytes": FlutterStandardTypedData(bytes: bytes),
      "quarterTurns": 0,
    ]
  }
}
