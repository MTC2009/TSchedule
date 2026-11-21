/// Separates motion time from civil time. Pausing holds the current cloud shapes instead of
/// restarting the simulation or advancing it by the time spent offscreen.
struct SkyPlaybackClock {
    private var held = 0.0
    private var origin: Double?

    func elapsed(at instant: Double) -> Double {
        guard let origin, instant.isFinite else { return held }
        return held + max(0, instant - origin)
    }

    mutating func setRunning(_ running: Bool, at instant: Double) {
        guard instant.isFinite else { return }
        if running {
            if origin == nil { origin = instant }
        } else if origin != nil {
            held = elapsed(at: instant)
            origin = nil
        }
    }
}
