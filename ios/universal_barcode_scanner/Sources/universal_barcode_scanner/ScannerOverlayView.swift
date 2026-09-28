import UIKit

/// The dimmed surround, the window's outline, and the line sweeping it.
final class ScannerOverlayView: UIView {
  var lineColor: UIColor = .red {
    didSet { line.backgroundColor = lineColor.cgColor }
  }
  var squareWindow = true {
    didSet { setNeedsLayout() }
  }
  /// A window of this size, in points, instead of one picked from the shape.
  var windowSize: CGSize? {
    didSet { setNeedsLayout() }
  }
  /// Height kept clear at the bottom, for controls drawn over the camera.
  var bottomInset: CGFloat = 0 {
    didSet { setNeedsLayout() }
  }
  /// Called whenever the window moves or changes size.
  var onWindowChange: ((CGRect) -> Void)?

  private(set) var scanWindow: CGRect = .zero

  private let dim = CAShapeLayer()
  private let outline = CAShapeLayer()
  private let line = CALayer()

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    backgroundColor = .clear

    dim.fillRule = .evenOdd
    dim.fillColor = UIColor(white: 0, alpha: 0.5).cgColor
    outline.fillColor = nil
    outline.strokeColor = UIColor(white: 1, alpha: 0.8).cgColor
    outline.lineWidth = 2
    line.backgroundColor = lineColor.cgColor

    layer.addSublayer(dim)
    layer.addSublayer(outline)
    layer.addSublayer(line)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not used")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let area = CGRect(
      x: 0,
      y: 0,
      width: bounds.width,
      height: max(0, bounds.height - bottomInset)
    )
    let window = ScanOptions.window(in: area, requested: windowSize, square: squareWindow)

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    dim.frame = bounds
    let path = UIBezierPath(rect: bounds)
    path.append(UIBezierPath(rect: window))
    dim.path = path.cgPath
    outline.frame = bounds
    outline.path = UIBezierPath(rect: window).cgPath
    line.frame = CGRect(x: window.minX, y: window.minY, width: window.width, height: 2)
    CATransaction.commit()

    if window != scanWindow {
      scanWindow = window
      sweep()
      onWindowChange?(window)
    }
  }

  private func sweep() {
    line.removeAllAnimations()
    guard scanWindow.height > 4 else { return }
    if UIAccessibility.isReduceMotionEnabled {
      line.position = CGPoint(x: scanWindow.midX, y: scanWindow.midY)
      return
    }
    let animation = CABasicAnimation(keyPath: "position.y")
    animation.fromValue = scanWindow.minY + 1
    animation.toValue = scanWindow.maxY - 1
    animation.duration = 1.5
    animation.autoreverses = true
    animation.repeatCount = .infinity
    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    // Kept across a trip to the background, which otherwise removes it.
    animation.isRemovedOnCompletion = false
    line.add(animation, forKey: "sweep")
  }
}
