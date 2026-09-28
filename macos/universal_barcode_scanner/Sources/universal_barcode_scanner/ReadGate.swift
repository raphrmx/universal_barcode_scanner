import QuartzCore

/// Decides which of the codes read frame after frame are worth reporting.
///
/// The same rule as on every other platform: a code held in front of the
/// camera is reported once, and again only after a second out of sight; each
/// code is followed on its own; no two codes are reported less than `delay`
/// apart, and one the delay held back goes out as soon as it allows.
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

  /// Forgets every code, so the ones in sight count as new again.
  func reset() {
    sightings.removeAll()
    lastEmit = nil
  }
}
