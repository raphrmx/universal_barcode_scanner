import Cocoa

/// The scan window over the camera: the surround dimmed, the window outlined,
/// and a line sweeping across it. Shared by the scanner window and the
/// embedded view, which each lay it out in their own area.
final class ScannerOverlay {
  private let dim = CAShapeLayer()
  private let outline = CAShapeLayer()
  private let line = CALayer()

  /// The window, in the host layer's coordinates.
  private(set) var window: CGRect = .zero

  init(lineColor: NSColor, shown: Bool) {
    dim.fillRule = .evenOdd
    dim.fillColor = NSColor(white: 0, alpha: 0.5).cgColor
    outline.fillColor = nil
    outline.strokeColor = NSColor(white: 1, alpha: 0.8).cgColor
    outline.lineWidth = 2
    line.backgroundColor = lineColor.cgColor
    // Without a window, nothing is drawn over the camera.
    dim.isHidden = !shown
    outline.isHidden = !shown
    line.isHidden = !shown
  }

  func install(in layer: CALayer) {
    layer.addSublayer(dim)
    layer.addSublayer(outline)
    layer.addSublayer(line)
  }

  /// Places the window in `area` of a host of `bounds`. True when the window
  /// moved, which is when the region Vision reads has to follow.
  @discardableResult
  func layout(bounds: CGRect, area: CGRect, requested: CGSize?, square: Bool) -> Bool {
    let window = ScannerOptions.window(in: area, requested: requested, square: square)

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    dim.frame = bounds
    let path = CGMutablePath()
    path.addRect(bounds)
    path.addRect(window)
    dim.path = path
    outline.frame = bounds
    outline.path = CGPath(rect: window, transform: nil)
    line.frame = CGRect(x: window.minX, y: window.midY, width: window.width, height: 2)
    CATransaction.commit()

    guard window != self.window else { return false }
    self.window = window
    sweep()
    return true
  }

  private func sweep() {
    line.removeAllAnimations()
    guard window.height > 4,
      !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    else { return }
    let animation = CABasicAnimation(keyPath: "position.y")
    animation.fromValue = window.minY + 1
    animation.toValue = window.maxY - 1
    animation.duration = 1.5
    animation.autoreverses = true
    animation.repeatCount = .infinity
    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    animation.isRemovedOnCompletion = false
    line.add(animation, forKey: "sweep")
  }
}
