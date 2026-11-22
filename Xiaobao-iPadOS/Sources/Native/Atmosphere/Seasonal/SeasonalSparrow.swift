import simd

/// Rest space of the perched sparrow. Y is up; the bill points to −X. The skin, follicles,
/// orbital rims and toes all have physical locations even on the side away from the camera.
enum SeasonalSparrow {
    static let eyeCenter=SIMD2<Float>(-0.385,0.474)
    static let billLift:Float=0.055
    // Height, anterior contour, posterior contour, half breadth. The throat has a slight
    // indentation below the mandible; the keel sits forward of the pointed rump.
    private static let rings:[SIMD4<Float>] = [
        .init(-0.213,-0.009,0.043,0.008), .init(-0.202,-0.105,0.119,0.066),
        .init(-0.166,-0.211,0.201,0.144), .init(-0.111,-0.301,0.290,0.194),
        .init(-0.073,-0.352,0.397,0.217), .init(-0.039,-0.386,0.478,0.228),
        .init(-0.006,-0.421,0.463,0.242), .init(0.059,-0.457,0.398,0.250),
        .init(0.133,-0.487,0.326,0.247), .init(0.197,-0.500,0.253,0.235),
        .init(0.259,-0.491,0.182,0.214), .init(0.312,-0.470,0.127,0.198),
        .init(0.350,-0.464,0.084,0.185), .init(0.394,-0.480,0.021,0.174),
        .init(0.440,-0.477,-0.026,0.165), .init(0.488,-0.449,-0.098,0.151),
        .init(0.532,-0.402,-0.154,0.124), .init(0.566,-0.341,-0.204,0.080),
        .init(0.580,-0.281,-0.273,0.005)]
    static func height(_ v:Float)->Float { -0.213+0.793*(0.5-0.5*cos(.pi*min(1,max(0,v)))) }
    static func ring(_ y:Float)->SkyPoint {
        var a=0, b=rings.count-1
        while b-a>1 {let m=(a+b)/2; if y < rings[m].x {b=m} else {a=m}}
        let p=rings[a], q=rings[b], before=rings[max(0,a-1)], after=rings[min(rings.count-1,b+1)]
        let span=q.x-p.x, f=max(0,min(1,(y-p.x)/span)), f2=f*f, f3=f2*f
        let lift=(q-before)*(span*(f3-2*f2+f)/(q.x-before.x))
        let fall=(after-p)*(span*(f3-f2)/(after.x-p.x))
        let r=p*(2*f3-3*f2+1)+q*(3*f2-2*f3)+lift+fall
        return .init(r.y,r.z,r.w)
    }
    static func skin(_ angle:Float,_ y:Float)->SkyPoint {
        let r=ring(y), c=cos(angle)
        return .init((r.x+r.y+(r.y-r.x)*c)*0.5,y,r.z*sin(angle)*(1-0.14*c))
    }
    static func girth(_ x:Float,_ y:Float)->Float {
        let r=ring(y), c=max(-1,min(1,(2*x-r.x-r.y)/max(0.0001,r.y-r.x)))
        return r.z*sqrt(max(0,1-c*c))*(1-0.14*c)
    }
    static func normal(_ a:Float,_ y:Float)->SkyPoint {
        simd_normalize(simd_cross(skin(a,y+0.0006)-skin(a,y-0.0006),skin(a+0.004,y)-skin(a-0.004,y)))
    }
    static func orbit(_ side:Float)->(center:SkyPoint,axes:simd_float3x3) {
        let x=eyeCenter.x,y=eyeCenter.y,r=ring(y)
        let a=side*acos((2*x-r.x-r.y)/(r.y-r.x)), n=normal(a,y)
        let forward=simd_normalize(SkyPoint(1,0,0)-n*n.x)
        return (skin(a,y)-n*0.014,.init(columns:(forward,simd_cross(n,forward),n)))
    }
    static func twig(_ t:Float)->SkyPoint {
        .init(-0.060+0.39*t+0.023*sin(3.1*t),-0.316+0.57*t+0.022*sin(2.2*t),
              0.018+0.48*t+0.024*(1-cos(3.3*t)))
    }
    static func radius(_ t:Float)->Float {max(0.012,0.0205-0.009*t+0.0018*cos(4*t))}
    /// The exact same radial frame is used to sweep bark and to wrap all eight digits.
    static func radial(_ t:Float,_ a:Float)->SkyPoint {
        let d=simd_normalize(twig(t+0.001)-twig(t-0.001)), up=simd_normalize(SkyPoint(0,1,0)-d*d.y)
        return up*cos(a)+simd_normalize(simd_cross(d,up))*sin(a)
    }
    static func contact(_ t:Float,_ a:Float,_ clearance:Float)->SkyPoint {
        twig(t)+radial(t,a)*(radius(t)+clearance)
    }
}

extension SeasonalScene {
    mutating func perchedSparrow() {
        let previous=basis
        // Fixed pitch of this perch in the world. A view from the reverse side sees
        // the other wing and hallux; nothing is rotated to face the viewer.
        basis=basis*Self.rotation(.init(-0.44,0.46,0))
        let scale=SkyPoint(repeating:1), pose=lift
        target = .none
        part(.sparrowPerch,.zero,scale,C.twig,.zero,0,.winterTwig)
        target = .subject
        part(.sparrowFoot,.zero,scale,C.rose,.zero,0,.sparrowTarsus)
        let crouch=SkyPoint(-0.006*pose,-0.035*pose,0)
        let bodyScale=SkyPoint(1+0.014*pose,1-0.014*pose,1+0.068*pose)
        part(.sparrowSkin,crouch,bodyScale,C.chalk,.zero,0,.sparrowDown)
        for shape:SeasonalShape in [.sparrowContour,.sparrowWing] {
            part(shape,crouch,bodyScale,C.umber,.zero,0,.sparrowVane)
            let last=instances[shape.rawValue].count-1
            instances[shape.rawValue][last].curve.w = -pose
        }
        part(.sparrowBill,crouch,bodyScale,C.umber,.zero,0,.sparrowHorn)
        for side:Float in [-1,1] {
            let e=SeasonalSparrow.orbit(side)
            let eye=simd_float3x3(diagonal:bodyScale)*e.axes
            primitive(.globe,crouch+e.center*bodyScale,.init(0.033,0.028,0.029),C.ink,eye,0,.cornea)
        }
        // Focus just inside the near wing, not on the twig or distant trees.
        focusZ=world(.init(-0.13,0.19,-0.13)).z
        basis=previous
    }
}

extension SeasonalMeshAtlas.Mesh {
    /// A narrow, continuously swept solid. Radius and longitudinal UVs taper across
    /// the knuckles and nail rather than meeting as capped cylinders.
    private mutating func sparrowTube(_ steps:Int,_ sides:Int,_ role:Int,
        _ path:(Float)->SkyPoint,_ width:(Float)->Float) {
        let start=UInt32(vertices.count)
        for i in 0...steps {
            let t=Float(i)/Float(steps), p=path(t), d=simd_normalize(path(min(1,t+0.001))-path(max(0,t-0.001)))
            let ref=abs(d.y)<0.84 ? SkyPoint(0,1,0) : SkyPoint(1,0,0)
            let a=simd_normalize(simd_cross(d,ref)), b=simd_cross(a,d)
            for j in 0...sides {
                let u=Float(j)/Float(sides),n=a*cos(2 * .pi*u)+b*sin(2 * .pi*u)
                vertices.append(.init(position:p+n*width(t),normal:n,uv:.init(u,Float(role)*2+t)))
            }
        }
        sparrowStrip(start,sides,steps)
    }
    mutating func sparrowStrip(_ start:UInt32,_ cols:Int,_ rows:Int) {
        let step=UInt32(cols+1)
        for j in 0..<rows { for i in 0..<cols {
            let a=start+UInt32(j*(cols+1)+i),b=a+step
            indices += [a,b,b+1,a,b+1,a+1]
        }}
    }
    mutating func sparrowPerch() {
        typealias S=SeasonalSparrow
        grid(20,110) {u,v in
            let t = -2.8+3.38*v,a = -u*2 * .pi
            let w=S.radius(t)*(1+0.032*sin(5*a+1.3*t)+0.021*cos(9*a-4*t))
            return S.twig(t)+S.radial(t,a)*w
        }
        // A dormant leaf scar and lateral spur are attached to the same living stem.
        for (t,reach) in [(-0.64,Float(0.18)),(-1.54,0.29)] {
            let p=S.twig(Float(t)), end=p+SkyPoint(-reach,reach*0.39,reach*0.37)
            sparrowTube(13,10,0,{f in p+(end-p)*f+SkyPoint(-0.013,0.018,0)*sin(.pi*f)},
                        {0.011*(1-$0)+0.0015})
        }
    }
    mutating func sparrowFoot() {
        typealias S=SeasonalSparrow
        for side:Float in [-1,1] {
            let t:Float=side<0 ? -0.060 : 0.135
            let heel=S.contact(t,-0.13,0.009)
            let ankle=SkyPoint(0.068+side*0.018,-0.143,side*0.086)
            sparrowTube(21,13,0,{f in ankle+(heel-ankle)*f+SkyPoint(0.008,0.006,side*0.007)*sin(.pi*f)},
                        {f in 0.0094+0.0038*pow(1-f,3)+0.0026*f*f})
            for j in 0..<4 {
                let hallux=j==3, spread:Float=hallux ? -0.077 : Float(j-1)*0.092+0.059
                let arc:Float=(hallux ? -1.0 : 1.0)*(hallux ? 2.01 : 1.92+Float(j%2)*0.46)
                func digit(_ f:Float)->SkyPoint {
                    let station=t+spread*f
                    let arch:Float=hallux ? 0.022 : (j==2 ? 0.013 : 0.005)
                    return S.contact(station,-0.13+arc*f,0.0062+arch*sin(.pi*f)+0.0021*cos(4 * .pi*f))
                }
                sparrowTube(21,10,1,digit,{f in 0.0072*(1-0.36*f)+0.0011*cos(4 * .pi*f)})
                sparrowTube(12,9,2,{f in
                    S.contact(t+spread*(1+0.24*f),-0.13+arc*(1+0.46*f),0.0077-0.0075*f*f)
                },{f in 0.0044*pow(1-f,0.75)+0.00016})
            }
        }
    }
    mutating func sparrowBill() {
        // Broad-based seed bill: arched culmen and flatter cutting surfaces meet at a
        // dark commissure. The lower mandible has neither the depth nor color of the upper.
        for lower in [false,true] {
            let start=UInt32(vertices.count)
            for i in 0...28 { for j in 0...36 {
                let t=Float(i)/28,u=Float(j)/36, a=2 * Float.pi*u
                let c=cos(a),sn=sin(a),f=pow(max(0.0004,1-t),0.84)
                let x = -0.443-0.142*t, join:Float=0.389-0.009*t-0.009*t*t
                let h:Float=lower ? (sn<0 ? 0.040 : 0.003) : (sn>=0 ? 0.046 : 0.003)
                let bevel:Float=lower ? -0.006*max(0,-sn) : 0.010*max(0,sn)
                let y=SeasonalSparrow.billLift+join+(lower ? -0.0035 : 0.0017)*f+h*sn*f+bevel*sin(.pi*t)
                let z=(lower ? 0.057 : 0.063)*c*f
                let n=simd_normalize(SkyPoint(-0.30,sn*(abs(sn)>0.03 ? 1.12 : 0.6),c))
                vertices.append(.init(position:.init(x,y,z),normal:n,uv:.init(u,(lower ? 2 : 0)+t)))
            }}
            sparrowStrip(start,36,28)
        }
        for side:Float in [-1,1] {
            // Short nasal bristles overlap the proximal horn, without hiding the cutting edge.
            for j in 0..<16 {
                let f=Float(j)/15,q=SeasonalScene.noise(j*31+7)
                let a=SkyPoint(-0.466-0.008*f,0.479-0.039*f,side*(0.014+0.046*f))
                let b=a+SkyPoint(-0.017-0.011*q,-0.006-0.009*f,side*0.0017)
                sparrowTube(4,4,5,{t in a+(b-a)*t+SkyPoint(0,0.002*sin(.pi*t),0)},
                            {0.0013*(1-$0)+0.00012})
            }
            let eye=SeasonalSparrow.orbit(side)
            // Upper and lower folds occlude the globe at the canthi. A ring drawn
            // around a whole exposed sphere reads like a glass bead on the cheek.
            for upper in [false,true] {
                let start=UInt32(vertices.count)
                for i in 0...6 {for j in 0...34 {
                    let f=Float(i)/6, x=2*Float(j)/34-1, opening=pow(max(0,1-x*x),0.70)
                    // Local +Y points upward only on the positive-Z flank.
                    let sign:Float=upper ? side : -side
                    let ey=sign*((upper ? 0.014 : 0.018)*opening+f*(0.013+0.008*opening))+side*x*0.0028
                    let ex=x*(0.032+0.009*f)
                    let sphere=max(0,1-(ex/0.033)*(ex/0.033)-(ey/0.028)*(ey/0.028))
                    let base:Float=0.009-0.004*f
                    let z=max(base,0.029*sqrt(sphere)+0.0015*(1-f))
                    let n=simd_normalize(eye.axes*SkyPoint(7*ex*(1-f),9*ey*(1-f),1))
                    vertices.append(.init(position:eye.center+eye.axes*SkyPoint(ex,ey,z),normal:n,
                                          uv:.init(Float(j)/34,(upper ? 6 : 8)+f)))
                }}
                sparrowStrip(start,34,6)
            }
        }
    }
}
