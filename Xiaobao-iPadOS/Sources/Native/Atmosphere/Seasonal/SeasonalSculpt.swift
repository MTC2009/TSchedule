import simd

/// Object-space surfaces. Anatomical cross sections join the head, neck and trunk into one skin;
/// poseable limbs, ear cartilage and individual flight feathers remain separate moving parts.
enum SeasonalSculpt {
    typealias Section = SIMD4<Float> // longitudinal position, spine height, vertical and lateral radius
    static let hare:[Section] = [
        .init(-0.97,0.17,0.015,0.021),.init(-0.91,0.155,0.085,0.10),.init(-0.81,0.18,0.131,0.165),
        .init(-0.70,0.242,0.186,0.175),.init(-0.58,0.26,0.221,0.194),.init(-0.46,0.225,0.205,0.180),
        .init(-0.36,0.114,0.169,0.148),.init(-0.25,0.065,0.229,0.189),.init(-0.09,0.042,0.263,0.222),
        .init(0.13,0.041,0.279,0.229),.init(0.34,0.076,0.312,0.250),.init(0.53,0.077,0.312,0.255),
        .init(0.67,0.061,0.258,0.208),.init(0.77,0.053,0.161,0.145),.init(0.81,0.071,0.010,0.012)]
    static let bird:[Section] = [
        .init(-0.44,-0.048,0.012,0.013),.init(-0.34,-0.033,0.066,0.067),.init(-0.23,-0.017,0.124,0.110),
        .init(-0.07,-0.002,0.18,0.155),.init(0.08,0.012,0.191,0.170),.init(0.17,0.055,0.172,0.151),
        .init(0.217,0.123,0.148,0.131),.init(0.295,0.148,0.136,0.124),.init(0.376,0.146,0.093,0.088),
        .init(0.417,0.13,0.040,0.050),.init(0.433,0.13,0.014,0.018)]
    static let deer:[Section] = [
        .init(-0.41,0.04,0.038,0.046),.init(-0.345,0.036,0.137,0.107),.init(-0.25,0.027,0.175,0.142),
        .init(-0.10,0.017,0.144,0.117),.init(0.04,0.014,0.16,0.129),.init(0.135,0.045,0.189,0.138),
        .init(0.205,0.130,0.153,0.090),.init(0.245,0.222,0.111,0.064),.init(0.286,0.302,0.071,0.060),
        .init(0.343,0.340,0.085,0.078),.init(0.40,0.337,0.075,0.069),.init(0.462,0.314,0.057,0.047),
        .init(0.524,0.288,0.036,0.043),.init(0.547,0.289,0.023,0.032)]
    static let carving:[Section] = [
        .init(-0.18,-0.06,0.016,0.022),.init(-0.12,-0.041,0.068,0.073),.init(-0.07,0,0.093,0.096),
        .init(0.014,0.031,0.12,0.119),.init(0.080,0.049,0.099,0.113),.init(0.14,0.035,0.069,0.098),
        .init(0.20,0.021,0.042,0.076),.init(0.254,0.038,0.049,0.078),.init(0.291,0.063,0.041,0.069),.init(0.312,0.061,0.011,0.016)]
    static let insect:[Section] = [
        .init(-0.263,0,0.003,0.002),.init(-0.23,0,0.084,0.048),.init(-0.15,0,0.138,0.086),
        .init(-0.058,0,0.154,0.103),.init(0.02,0,0.147,0.102),.init(0.087,0,0.123,0.089),
        .init(0.11,0,0.105,0.082),.init(0.157,0,0.113,0.068),.init(0.18,0,0.092,0.06),
        .init(0.199,0,0.062,0.047),.init(0.24,0,0.072,0.048),.init(0.264,0,0.025,0.022)]
    static func profile(_ sections:[Section],_ u:Float,_ v:Float) -> SkyPoint {
        let t=min(1,max(0,v))*Float(sections.count-1), i=min(sections.count-2,Int(t)), f=t-Float(i)
        let a=sections[max(i-1,0)],b=sections[i],c=sections[i+1],d=sections[min(i+2,sections.count-1)]
        let t2=f*f, t3=t2*f
        let h=b*(2*t3-3*t2+1)+c*(3*t2-2*t3)
        let k=(c-a)*(0.5*(t3-2*t2+f))+(d-b)*(0.5*(t3-t2))
        let s=h+k, theta=2*Float.pi*u
        // Pin the poles. The last small cross section otherwise leaves a hole on the muzzle.
        let cap=min(1, min(t,Float(sections.count-1)-t)*6)
        return SkyPoint(s.x,s.y+max(0,s.z)*cos(theta)*cap,-max(0,s.w)*sin(theta)*cap)
    }

    static func lamina(_ kind:SeasonalShape,_ u:Float,_ v:Float)->SkyPoint {
        let a=u*2*Float.pi,y=2*v-1, w=cos(a), s=sin(a), v0=min(1,max(0,v))
        let arch=max(0,sin(.pi*v0))
        if kind == .pad {
            // A lotus pad has a radial basin and a curled notch; the second hemisphere closes its rim.
            let r=sin(.pi*v0), theta = a + 0.07*sin(4*a)
            let notch = 1-0.24*pow(max(0,cos(theta-0.53)),54)
            return .init(r*cos(theta)*notch,0.16*r*r+0.039*r*r*sin(11*theta+0.35)+0.038*cos(.pi*v0),r*sin(theta)*notch)
        }
        var width:Float, cup:Float, archZ:Float, thickness:Float, turn:Float
        switch kind {
        case .ear:
            width=pow(arch,0.68)*(0.88+0.19*v); cup=0.86*w*w-0.35; archZ=0.18*y*y
            thickness=0.15; turn=0.15*v
        case .petal:
            width=pow(arch,0.57)*(0.65+0.68*v); cup=0.65*w*w
            archZ=0.62*v*v-0.16*sin(2 * .pi*v); thickness=0.058; turn=0.18*y
        case .feather,.wing:
            width=pow(arch,0.78)*(1.16-0.40*v)*(0.94+0.20*w)
            cup=0.27*w*w; archZ=0.32*v*v; thickness=0.056; turn=0.19*y
        case .blade:
            width=pow(arch,0.78)*(1.30-0.60*v); cup = -0.42*abs(w)
            archZ=0.96*v*v; thickness=0.044; turn=0.58*v
        default:
            let teeth=0.973+0.027*cos(25 * Float.pi*v+2.5*w)
            width=pow(arch,0.85)*(1.21-0.37*v)*(0.98+0.08*w)*teeth
            cup=0.33*abs(w)-0.17*exp(-9*abs(w)); archZ=0.50*v*v-0.14*sin(v*4)
            thickness=0.067; turn=0.38*v-0.18
        }
        let x=width*w,z=archZ+width*(s*thickness+cup)+0.07*width*w*sin(14*v+w)
        return .init(x*cos(turn)-z*sin(turn),y,x*sin(turn)+z*cos(turn))
    }
}

extension SeasonalMeshAtlas.Mesh {
    mutating func body(_ shape:SeasonalShape) {
        let rows = shape == .dragonHead ? SeasonalSculpt.carving : shape == .hare ? SeasonalSculpt.hare : (shape == .stag ? SeasonalSculpt.deer : (shape == .beetle ? SeasonalSculpt.insect : SeasonalSculpt.bird))
        grid(shape == .hare ? 64 : 40,(rows.count-1)*6) { SeasonalSculpt.profile(rows,$0,$1) }
    }
    /// A seated paddler's upper body, neck, jaw and scalp are one loft. Chest and shoulder
    /// widths are different in profile; near the ear the silhouette narrows into the neck.
    mutating func paddler() {
        let sections:[SIMD4<Float>] = [
            .init(-0.065,0,0.064,0.071),.init(0.004,0,0.072,0.077),.init(0.052,-0.014,0.067,0.072),
            .init(0.105,-0.009,0.075,0.083),.init(0.144,0.004,0.068,0.096),.init(0.161,0.008,0.054,0.083),
            .init(0.175,0.016,0.029,0.036),.init(0.197,0.022,0.027,0.030),.init(0.203,0.040,0.039,0.035),
            .init(0.221,0.036,0.051,0.045),.init(0.244,0.030,0.055,0.049),.init(0.271,0.028,0.053,0.049),
            .init(0.289,0.024,0.043,0.041),.init(0.306,0.023,0.005,0.006)]
        grid(40,78) { u,v in
            let p=SeasonalSculpt.profile(sections,u,v)
            return .init(p.y,p.x,p.z)
        }
        // Swapping axes changes handedness; normals, unlike two-sided coverage, must be corrected.
        for i in vertices.indices {vertices[i].normalV.x *= -1;vertices[i].normalV.y *= -1;vertices[i].normalV.z *= -1}
    }
    /// Deterministic groom on the actual skin. Each guard-hair tuft is a tiny tapered
    /// three-sided solid, so it affects silhouette, depth, transmitted light and picking.
    mutating func coat() {
        for i in 0..<3700 {
            let u=SeasonalScene.noise(i*3+17),v=0.022+0.951*SeasonalScene.noise(i*7+11)
            let at=SeasonalSculpt.profile(SeasonalSculpt.hare,u,v)
            let du=SeasonalSculpt.profile(SeasonalSculpt.hare,u+0.0008,v)-at
            let dv=SeasonalSculpt.profile(SeasonalSculpt.hare,u,v+0.0008)-at
            let n=simd_normalize(simd_cross(dv,du)), side=simd_normalize(du)
            guard n.x.isFinite,side.x.isFinite else {continue}
            let q=SeasonalScene.noise(i*11+33),r:Float = 0.0021+0.0024*q
            let flow=simd_normalize(simd_normalize(dv)+n*(0.37+0.49*q))
            let length:Float = (0.014+0.023*q)*(v<0.37 ? 0.63 : 1)
            let root=at-n*r*0.85, tip=root+flow*length, mid=root+flow*length*0.57+n*r*0.75
            let start=UInt32(vertices.count),rad=simd_normalize(simd_cross(flow,side))
            for j in 0..<3 {
                let a=2*Float.pi*Float(j)/3, rim=side*cos(a)+rad*sin(a)
                let normal=simd_normalize(n+rim*0.36)
                vertices.append(.init(position:root+rim*r,normal:normal,uv:.init(u,v)))
                vertices.append(.init(position:mid+rim*r*0.50,normal:normal,uv:.init(u,v)))
            }
            vertices.append(.init(position:tip,normal:n,uv:.init(u,v)))
            for j in 0..<3 {
                let a=start+UInt32(j*2),b=start+UInt32((j+1)%3*2)
                indices += [a,b,a+1,b,b+1,a+1,a+1,b+1,start+6]
            }
        }
    }
    mutating func beveledBox() {
        let edge:[Float]=[-1,-0.993,-0.973,-0.945,0.945,0.973,0.993,1]
        for face in 0..<6 {
            let start=UInt32(vertices.count)
            for v in edge { for u in edge {
                let p:SkyPoint
                switch face { case 0:p = .init(1,v,u);case 1:p = .init(-1,v,-u)
                case 2:p = .init(u,1,v);case 3:p = .init(u,-1,-v)
                case 4:p = .init(-u,v,1);default:p = .init(u,v,-1) }
                let c=simd_clamp(p,SkyPoint(repeating:-0.945),SkyPoint(repeating:0.945))
                let n=simd_normalize(p-c)
                vertices.append(.init(position:c+n*0.055,normal:n,uv:.init((u+1)/2,(v+1)/2)))
            }}
            for j in 0..<(edge.count-1) { for i in 0..<(edge.count-1) {
                let a=start+UInt32(j*edge.count+i), b=a+UInt32(edge.count)
                indices += [a,b,b+1,a,b+1,a+1]
            }}
        }
    }
    mutating func roof() {
        // A pitched tiled roof with lifted gable corners, bowed eaves and a dark soffit.
        grid(72,48) { u,v in
            let x=2*u-1, a=2*Float.pi*v, z=cos(a)
            let eave=0.16*pow(abs(x),4)*abs(z), h=pow(max(0,1-abs(z)),1.43)
            return .init(x,h+eave+0.024*cos(22*Float.pi*x)*abs(z)+(sin(a)>0 ? 0.08 : -0.10),z)
        }
    }
    mutating func vessel() {
        let profile:[SIMD2<Float>] = [.init(0,-1),.init(0.42,-0.99),.init(0.46,-0.86),.init(0.61,-0.74),
            .init(0.86,-0.32),.init(0.97,0.56),.init(1,0.89),.init(0.973,1),.init(0.906,0.94),.init(0.84,0.34),.init(0.64,-0.51),.init(0,-0.57)]
        grid(48,55) { u,v in
            let g=min(1,max(0,v))*Float(profile.count-1),i=min(profile.count-2,Int(g)),f=g-Float(i)
            let p=profile[i]+(profile[i+1]-profile[i])*f,a=u*2*Float.pi
            return .init(p.x*cos(a),p.y,p.x*sin(a))
        }
    }
}

extension SeasonalMeshAtlas.Mesh {
    /// Branchlets and diverging silk awns share one mesh, built once even for a whole reed bed.
    mutating func plume() {
        func line(_ a:SkyPoint,_ b:SkyPoint,_ bend:SkyPoint,_ r:Float,_ end:Float) {
            let d=simd_normalize(b-a),axis=abs(d.y)>0.8 ? SkyPoint(1,0,0) : SkyPoint(0,1,0)
            let x=simd_normalize(simd_cross(d,axis)),z=simd_cross(x,d),first=UInt32(vertices.count)
            for i in 0...2 { let f=Float(i)/2
                let p=a+(b-a)*f+bend*(4*f*(1-f)),w=r+(end-r)*f
                for j in 0..<4 {
                    let angle=Float(j)*Float.pi/2,n=x*cos(angle)+z*sin(angle)
                    vertices.append(.init(position:p+n*w,normal:n,uv:.init(Float(j)/4,f)))
                }
            }
            for i in 0..<2 { for j in 0..<4 {
                let k=first+UInt32(i*4+j),m=first+UInt32(i*4+(j+1)%4)
                indices += [k,m,k+4,m,m+4,k+4]
            }}
        }
        line(.init(0,-1,0),.init(0.14,0.94,0.045),.init(-0.1,0,0),0.036,0.009)
        for j in 0..<24 {
            let f=Float(j)/24, angle=Float(j)*2.39996,axis=SkyPoint(cos(angle),0,sin(angle))
            let base=SkyPoint(0.13*f,-0.91+1.67*f,0),reach=(0.27+0.72*sin(.pi*f))*(0.70+0.30*SeasonalScene.noise(j+20))
            let tip=base+axis*reach+SkyPoint(0,0.49+0.12*f,0)
            line(base,tip,axis*0.053,0.023,0.006)
            for k in 1...6 {
                let v=Float(k)/6,p=base+(tip-base)*v, wing=SkyPoint(-axis.z,0,axis.x)
                for side:Float in [-1,1] {
                    let seed=p+wing*(side*(0.07+0.07*f))+SkyPoint(0,0.075,0)
                    line(p,seed,.zero,0.024,0.010)
                    for h in 0..<3 {
                        let lean=SeasonalScene.noise(j*53+k*5+h)
                        let end=seed+axis*(0.04+0.23*lean)+wing*(side*(0.046+0.14*lean))+SkyPoint(0,0.14+0.19*lean,0)
                        line(seed,end,axis*0.034,0.0085,0.0018)
                    }
                }
            }
        }
    }
}

extension SeasonalMeshAtlas.Mesh {
    /// Cross sections along a bent limb, including a continuous joint and foot.
    /// Rotating this skin at its buried root avoids the pinched ends of joined ellipsoids.
    mutating func leg(_ shape:SeasonalShape) {
        typealias S=SIMD4<Float>
        let sections:[S]
        switch shape {
        case .hareHindleg:
            sections=[.init(0,0,0.014,0.019),.init(-0.02,-0.062,0.150,0.104),.init(-0.097,-0.163,0.158,0.101),
                .init(-0.145,-0.269,0.100,0.082),.init(-0.072,-0.31,0.076,0.069),.init(0.101,-0.344,0.080,0.065),
                .init(0.239,-0.36,0.047,0.050),.init(0.312,-0.372,0.038,0.044),.init(0.417,-0.394,0.054,0.060),
                .init(0.496,-0.41,0.041,0.049),.init(0.55,-0.412,0.006,0.013)]
        case .hareForeleg:
            sections=[.init(0,0,0.018,0.019),.init(0.01,-0.067,0.094,0.071),.init(0.052,-0.16,0.071,0.062),
                .init(0.060,-0.22,0.050,0.052),.init(-0.031,-0.254,0.043,0.050),.init(-0.196,-0.277,0.035,0.034),
                .init(-0.266,-0.283,0.029,0.034),.init(-0.361,-0.294,0.044,0.052),.init(-0.433,-0.296,0.010,0.016)]
        default:
            let hind:Float=shape == .deerHindleg ? 1 : -1
            sections=[.init(0,0,0.013,0.012),.init(-0.02*hind,-0.046,0.056,0.050),
                .init(-0.058*hind,-0.122,0.045,0.041),.init(-0.076*hind,-0.154,0.031,0.033),
                .init(0.012*hind,-0.214,0.020,0.020),.init(0.121*hind,-0.266,0.022,0.024),
                .init(0.14*hind,-0.29,0.015,0.015),.init(0.16*hind,-0.342,0.018,0.019),
                .init(0.19*hind+0.018,-0.357,0.022,0.022),.init(0.19*hind+0.043,-0.37,0.004,0.007)]
        }
        func section(_ v:Float)->S {
            let g=min(1,max(0,v))*Float(sections.count-1),i=min(sections.count-2,Int(g)),f=g-Float(i)
            let a=sections[max(0,i-1)],b=sections[i],c=sections[i+1],d=sections[min(i+2,sections.count-1)]
            let f2=f*f,f3=f*f*f
            return b*(2*f3-3*f2+1)+c*(3*f2-2*f3)+(c-a)*(0.5*(f3-2*f2+f))+(d-b)*(0.5*(f3-f2))
        }
        grid(32,(sections.count-1)*5) { u,v in
            let k=section(v), g=section(v+0.001)-section(v-0.001),len=max(0.00001,sqrt(g.x*g.x+g.y*g.y))
            let tangent=SkyPoint(g.x/len,g.y/len,0), side=SkyPoint(-tangent.y,tangent.x,0)
            let a=2*Float.pi*u, cap=min(1,min(v,1-v)*90)
            return SkyPoint(k.x,k.y,0)+side*(k.z*cos(a)*cap)+SkyPoint(0,0,-k.w*sin(a)*cap)
        }
    }
}

extension SeasonalMeshAtlas.Mesh {
    /// Overlapping irregular volumetric leaf clusters; even the treeline has a back side.
    mutating func crown() {
        for j in 0..<26 {
            let f=Float(j),angle=f*2.39996, level=(f+0.5)/26
            let r=pow(sin(.pi*level),0.67)*(0.46+0.24*SeasonalScene.noise(j+7))
            let center=SkyPoint(cos(angle)*r,-0.63+1.44*level,sin(angle)*r)
            let size=0.24+0.24*SeasonalScene.noise(j+32)
            grid(12,9) { u,v in
                let a=u*2 * .pi,b=(v-0.5) * .pi,n=SkyPoint(cos(b)*cos(a),sin(b),cos(b)*sin(a))
                let br=0.93+0.13*sin(9*n.x+f)*cos(11*n.z-6*n.y)+0.07*cos(15*n.y+f)
                return center+n*size*br
            }
        }
    }
}

extension SeasonalMeshAtlas.Mesh {
    /// The longitude wraps around both sides and the rim. The centerline, not
    /// a stack of flat alpha cards, describes how each petal rolls out of the cup.
    mutating func sculptedLamina(_ shape: SeasonalShape) {
        grid(42,36) { u,v in
            let a=2*Float.pi*u, w=cos(a), side=sin(a), y=2*v-1
            let arch=max(0.00002,sin(.pi*v))
            if shape == .paddleBlade {
                let breadth=pow(arch,0.34)*(0.42+0.55*v)+0.055*(1-v)
                return .init(w*breadth,y,side*breadth*(0.15+0.09*(1-abs(w))))
            }
            let breadth=pow(arch,0.65)*(0.67+0.77*v)*(1+0.038*w*(2*v-1))
            let margin=abs(w)*abs(w), fold=0.034*sin(13*w+1.4*v)*margin*arch
            let z = -0.57*arch + 0.14*sin(2 * .pi*v) + breadth*(0.74*margin+0.044*side+fold)
            return .init(w*breadth+0.064*v*arch,y,z)
        }
    }
}
