import UIKit

/// The scanner's icons, drawn from the same shapes as the Android ones, on a
/// 24-point grid: a bolt for the torch, a camera with two turning arrows for
/// the switch. Drawn in code, so the package ships no image to look up.
enum ScannerIcons {
  static func torch(on: Bool) -> UIImage {
    return on ? torchOn : torchOff
  }

  static let switchCamera: UIImage = drawIcon {
    let body = UIBezierPath()
    body.move(to: CGPoint(x: 4.5, y: 7.5))
    body.addLine(to: CGPoint(x: 8.2, y: 7.5))
    body.addLine(to: CGPoint(x: 9.7, y: 5.5))
    body.addLine(to: CGPoint(x: 14.3, y: 5.5))
    body.addLine(to: CGPoint(x: 15.8, y: 7.5))
    body.addLine(to: CGPoint(x: 19.5, y: 7.5))
    body.addArc(
      withCenter: CGPoint(x: 19.5, y: 9), radius: 1.5,
      startAngle: radians(270), endAngle: radians(360), clockwise: true)
    body.addLine(to: CGPoint(x: 21, y: 18))
    body.addArc(
      withCenter: CGPoint(x: 19.5, y: 18), radius: 1.5,
      startAngle: 0, endAngle: radians(90), clockwise: true)
    body.addLine(to: CGPoint(x: 4.5, y: 19.5))
    body.addArc(
      withCenter: CGPoint(x: 4.5, y: 18), radius: 1.5,
      startAngle: radians(90), endAngle: radians(180), clockwise: true)
    body.addLine(to: CGPoint(x: 3, y: 9))
    body.addArc(
      withCenter: CGPoint(x: 4.5, y: 9), radius: 1.5,
      startAngle: radians(180), endAngle: radians(270), clockwise: true)
    body.close()
    body.lineWidth = 1.5
    body.lineJoinStyle = .round
    body.stroke()

    let arrows = UIBezierPath()
    addArrow(to: arrows, from: 190, to: 320)
    addArrow(to: arrows, from: 10, to: 140)
    arrows.lineWidth = 1.4
    arrows.lineCapStyle = .round
    arrows.lineJoinStyle = .round
    arrows.stroke()
  }

  private static let torchOn: UIImage = drawIcon {
    boltPath().fill()
  }

  private static let torchOff: UIImage = drawIcon {
    let outline = boltPath()
    outline.lineWidth = 1.4
    outline.lineJoinStyle = .round
    outline.stroke()

    let slash = UIBezierPath()
    slash.move(to: CGPoint(x: 4, y: 4))
    slash.addLine(to: CGPoint(x: 20, y: 20))
    slash.lineWidth = 1.8
    slash.lineCapStyle = .round
    slash.stroke()
  }
}

private func radians(_ degrees: CGFloat) -> CGFloat {
  return degrees * .pi / 180
}

private func boltPath() -> UIBezierPath {
  let path = UIBezierPath()
  path.move(to: CGPoint(x: 13.8, y: 2.5))
  path.addLine(to: CGPoint(x: 6, y: 13.2))
  path.addLine(to: CGPoint(x: 11.2, y: 13.2))
  path.addLine(to: CGPoint(x: 9.8, y: 21.5))
  path.addLine(to: CGPoint(x: 18, y: 10.4))
  path.addLine(to: CGPoint(x: 12.8, y: 10.4))
  path.close()
  return path
}

/// Part of a turn round the camera's centre, clockwise from `start` to `end`
/// degrees, with a chevron at its end.
private func addArrow(to path: UIBezierPath, from start: CGFloat, to end: CGFloat) {
  let center = CGPoint(x: 12, y: 13.5)
  let radius: CGFloat = 3.6
  let begin = CGPoint(
    x: center.x + radius * cos(radians(start)),
    y: center.y + radius * sin(radians(start)))
  let tip = CGPoint(
    x: center.x + radius * cos(radians(end)),
    y: center.y + radius * sin(radians(end)))
  path.move(to: begin)
  path.addArc(
    withCenter: center, radius: radius,
    startAngle: radians(start), endAngle: radians(end), clockwise: true)

  // Back along the direction of travel, and to either side of it.
  let alongX = -sin(radians(end))
  let alongY = cos(radians(end))
  let acrossX = cos(radians(end))
  let acrossY = sin(radians(end))
  path.move(to: CGPoint(x: tip.x - 1.6 * alongX + acrossX, y: tip.y - 1.6 * alongY + acrossY))
  path.addLine(to: tip)
  path.addLine(to: CGPoint(x: tip.x - 1.6 * alongX - acrossX, y: tip.y - 1.6 * alongY - acrossY))
}

/// Renders `body`, drawn on the 24-point grid, into a 28-point white icon.
private func drawIcon(_ body: () -> Void) -> UIImage {
  let size = CGSize(width: 28, height: 28)
  return UIGraphicsImageRenderer(size: size).image { context in
    context.cgContext.scaleBy(x: size.width / 24, y: size.height / 24)
    UIColor.white.setFill()
    UIColor.white.setStroke()
    body()
  }
}
