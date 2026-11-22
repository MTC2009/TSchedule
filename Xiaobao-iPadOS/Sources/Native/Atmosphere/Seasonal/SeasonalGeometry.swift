import Metal
import simd

typealias SkyPoint = SIMD3<Float>

/// Closed meshes in a shared atlas. The leaf has two curved faces and a curved central rib;
/// no primitive is a camera-facing quad. Each instance can rotate independently of the camera.
enum SeasonalShape: Int, CaseIterable {
    case globe, cube, stem, cone, leaf, ring, hull, lantern, lake, bank
    case blade, petal, feather, ear, wing, pad, limb, hair, vessel, roof, hare, hareCoat, songbird, stag, beetle, glume, bough
    case plume, twig, leaflet, bead, rock
    case hareForeleg, hareHindleg, deerForeleg, deerHindleg, crown, pumpkin, batWing, floor, hillside, dragonHead, paddler
    case sparrowSkin, sparrowContour, sparrowWing, sparrowBill, sparrowFoot, sparrowPerch
    case moonCut, magpieCut, pinionCut, sailCut, stagCut, riderCut, prowCut, waveCut, ridgeCut, passCut, raceHull, fireTongue
    case spanCut, scrollCut, weaverCut, oarsmanCut, swallowCut, mapleCut, cragCut, pavilionCut
    case bridgeQuill, herdsmanCut, lotusTepal, paddleBlade, rowerFaceCut, wingFlashCut, flankFlashCut
    case bambooLeaf, huskBody, huskFold, oliveLeaf, mumLeaf, mumRay, bulbLeaf, plumFlower, osmanthusFlower, narcissusFlower, narcissusCup
    static func spanHeight(_ f:Float)->Float {-0.26+0.62*sin(.pi*f)+0.17*f}
    static func trailHeight(_ x:Float)->Float {0.13+0.40*x+0.095*sin(2.6*x)+0.041*sin(6.7*x+0.9)}
    var belongsToSparrow:Bool {
        switch self {
        case .sparrowSkin,.sparrowContour,.sparrowWing,.sparrowBill,.sparrowFoot,.sparrowPerch: return true
        default: return false
        }
    }

    /// Shared by the bank mesh and objects planted on its crest, in normalized bank space.
    static func crest(at x: Float) -> Float {
        0.44+0.20*cos(14*x)+0.15*sin(29*x)+0.075*sin(53*x+0.5)+0.038*cos(119*x)
    }
    static func bankHeight(_ x:Float,_ z:Float)->Float {
        let ridge=crest(at:x)
        let h:Float = z < -0.57 ? -0.50+((z+1)/0.43)*(0.50+0.43*ridge)
            : (z < 0.16 ? 0.43*ridge+(z+0.57)/0.73*0.57*ridge : ridge-(z-0.16)/0.84*(ridge+0.41))
        return h+0.065*sin(41*x+2.1*z+1.5*sin(22*x+3*z))*sin(7*z+0.3*sin(18*x))+0.028*sin(102*x+13*z)
    }

}

struct SeasonalVertex {
    var positionU, normalV: SIMD4<Float>
    init(position:SkyPoint,normal:SkyPoint,uv:SIMD2<Float> = .zero) {
        positionU = .init(position,uv.x); normalV = .init(normal,uv.y)
    }
}

struct SeasonalMeshAtlas {
    let vertices: MTLBuffer
    let indices: MTLBuffer
    let ranges: [Range<Int>]

    init(device: MTLDevice, sparrow:Bool = false) throws {
        // In-progress festival meshes are not a dependency of the ordinary sky build.
        #if TSCHEDULE_SEASONAL_ART
        var all: [SeasonalVertex] = [], indices: [UInt32] = [], ranges: [Range<Int>] = []
        for shape in SeasonalShape.allCases {
            let start = indices.count
            // Leave an empty slot so either immutable bank uses the same shape IDs.
            guard shape.belongsToSparrow == sparrow else {ranges.append(start..<start);continue}
            let base = UInt32(all.count)
            var mesh = Mesh()
            switch shape {
            case .cube: mesh.beveledBox()
            case .stem, .cone, .lantern: mesh.lathe(shape)
            case .lake: mesh.lake()
            case .bank, .hillside: mesh.bank(skirt:shape == .hillside)
            case .floor: mesh.grid(112,58) { u,v in
                let x=2*u-1,z=2*v-1
                return .init(x,0.075*sin(13*x+1.3*sin(6*z))+0.041*cos(31*x+4*z)+0.017*sin(71*x+13*z),z)
            }
            case .beetle: mesh.body(shape)
            case .hare,.songbird,.stag,.dragonHead,.paddler,.hareCoat,.hareForeleg,.hareHindleg,.deerForeleg,.deerHindleg,.ear,.hull,.batWing:
                // Retired figurine slots stay stable without allocating meshes for them.
                ranges.append(start..<start);continue
            case .roof: mesh.roof()
            case .vessel: mesh.vessel()
            case .plume: mesh.plume()
            case .crown: mesh.crown()
            case .sparrowSkin: mesh.grid(88,95) { u,v in SeasonalSparrow.skin(u*2 * .pi,SeasonalSparrow.height(v)) }
            case .sparrowContour: mesh.sparrowContour()
            case .sparrowWing: mesh.sparrowWing()
            case .sparrowBill: mesh.sparrowBill()
            case .sparrowFoot: mesh.sparrowFoot()
            case .sparrowPerch: mesh.sparrowPerch()
            case .fireTongue:
                // Emission flows out of the opening before rising. The cross
                // section remains visible when the lantern is turned edge-on.
                mesh.grid(17,26) { u,v in
                    let a=2*Float.pi*u, r=0.39*pow(max(0.00012,sin(.pi*pow(v,0.61))),0.72)*(1-0.52*v)
                    let curl=0.14*sin(5.2*v+0.23)+0.12*v*v
                    return .init(curl+r*cos(a),-0.52+1.32*v,0.065-0.32*sin(v*1.65)+0.74*r*sin(a))
                }
            case .bambooLeaf,.oliveLeaf,.mumLeaf,.mumRay,.bulbLeaf: mesh.festivalLamina(shape)
            case .plumFlower,.osmanthusFlower,.narcissusFlower: mesh.festivalCorolla(shape)
            case .narcissusCup: mesh.narcissusCup()
            case .huskBody,.huskFold: mesh.leafParcel(shape)
            case .raceHull: mesh.regattaHull()
            case .lotusTepal, .paddleBlade: mesh.sculptedLamina(shape)
            case .moonCut,.magpieCut,.pinionCut,.sailCut,.stagCut,.riderCut,.prowCut,.waveCut,.ridgeCut,.passCut,.bridgeQuill,.herdsmanCut,.rowerFaceCut,.wingFlashCut,.flankFlashCut,
                 .spanCut,.scrollCut,.weaverCut,.oarsmanCut,.swallowCut,.mapleCut,.cragCut,.pavilionCut:
                mesh.relief(shape)
            default: mesh.surface(shape)
            }
            all.append(contentsOf: mesh.vertices)
            indices.append(contentsOf: mesh.indices.map { $0 + base })
            ranges.append(start..<indices.count)
        }
        guard let v = device.makeBuffer(bytes: all, length: MemoryLayout<SeasonalVertex>.stride * all.count),
              let i = device.makeBuffer(bytes: indices, length: MemoryLayout<UInt32>.stride * indices.count)
        else { throw VolumetricSky.SetupError.texture }
        self.vertices = v; self.indices = i; self.ranges = ranges
        #else
        throw SeasonalArtUnavailable.paused
        #endif
    }

    private enum SeasonalArtUnavailable: Error { case paused }

    struct Mesh {
        var vertices: [SeasonalVertex] = []
        var indices: [UInt32] = []

        mutating func face(_ a: SkyPoint, _ b: SkyPoint, _ c: SkyPoint, _ d: SkyPoint) {
            let cross = simd_cross(b-a,c-a)
            guard simd_length_squared(cross) > 0.00000001 else { return }
            let normal = simd_normalize(cross)
            let base = UInt32(vertices.count)
            for p in [a,b,c,d] { vertices.append(.init(position:p,normal:normal)) }
            indices += [base,base+1,base+2,base,base+2,base+3]
        }

        mutating func lathe(_ shape: SeasonalShape) {
            if shape == .lantern {
                // Frames stretch thin paper between eight ribs; the unsupported middle of
                // each panel bows slightly and has restrained vertical tension folds.
                grid(144,54) {u,v in
                    let a=(u*8).rounded(.down),t=u*8-a
                    let a0=(a+0.5)*Float.pi/4,a1=a0+Float.pi/4
                    let axis=SkyPoint(cos(a0)*(1-t)+cos(a1)*t,0,sin(a0)*(1-t)+sin(a1)*t)
                    let h=2*v-1,belly=1-0.42*pow(abs(h),3.9)
                    let flex=sin(.pi*t)*pow(max(0,sin(.pi*v)),0.63)
                    let wrinkle=0.016*cos(5 * .pi*t+0.6*sin(4*h))+0.007*sin(10 * .pi*t+4*h)
                    return axis*(belly+flex*(0.028+wrinkle))+SkyPoint(0,h,0)
                }
                for j in 0..<8 {
                    let a=(Float(j)+0.5)*Float.pi/4,b=a+Float.pi/4
                    for sign:Float in [-1,1] {
                        let tip=SkyPoint(0,sign,0),r=SkyPoint(cos(a)*0.58,sign,sin(a)*0.58),q=SkyPoint(cos(b)*0.58,sign,sin(b)*0.58)
                        if sign>0 { face(tip,q,r,r) } else { face(tip,r,q,q) }
                    }
                }
                return
            }
            let n = 16
            let profile: [(Float, Float)]
            switch shape {
            case .cone: profile = [(-1,1),(1,0.015)]
            default: profile = [(-1,1),(1,0.96)]
            }
            func p(_ k: Int,_ i: Int) -> SkyPoint {
                let a = (Float(i)+0.5)*2*Float.pi/Float(n)
                return SkyPoint(cos(a)*profile[k].1,profile[k].0,sin(a)*profile[k].1)
            }
            for i in 0..<n {
                for k in 0..<(profile.count-1) { face(p(k,i),p(k+1,i),p(k+1,i+1),p(k,i+1)) }
                let end = profile.count-1
                face(.init(0,profile[0].0,0),p(0,i),p(0,i+1),p(0,i+1))
                face(.init(0,profile[end].0,0),p(end,i+1),p(end,i),p(end,i))
            }
        }

        /// A continuous distant shore, with a crest and sloping faces at different depths.
        mutating func bank(skirt:Bool) {
            grid(224,24) { u,v in
                let x = 2*u-1,z = 2*v-1
                return .init(x,SeasonalShape.bankHeight(x,z),z)
            }
            guard skirt else {return}
            // The near flank descends past the lens framing. A thin ridge viewed from
            // below would otherwise expose the bright sky underneath an entire hillside.
            grid(224,12) { u,v in
                let x=2*u-1,roll=1-v
                return .init(x,SeasonalShape.bankHeight(x,-1)-roll*(2.6+0.19*sin(26*x)), -1-roll*1.75)
            }
        }

        mutating func lake() {
            let cols = 104, rows = 64
            for j in 0...rows { for i in 0...cols {
                let x = 2*Float(i)/Float(cols)-1, z = 2*Float(j)/Float(rows)-1
                vertices.append(.init(position:.init(x,0,z),normal:.init(0,1,0)))
            } }
            for j in 0..<rows { for i in 0..<cols {
                let a = UInt32(j*(cols+1)+i), b=a+UInt32(cols+1)
                indices += [a,b,a+1,a+1,b,b+1]
            } }
        }

        mutating func surface(_ shape: SeasonalShape) {
            let fine = [.leaf,.blade,.petal,.ear,.wing,.feather,.pad,.leaflet].contains(shape)
            let small = [.twig,.bead,.glume,.leaflet].contains(shape)
            let columns = shape == .pumpkin ? 100 : small ? 10 : (fine ? 20 : (shape == .hair ? 4 : (shape == .ring ? 52 : 28)))
            let rows = shape == .pumpkin ? 36 : small ? (shape == .leaflet ? 18 : 9) : (fine ? 50 : (shape == .hair ? 3 : (shape == .ring ? 8 : 18)))
            func point(_ u:Float,_ v:Float) -> SkyPoint {
                if fine { return SeasonalSculpt.lamina(shape,u,v) }
                let a = u*2*Float.pi, b = (v-0.5)*Float.pi
                switch shape {
                case .bough,.twig:
                    let radius=(1-0.37*v)*(0.975+0.025*cos(5*a+2*v))
                    return .init(radius*cos(a),2*v-1,radius*sin(a))
                case .rock:
                    let q=SkyPoint(cos(b)*cos(a),sin(b),cos(b)*sin(a))
                    let rugged=0.91+0.094*sin(q.x*5.7+q.y*7.1)*cos(q.z*6.8)+0.042*cos(17*q.z+6*q.x)
                    return q*rugged+SkyPoint(0.11*q.y,0.072*q.z,0.060*q.x)
                case .batWing:
                    let wing=sin(Float.pi*v), scallop=abs(sin(Float.pi*3*v)), chord=(0.18+0.57*wing-0.16*scallop)*sqrt(max(0,1-v))
                    return .init(v,0.19*sin(Float.pi*v)-0.16*v+chord*0.13*sin(a),cos(a)*chord-0.13*v)
                case .ring:
                    let c = v*2*Float.pi, r = 1+0.055*cos(c)
                    return .init(r*cos(a),0.055*sin(c),r*sin(a))
                case .hair:
                    let r = max(0,1-v)
                    return .init(r*cos(a)+0.42*v*v,2*v-1,r*sin(a))
                case .limb,.glume:
                    let hump=pow(max(0,sin(v*Float.pi)),shape == .limb ? 0.46 : 0.69)
                    let w=hump*(1.34-0.77*v)
                    return .init(w*cos(a)+0.12*sin(v*Float.pi),2*v-1,w*sin(a))
                case .hull:
                    let x = 2*v-1, w = pow(max(0,sin(.pi*v)),0.55)
                    return .init(x,0.62*x*x + sin(a)*w*(sin(a)>0 ? 0.18 : 0.82),w*cos(a))
                default: return .init(cos(b)*cos(a),sin(b),cos(b)*sin(a))
                }
            }
            grid(columns,rows,point:point)
        }

        mutating func grid(_ columns:Int,_ rows:Int,point:(Float,Float)->SkyPoint) {
            let first=UInt32(vertices.count)
            for j in 0...rows { for i in 0...columns {
                let u = Float(i)/Float(columns), v = Float(j)/Float(rows)
                let q = min(0.999,max(0.001,v)), h:Float = 0.0004
                let du = point(u+h,q)-point(u-h,q), dv = point(u,q+h)-point(u,q-h)
                var n = simd_normalize(simd_cross(dv,du))
                if !n.x.isFinite { n = .init(0,1,0) }
                vertices.append(.init(position:point(u,v),normal:n,uv:.init(u,v)))
            } }
            for j in 0..<rows { for i in 0..<columns {
                let a = first+UInt32(j*(columns+1)+i), b = a+UInt32(columns+1)
                indices += [a,b,b+1,a,b+1,a+1]
            } }
        }
    }
}
