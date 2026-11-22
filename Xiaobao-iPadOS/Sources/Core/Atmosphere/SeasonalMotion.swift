import Foundation

/// Values written by the geometry pass and read only under a pointer; zero is empty sky.
enum SeasonalTarget: Int, Sendable { case none, subject, water, rabbit, sleigh }

struct SeasonalGesture {
    let target: SeasonalTarget
    let point: SIMD3<Float>
    let began: Float
    var pull: Float
    var held: Bool
}

struct SeasonalMotion {
    /// Fixed for a visit. Each event derives its variation from its lane and launch
    /// number, never from the number of frames drawn. Pausing cannot reshuffle it.
    let seed:UInt32
    init(seed:UInt32 = 0) {self.seed=seed}
    private(set) var gesture: SeasonalGesture?
    private(set) var landing: Float?
    private(set) var present: (at: Float, origin: SIMD3<Float>)?
    private(set) var ignition:Float?

    func sample(_ lane:Int,_ cycle:Int,_ channel:Int)->Float {
        var x=seed ^ (UInt32(truncatingIfNeeded:lane) &* 0x9e3779b9)
            ^ (UInt32(truncatingIfNeeded:cycle) &* 0x85ebca6b) ^ (UInt32(truncatingIfNeeded:channel+1) &* 0xc2b2ae35)
        x ^= x>>16; x &*= 0x7feb352d;x ^= x>>15; x &*= 0x846ca68b;x ^= x>>16
        return Float(x>>8)/16_777_216
    }
    /// Three discrete spring arcs; rotation begins after the last landing. Color
    /// outlasts the spin, then the lantern returns to amber and accepts another tap.
    func haunt(_ t:Float)->(rise:Float,turn:Float,fire:Float) {
        guard let ignition else {return (0,0,0)}
        let a=max(0,t-ignition)
        guard a<5.2 else {return (0,0,0)}
        let span:Float=0.48, count=Int(a/span), phase=(a/span)-Float(count)
        let rise:Float=count<3 ? 4*phase*(1-phase)*[0.32,0.255,0.19][count] : 0
        let p=max(0,min(1,(a-3*span)/0.85)),fade=max(0,min(1,(5.2-a)/0.9))
        return (rise,2 * .pi*p*p*(3-2*p),min(1,a*11)*fade)
    }

    static func flight(_ festival: Festival, time t: Float, landing: Float?) -> SIMD3<Float>? {
        let rabbit = festival == .midautumn
        guard rabbit || festival == .christmas || festival == .christmasEve else { return nil }
        let period: Float = rabbit ? 23 : 28, duration: Float = rabbit ? 11 : 15
        // A manual preview starts with a visible actor; the quiet interval is part of the loop.
        let shifted = max(0,t) + (rabbit ? 3.4 : 4.1)
        let cycle = floor(shifted/period), p = (shifted-cycle*period)/duration
        guard p <= 1 else { return nil }
        var y:Float = rabbit ? 0.50+0.067*cos(2 * .pi*(p-0.12))-0.055*sin(.pi*p) : 0.38-0.098*sin(.pi*p)
        var z: Float = (rabbit ? 7.6 : (festival == .christmasEve ? 12 : 8.7)) + 0.8*sin(p*4)
        if rabbit, let landing, t >= landing, floor((landing+3.4)/period) == cycle {
            let age = t-landing
            guard age < 2.5 else { return nil }
            y += 0.19*age*age
            z += 3.6*age*age
        }
        return .init(rabbit ? 1.16-1.32*p : -0.16+1.32*p, y,z)
    }

    @discardableResult mutating func touch(_ target: SeasonalTarget, scene: Festival, time: Float,
                                            point: SIMD3<Float>, chance: Float, holding: Bool = false,stillFrame:Bool = false) -> Bool {
        guard time.isFinite, point.x.isFinite, point.y.isFinite, point.z.isFinite else { return false }
        switch target {
        case .none: return false
        case .rabbit:
            guard scene == .midautumn, Self.flight(scene,time:time,landing:landing) != nil,
                  landing.map({ time-$0 > 2.5 }) ?? true else { return false }
            landing = time
        case .sleigh:
            guard scene == .christmas || scene == .christmasEve,
                  Self.flight(scene,time:time,landing:nil) != nil,
                  chance < 0.72, present.map({ time-$0.at > 1.1 }) ?? true else { return false }
            present = (time,point)
        case .subject, .water:
            if scene == .halloween {
                guard target == .subject,!holding,stillFrame || (ignition.map({time-$0>=5.2}) ?? true) else {return false}
                ignition=time;return true
            }
            guard Festival.solarTerms.contains(scene) else { return false }
            gesture = .init(target:target,point:point,began:time,pull:0,held:holding)
        }
        return true
    }

    mutating func pull(_ displacement: Float) {
        guard gesture?.held == true else { return }
        gesture?.pull = max(-1,min(1,displacement))
    }

    mutating func release(at t: Float) {
        guard let g = gesture, g.held else { return }
        gesture = .init(target:g.target,point:g.point,began:t,pull:g.pull,held:false)
    }
    func age(_ t: Float) -> Float { gesture.map { max(0,t-$0.began) } ?? 1000 }
    func lift(_ t: Float) -> Float {
        guard let g = gesture, g.target == .subject else { return 0 }
        if g.held { return min(1,abs(g.pull)+0.25) }
        let a = age(t)
        return a < 4 ? min(1,a*10)*exp(-max(0,a-0.55)*2.0) : 0
    }
    func bend(_ t: Float) -> Float {
        guard let g = gesture, g.target == .subject else { return 0 }
        if g.held { return g.pull }
        let a = age(t)
        return a < 3 ? exp(-2.8*a)*(abs(g.pull)>0.02 ? g.pull*cos(8*a) : 0.69*sin(8*a)) : 0
    }
}
