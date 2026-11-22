import simd

/// Material roles belong to the sky illustration, never to school controls. Values are linear RGB.
enum SeasonalInk {
    static let bark = SkyPoint(0.105,0.066,0.038), twig = SkyPoint(0.22,0.119,0.054)
    static let jade = SkyPoint(0.055,0.179,0.046), moss = SkyPoint(0.145,0.264,0.045), bud = SkyPoint(0.35,0.48,0.075)
    static let pine = SkyPoint(0.035,0.089,0.041), teal = SkyPoint(0.046,0.20,0.16), water = SkyPoint(0.028,0.078,0.075)
    static let ivory = SkyPoint(0.79,0.71,0.53), pearl = SkyPoint(0.75,0.77,0.73), silver = SkyPoint(0.54,0.58,0.57)
    static let brass = SkyPoint(0.52,0.31,0.095), gold = SkyPoint(0.89,0.55,0.16), honey = SkyPoint(0.85,0.32,0.055)
    static let vermilion = SkyPoint(0.43,0.043,0.026), berry = SkyPoint(0.24,0.019,0.028), blush = SkyPoint(0.68,0.30,0.33)
    static let ink = SkyPoint(0.022,0.029,0.036), slate = SkyPoint(0.14,0.16,0.155), copper = SkyPoint(0.32,0.144,0.055)
    static let hay = SkyPoint(0.42,0.30,0.135), umber = SkyPoint(0.105,0.084,0.060), chalk = SkyPoint(0.61,0.61,0.54)
    static let amber = SkyPoint(0.21,0.097,0.018), rose = SkyPoint(0.49,0.225,0.205)
    static let moonSilk = SkyPoint(0.92,0.91,0.845), midnight = SkyPoint(0.012,0.021,0.038)
    static let farIndigo = SkyPoint(0.205,0.306,0.37), riverMist = SkyPoint(0.42,0.53,0.54)
    static let ghost = SkyPoint(0.12,0.88,0.095), celadon = SkyPoint(0.245,0.411,0.31)
}

/// Stable values shared with SeasonalSurface.h. A swatch is not a material: brass-coloured
/// grain, brass hardware and brass-coloured silk scatter light differently.
enum SeasonalFinish: UInt32 {
    var transmits:Bool { self == .dew || self == .membrane || self == .glass || self == .water }
    case matte, foliage, dew, gourd, paper, water, soil, bark, alloy, fur, plumage, petal,
         shell, feather, cloth, stone, glaze, glass, snow, hide, skin, awn, tile, pinna, membrane, wax, featherBody, caribou, hair, leafPad, ember, canopy, timber, masonry, squash, magpie, paddler,
         sparrowDown, sparrowVane, sparrowHorn, sparrowTarsus, cornea, winterTwig, cutInk, lotusSilk, carvedInk, bambooFibre
}

struct SeasonalInstance {
    var x, y, z, center, material, extras: SIMD4<Float>
    var curve = SIMD4<Float>.zero
}

struct SeasonalScene {
    typealias C = SeasonalInk
    var instances = Array(repeating:[SeasonalInstance](),count:SeasonalShape.allCases.count)
    private(set) var refractors:[Int:[SeasonalInstance]] = [:]
    var light = SIMD4<Float>(repeating:0)
    var glowColor = SkyPoint.zero
    var parcelOrigin: SkyPoint?
    var waterPlane:SIMD4<Float>?
    var waterImpulse:SIMD4<Float>?
    var smoke:Float = 0
    /// Opaque marks nearer than this eye distance sit in front of the cloud
    /// volume. Zero is entirely airborne; the lantern plate mixes both depths.
    var foregroundReach:Float = 0
    var focusZ:Float = 6.8
    var origin = SkyPoint.zero
    var basis = matrix_identity_float3x3
    var unit:Float = 1
    var target = SeasonalTarget.none
    let aspect:Float, t:Float
    let motion:SeasonalMotion
    var lift:Float { motion.lift(t) }
    var bend:Float { motion.bend(t) }
    static let span:Float = 0.86

    static func yaw(_ aspect:Float) -> Float {
        let f = min(1,max(0,(aspect-0.6)/0.72))
        return 0.118*(1-f*f*(3-2*f))
    }
    static func slope(_ uv:SIMD2<Float>, aspect:Float) -> SkyPoint {
        .init((uv.x-0.5)*span*aspect + yaw(aspect),0.102+(1-uv.y)*span,1)
    }
    func space(_ u:Float,_ v:Float,_ depth:Float) -> SkyPoint { Self.slope(.init(u,v),aspect:aspect)*depth }
    func world(_ p:SkyPoint) -> SkyPoint { origin + basis*(p*unit) }
    func local(_ p:SkyPoint) -> SkyPoint { basis.transpose*(p-origin)/unit }
    mutating func place(_ u:Float,_ v:Float,_ depth:Float,_ size:Float,_ turn:Float = 0) {
        origin = space(u,v,depth); unit = depth * Self.span * size
        basis = Self.rotation(.init(0,turn,0))
    }
    static func rotation(_ a:SkyPoint) -> simd_float3x3 {
        let qx = simd_quatf(angle:a.x,axis:.init(1,0,0)), qy = simd_quatf(angle:a.y,axis:.init(0,1,0))
        return simd_float3x3(simd_quatf(angle:a.z,axis:.init(0,0,1))*qy*qx)
    }
    mutating func part(_ shape:SeasonalShape,_ p:SkyPoint,_ s:SkyPoint,_ ink:SkyPoint,
                       _ rot:SkyPoint = .zero,_ glow:Float = 0,_ finish:SeasonalFinish = .matte) {
        primitive(shape,p,s,ink,Self.rotation(rot),glow,finish)
    }
    mutating func primitive(_ shape:SeasonalShape,_ p:SkyPoint,_ s:SkyPoint,_ ink:SkyPoint,
                            _ r:simd_float3x3,_ glow:Float,_ finish:SeasonalFinish) {
        let shape:SeasonalShape = shape == .globe && simd_reduce_max(s)<0.042 ? .bead : shape
        let m = basis*r, scales = simd_max(s*unit,SkyPoint(repeating:0.00001))
        let count=finish.transmits ? (refractors[shape.rawValue]?.count ?? 0) : instances[shape.rawValue].count
        let seed = Float((count*37 + shape.rawValue*11) % 251)/251
        let item=SeasonalInstance(x:.init(m.columns.0*scales.x,0),y:.init(m.columns.1*scales.y,0),
            z:.init(m.columns.2*scales.z,0),center:.init(world(p),1),material:.init(ink,glow),
            extras:.init(Float(target.rawValue),Float(finish.rawValue),seed,0))
        if finish.transmits { refractors[shape.rawValue,default:[]].append(item) }
        else { instances[shape.rawValue].append(item) }
    }
    mutating func rod(_ a:SkyPoint,_ b:SkyPoint,_ r:Float,_ color:SkyPoint,_ glow:Float = 0,_ finish:SeasonalFinish = .bark) {
        let diff = b-a, len = simd_length(diff)
        guard len > 0.0001 else { return }
        primitive(.stem,(a+b)*0.5,.init(r,len*0.5,r),color,
                  simd_float3x3(simd_quatf(from:.init(0,1,0),to:diff/len)),glow,finish)
    }
    mutating func arc(_ a:SkyPoint,_ mid:SkyPoint,_ b:SkyPoint,_ r:Float,_ color:SkyPoint,_ n:Int = 8,
                      _ glow:Float = 0,_ finish:SeasonalFinish = .bark) {
        let d=b-a, len=simd_length(d); guard len>0.0001 else {return}
        let at=(a+b)*0.5
        let shape:SeasonalShape = n<=5 || r<0.009 ? .twig : .bough
        primitive(shape,at,.init(r,len*0.5,r),color,simd_float3x3(simd_quatf(from:.init(0,1,0),to:d/len)),glow,finish)
        let k=shape.rawValue, curvature=SIMD4<Float>(basis*((mid-at)*(0.5*unit)),1)
        if finish.transmits,let i=refractors[k]?.indices.last { refractors[k]?[i].curve=curvature }
        else { instances[k][instances[k].count-1].curve=curvature }
    }
    /// A muscle, grain, claw or fibre tapers in actual cross section instead of as a line.
    mutating func taper(_ a:SkyPoint,_ b:SkyPoint,_ width:Float,_ depth:Float,_ ink:SkyPoint,
                        _ finish:SeasonalFinish,_ kind:SeasonalShape = .limb) {
        let d=b-a, len=simd_length(d); guard len>0.0001 else {return}
        primitive(kind,(a+b)*0.5,.init(width,len*0.5,depth),ink,
                  simd_float3x3(simd_quatf(from:.init(0,1,0),to:d/len)),0,finish)
    }
    mutating func leaf(_ start:SkyPoint,_ tip:SkyPoint,_ width:Float,_ color:SkyPoint,_ roll:Float = 0,
                       _ shape:SeasonalShape = .leaf,_ finish:SeasonalFinish = .foliage) {
        let d = tip-start, l = simd_length(d)
        guard l > 0.001 else { return }
        let rot = simd_quatf(from:SkyPoint(0,1,0),to:d/l)*simd_quatf(angle:roll,axis:SkyPoint(0,1,0))
        let mesh:SeasonalShape = shape == .leaf && width<0.044 ? .leaflet : shape
        primitive(mesh,(tip+start)*0.5,.init(width,l*0.5,width*0.65),color,simd_float3x3(rot),0,finish)
    }
    mutating func lamp(_ p:SkyPoint,_ color:SkyPoint,_ power:Float) {
        light = .init(world(p),power*unit*unit); glowColor = color
    }
    /// An explicitly faced lamina is important for petals and primaries. A rotation about
    /// the growth axis alone does not keep an opening flower's corolla facing its pollinator.
    mutating func vane(_ root:SkyPoint,_ tip:SkyPoint,_ width:Float,_ normal:SkyPoint,
                       _ ink:SkyPoint,_ shape:SeasonalShape,_ finish:SeasonalFinish, rime:Float = 0) {
        let d=tip-root, len=simd_length(d); guard len>0.0001 else {return}
        let ay=d/len, cross=simd_cross(ay,normal)
        let ax=simd_length_squared(cross)>0.0001 ? simd_normalize(cross) : simd_normalize(simd_cross(ay,SkyPoint(0,1,0.1)))
        primitive(shape,(root+tip)*0.5,.init(width,len*0.5,0.65*width),ink,
                  .init(columns:(ax,ay,simd_cross(ax,ay))),0,finish)
        if shape == .blade {
            // Long grass bends by its length, not its width. Preserve that arch in the
            // shadow and reflection cameras as well as in the visible silhouette.
            let i=instances[shape.rawValue].count-1
            let arch=SkyPoint(-d.x*0.085,len*0.17,0.035*len*sin(root.x*7))
            instances[shape.rawValue][i].curve = .init(basis*(arch*unit),1)
            instances[shape.rawValue][i].extras.w=rime
        }
    }
    static func noise(_ i:Int) -> Float {
        let n = sin(Float(i)*127.1+9.7)*4358.123
        return n-floor(n)
    }
}
