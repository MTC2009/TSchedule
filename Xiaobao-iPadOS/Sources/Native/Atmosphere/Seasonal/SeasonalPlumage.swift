import simd

/// Follicles grow on the skin; folded flight feathers follow a separate, convex wing
/// envelope. No feather is a billboard. Packed UVs carry identity, tract and shaft
/// coordinates without expanding the vertex layout for the rest of the shared atlas.
private enum SparrowTract:Int { case contour, rectrix, primary, secondary, tertial, greater, median, scapular, mantle, cushion }
private struct VaneRing { let p, across, normal:SkyPoint }

private enum SparrowFold {
    // Carpal joint to tip. Each double lobe has an inboard side against the rib cage
    // and a cambered outboard side under its feathers, including past the rump.
    static let x:[Float]=[-0.388,-0.340,-0.242,-0.120,0.015,0.169,0.296,0.401,0.502,0.563]
    static let section:[SIMD4<Float>]=[
        .init(0.241,0.004,0.124,0.004),.init(0.228,0.080,0.122,0.074),
        .init(0.207,0.121,0.128,0.091),.init(0.172,0.138,0.124,0.115),
        .init(0.137,0.150,0.117,0.123),.init(0.113,0.135,0.090,0.115),
        .init(0.080,0.101,0.076,0.091),.init(0.046,0.070,0.054,0.068),
        .init(0.017,0.043,0.029,0.038),.init(-0.011,0.003,0.015,0.003)]
    static func slice(_ at:Float)->SIMD4<Float> {
        var i=0
        while i<x.count-2 && at>x[i+1] {i+=1}
        let f=max(0,min(1,(at-x[i])/(x[i+1]-x[i]))),f2=f*f,f3=f2*f
        let a=section[max(0,i-1)],b=section[i],c=section[i+1],d=section[min(i+2,x.count-1)]
        let ends=b*(2*f3-3*f2+1)+c*(3*f2-2*f3)
        return ends+(c-a)*(0.5*(f3-2*f2+f))+(d-b)*(0.5*(f3-f2))
    }
    static func depth(_ x:Float,_ y:Float)->Float {
        let s=slice(x), h=(y-s.x)/max(0.003,s.y)
        let lobe=s.z+s.w*sqrt(max(0,1-h*h))
        // A wing root can disappear into back plumage, not emerge as a floating tab.
        return max(SeasonalSparrow.girth(x,y),lobe*max(0,1-max(0,abs(h)-1)*0.80))
    }
}

extension SeasonalMeshAtlas.Mesh {
    /// Banked, closed tail. Adjoining rectrices overlap across one cambered surface
    /// for their full length, with only the last few millimetres separating.
    private mutating func sparrowTail() {
        let rows=26, sides=14
        for j in 0..<12 {
            let lane=(Float(j)-5.5)/5.5, first=UInt32(vertices.count)
            for i in 0...rows {
                let t=Float(i)/Float(rows)
                let f=max(0.0004,min(1,min(t*13,(1-t)*11))), w=(0.018+0.008*t)*sqrt(f)
                let xc=0.259+(0.615-0.034*lane*lane)*t
                let zc=lane*(0.070-0.020*t)+0.019*t*t
                for k in 0...sides {
                    let a=2*Float.pi*Float(k)/Float(sides),c=cos(a),h=sin(a)
                    let z=zc+w*c
                    let bank:Float=0.50+0.16*t, bend:Float=0.028*sin(.pi*t)-0.018*t*t
                    let y = -0.021-0.170*t+bend-bank*z-1.71*z*z
                    // The central pair sits on top. Slight transverse twist makes
                    // broad overlapping webs, rather than a row of parallel wires.
                    let relief=(1-c*c)*0.0011+0.0013*h-abs(lane)*0.0115-lane*c*0.0028
                    let slope=(0.170-0.028*Float.pi*cos(.pi*t)+0.036*t+0.16*z)/0.61
                    let n=simd_normalize(SkyPoint(slope,1,bank+3.42*z+c*0.08))*(h >= -0.001 ? 1 : -1)
                    vertices.append(.init(position:.init(xc,y+relief,z),normal:n,
                        uv:.init(Float(4*(j+1)+2)+c,2+t)))
                }
            }
            sparrowStrip(first,sides,rows)
        }
    }
    /// The downy ends of body feathers are not coherent plates. Build a little
    /// branched fan of tapered, three-sided barb bundles on the continuous undercoat.
    private mutating func sparrowFan(_ id:Int,_ w:Float,_ path:(Float)->VaneRing) {
        let core=path(0.16), mid=path(0.61), apex=path(0.97)
        let axis=apex.p-core.p
        for k in 0..<13 {
            let s=Float(k)/6-1,noise=SeasonalScene.noise(id*29+k*43),n=core.normal
            let scale=w*(0.026+0.022*noise)
            let a=core.p+core.across*(w*s*0.09)-n*0.0014
            let b=mid.p+mid.across*(w*s*0.54)+mid.normal*(w*0.057)
            let split=0.45+0.61*noise
            let c=apex.p+apex.across*(s*w*split)+axis*(0.16*noise-0.12*abs(s))+apex.normal*(w*(0.055+0.11*noise))
            let i=UInt32(vertices.count),u=Float(id*4+2)+s
            for j in 0..<3 {
                let angle=Float(j)*2 * .pi/3, r=cos(angle),h=sin(angle)
                let rootOffset=(core.across*r+core.normal*h)*scale
                let midOffset=(mid.across*r+mid.normal*h)*scale*0.74
                vertices.append(.init(position:a+rootOffset,normal:simd_normalize(n+core.across*r*0.18),uv:.init(u,0.16)))
                vertices.append(.init(position:b+midOffset,normal:simd_normalize(mid.normal+mid.across*r*0.22),uv:.init(u,0.61)))
            }
            vertices.append(.init(position:c,normal:apex.normal,uv:.init(u,0.97)))
            for j in 0..<3 {
                let g=i+UInt32(2*j),h=i+UInt32(2*((j+1)%3))
                indices += [g,h,g+1,h,h+1,g+1,g+1,h+1,i+6]
            }
        }
    }
    private mutating func sparrowFeather(_ id:Int,_ tract:SparrowTract,_ width:Float,_ steps:Int,
                      conform:((SkyPoint,Float)->SkyPoint)? = nil,
                      _ path:(Float)->VaneRing) {
        let big=tract == .primary
        let sides=16, first=UInt32(vertices.count), seed=SeasonalScene.noise(id*11+3)
        for i in 0...steps {
            let t=Float(i)/Float(steps),r=path(t)
            let exponent:Float=big ? 0.49 : 0.52
            let base=pow(max(0.00025,sin(.pi*t)),exponent)
            // A narrow quill opens into an asymmetric vane; the fine tip is rounded,
            // not a diamond. Primaries have a genuinely narrower leading web.
            let w=width*base*(0.69+0.53*t)
            let shell=width*0.048*base
            for j in 0...sides {
                let a=2*Float.pi*Float(j)/Float(sides), c=cos(a),s=sin(a)
                let trim:Float = 0.017*pow(abs(c),4)*sin(39*t+7*seed+2*c)*t
                let flank:Float=big ? (c>0 ? 0.76 : 1.11) : (1+0.055*c)
                let camber=shell*(s+0.84*(1-c*c))
                let flat=r.p+r.across*(w*c*flank*(1+trim))
                let p=(conform?(flat,t) ?? flat)+r.normal*camber
                let n=simd_normalize(r.normal*(s>=0 || abs(s)<0.002 ? 1 : -1)+r.across*(c*0.20))
                vertices.append(.init(position:p,normal:n,uv:.init(Float(id*4+2)+c,Float(tract.rawValue*2)+t)))
            }
        }
        sparrowStrip(first,sides,steps)
        if [.primary,.secondary,.tertial,.greater,.median,.scapular,.mantle].contains(tract) {
            // Follow the mesh we just built, including its camber across the flank.
            // Sampling both sides of the vane avoids straight lines hovering above
            // a curved feather. Remaining subpixel barbules are filtered in Metal.
            func surface(_ t:Float,_ c:Float)->(SkyPoint,SkyPoint) {
                let row=t*Float(steps),col=acos(max(-1,min(1,c)))*Float(sides)/(2 * .pi)
                let i=min(steps-1,Int(row)),j=min(sides-1,Int(col)),h=row-Float(i),f=col-Float(j)
                let a=Int(first)+i*(sides+1)+j,b=a+sides+1
                func gather(_ va:SIMD4<Float>,_ vb:SIMD4<Float>,_ vc:SIMD4<Float>,_ vd:SIMD4<Float>)->SkyPoint {
                    let q=va*(1-f)*(1-h)+vb*f*(1-h)+vc*(1-f)*h+vd*f*h
                    return .init(q.x,q.y,q.z)
                }
                let va=vertices[a],vb=vertices[a+1],vc=vertices[b],vd=vertices[b+1]
                return (gather(va.positionU,vb.positionU,vc.positionU,vd.positionU),
                        simd_normalize(gather(va.normalV,vb.normalV,vc.normalV,vd.normalV)))
            }
            let count=big ? 66 : (tract == .tertial || tract == .secondary ? 54 : 26)
            for j in 1...count {
                for side:Float in [-1,1] {
                    let q=SeasonalScene.noise(id*41+j*11+(side>0 ? 31 : 0))
                    let root=0.17+0.70*(Float(j)+0.51*q)/Float(count)
                    let adv:Float=(big ? 0.076 : 0.121)*(0.73+0.47*q)
                    let start=surface(root,side*0.065),mid=surface(root+adv*0.37,side*0.49)
                    let end=surface(root+adv,side*(0.83+0.16*q))
                    let ax=simd_normalize(simd_cross(mid.1,end.0-start.0))
                    let radius=width*(0.009+0.009*q), lift=width*0.006
                    let index=UInt32(vertices.count), tractV=Float(2*(tract.rawValue+12))
                    for (v,t,c) in [(start,root,side*0.065),(mid,root+adv*0.37,side*0.49),(end,root+adv,side*0.96)] {
                        let u=Float(id*4+2)+c
                        vertices.append(.init(position:v.0+v.1*lift-ax*radius,normal:v.1,uv:.init(u,tractV+t)))
                        vertices.append(.init(position:v.0+v.1*(lift+radius),normal:simd_normalize(v.1-ax*0.22),uv:.init(u,tractV+t)))
                        vertices.append(.init(position:v.0+v.1*lift+ax*radius,normal:simd_normalize(v.1+ax*0.22),uv:.init(u,tractV+t)))
                    }
                    for k in 0..<2 {for l in 0..<3 {
                        let a=index+UInt32(k*3+l),b=index+UInt32(k*3+(l+1)%3)
                        indices += [a,b,a+3,b,b+3,a+3]
                    }}
                }
            }
        }
        // A few free barbs extend beyond the joined web. They have triangular
        // cross sections and their own tips; at a grazing angle it is the strands,
        // not an alpha fringe, that break up the outline.
        if tract == .scapular || tract == .median {
            for k in 0..<8 {
                let noise=SeasonalScene.noise(id*29+k*53), side:Float=k%2==0 ? -1 : 1
                let t0=0.47+0.34*noise,root=path(t0), tip=path(0.91+0.076*noise)
                let start=root.p+root.across*(side*width*(0.39+0.34*noise))+root.normal*width*0.062
                let end=tip.p+tip.across*(side*width*(0.28+0.68*noise))+tip.normal*(width*(0.15+0.29*noise))
                let r:Float=width*0.022,axis=tip.across*r
                let b=UInt32(vertices.count), u=Float(id*4+2)+side*0.65, v=Float(tract.rawValue*2)
                for (point,n) in [(start-axis,root.normal),(start+axis,root.normal),(start-root.normal*r,root.normal)] {
                    vertices.append(.init(position:point,normal:n,uv:.init(u,v+t0)))
                }
                vertices.append(.init(position:end,normal:tip.normal,uv:.init(u,v+0.99)))
                indices += [b,b+1,b+3,b+1,b+2,b+3,b+2,b,b+3]
            }
        }
    }

    mutating func sparrowContour() {
        typealias S=SeasonalSparrow
        let rows=49
        var id=0
        for j in 1..<rows {
            let v=Float(j)/Float(rows), y=S.height(v), r=S.ring(y), head=smooth(0.25,0.47,y)
            let span=(r.y-r.x)*0.5, perimeter=2*Float.pi*sqrt((span*span+r.z*r.z)*0.5)
            let number=max(6,Int(perimeter/(0.030-0.011*head)))
            for k in 0..<number {
                id+=1
                let seed=SeasonalScene.noise(id*7+13), q=SeasonalScene.noise(id*13+92)
                let a=2*Float.pi*(Float(k)+Float(j)*0.381966+0.47*(q-0.5))/Float(number)
                let y0=S.height(v+(seed-0.5)*0.70/Float(rows)), root=S.skin(a,y0), n=S.normal(a,y0)
                let cheek=smooth(0.25,0.40,y0)*(1-smooth(-0.26,-0.10,root.x))
                let breast=(1-smooth(-0.44,-0.20,root.x))*(1-smooth(0.25,0.46,y0))
                let direction=SkyPoint(0.90-0.57*breast,-0.35-0.62*breast+0.27*head+0.20*(q-0.5),0.05*sin(a))
                let tangent=simd_normalize(direction-n*simd_dot(n,direction))
                let du=(S.skin(a+0.002,y0)-S.skin(a-0.002,y0))/0.004
                let dv=(S.skin(a,y0+0.0007)-S.skin(a,y0-0.0007))/0.0014
                let aa=simd_dot(du,du),bb=simd_dot(dv,dv),ab=simd_dot(du,dv),det=max(0.00001,aa*bb-ab*ab)
                let da=(simd_dot(tangent,du)*bb-simd_dot(tangent,dv)*ab)/det
                let dy=(simd_dot(tangent,dv)*aa-simd_dot(tangent,du)*ab)/det
                let length=(0.078-0.035*head-0.010*cheek)*(0.83+0.46*seed)
                let width=(0.026-0.014*head)*(0.80+0.40*q)
                let travel=max(-0.9,min(0.9,da*length)), rise=dy*length
                func ring(_ t:Float)->VaneRing {
                    let at=a+travel*t,y1=max(-0.2128,min(0.5798,y0+rise*t))
                    let m=S.normal(at,y1),side=simd_normalize(simd_cross(m,tangent))
                    let puff=(0.003+0.0055*(1-head)+0.003*q)*t*t
                    return .init(p:S.skin(at,y1)+m*(puff-0.0025*(1-t)),across:side,normal:m)
                }
                let middle=ring(0.56).p
                let ox=(middle.x-S.eyeCenter.x)/0.037,oy=(middle.y-S.eyeCenter.y)/0.032
                if ox*ox+oy*oy<1.05 {continue}
                // Flight feathers completely cover the central flank. Hidden follicles
                // are not triangulated for a background running on battery.
                if middle.x > -0.11 && middle.x < 0.23 && middle.y > 0.095 && middle.y < 0.225 && abs(n.z)>0.74 {continue}
                sparrowFan(id,width,ring)
            }
        }
    }

    mutating func sparrowWing() {
        typealias S=SeasonalSparrow
        sparrowTail()
        var id=12
        for sign:Float in [-1,1] {
            // The shoulder, carpal joint, and pointed trailing wingtip are stations on
            // one envelope. A short fan of separated "knives" cannot form a folded wing.
            let base=vertices.count
            grid(48,70) { u,v in
                let x = -0.388+0.888*v,s=SparrowFold.slice(x),a = -sign*2 * .pi*u
                let close=min(1,min(v,1-v)*80)
                let trim:Float=1-0.47*max(0,(v-0.83)/0.17)
                return .init(x,s.x+s.y*cos(a)*close*trim,sign*(s.z+s.w*sin(a)*close*trim))
            }
            for i in base..<vertices.count {
                vertices[i].positionU.w=2
                vertices[i].normalV.w=Float(2*SparrowTract.cushion.rawValue)
            }
            func place(_ tract:SparrowTract,_ start:SIMD2<Float>,_ tip:SIMD2<Float>,_ w:Float,_ order:Float,_ arc:Float) {
                id+=1
                func wingDepth(_ x:Float,_ y:Float)->Float {
                    tract == .mantle ? S.girth(x,y) : SparrowFold.depth(x,y)
                }
                let raised=SIMD2<Float>(start.x,start.y+0.036*max(0,min(1,(-start.x-0.09)*4.4)))
                let delta=tip-raised, chord=simd_normalize(SIMD2(-delta.y,delta.x))
                func height(_ t:Float)->Float {
                    // The calamus is buried under the shoulder; only the distal web
                    // stands above its neighbour. Never leave a visible row of roots.
                    let f=min(1,t*2.5),emerge=f*f*(3-2*f)
                    return -0.012+(order*0.62+0.012)*emerge+0.0021*t
                }
                sparrowFeather(id,tract,w,19,conform:{ p,t in
                    .init(p.x,p.y,sign*(wingDepth(p.x,p.y)+height(t)))
                }) { t in
                    let q=raised+delta*t+chord*(arc*sin(.pi*t))
                    let hx:Float=0.0015
                    let gx=(wingDepth(q.x+hx,q.y)-wingDepth(q.x-hx,q.y))/(2*hx)
                    let gy=(wingDepth(q.x,q.y+hx)-wingDepth(q.x,q.y-hx))/(2*hx)
                    let n=simd_normalize(SkyPoint(-gx,-gy,sign))
                    let across=simd_normalize(SkyPoint(chord.x,chord.y,sign*(gx*chord.x+gy*chord.y)))
                    let dist=wingDepth(q.x,q.y)+height(t)
                    return .init(p:.init(q.x,q.y,sign*dist),across:across,normal:n)
                }
            }
            for j in 0..<9 {
                let f=Float(j)/8
                if j<5 {
                    let g=Float(j)/4
                    place(.primary,.init(-0.274+0.122*g,0.093+0.037*g),
                          .init(0.472+0.094*g,-0.030+0.040*g),0.034-0.004*g,0.050+0.011*g,-0.028)
                } else {
                    place(.primary,.init(-0.120+0.083*f,0.107+0.107*f),
                          .init(0.555-0.102*f,-0.022+0.052*f),0.029-0.004*f,0.002+0.011*f,-0.018)
                }
            }
            for j in 0..<7 {
                let f=Float(j)/6
                place(.secondary,.init(-0.247+0.14*f,0.092+0.108*f),
                      .init(0.218+0.246*f,-0.017+0.047*f),0.048-0.007*f,0.015+0.009*f,-0.027)
            }
            for j in 0..<3 {
                let f=Float(j)/2
                place(.tertial,.init(-0.196+0.051*f,0.204+0.080*f),
                      .init(0.489-0.115*f,0.029+0.110*f),0.048-0.009*f,0.026+0.005*f,-0.011)
            }
            // Exposed inner tertials along the dorsal edge are shorter and more
            // rounded than the pointed primaries below them.
            place(.tertial,.init(-0.106,0.308),.init(0.288,0.170),0.038,0.060,0.009)
            place(.tertial,.init(-0.063,0.266),.init(0.386,0.105),0.041,0.060,0.008)
            for j in 0..<8 {
                let f=Float(j)/7
                place(.greater,.init(-0.329+0.092*f,0.165+0.139*f),
                      .init(-0.045+0.383*f,0.071+0.068*f+0.008*sin(15*f)),0.057-0.012*f,0.033+0.008*f,-0.006)
            }
            for j in 0..<8 {
                let f=Float(j)/7
                let wear=SeasonalScene.noise(291+j*31+(sign>0 ? 4 : 0))-0.5
                place(.median,.init(-0.356+0.124*f,0.215+0.111*f),
                      .init(-0.145+0.258*f+0.024*wear,0.148+0.065*f+0.013*sin(12*f)+0.012*wear),
                      0.049-0.011*f+0.006*wear,0.052+0.010*f,-0.012+0.008*wear)
            }
            for j in 0..<10 {
                let f=Float(j)/9
                place(.scapular,.init(-0.363+0.155*f,0.300+0.065*f),
                      .init(-0.196+0.401*f,0.196+0.043*f+0.015*sin(9*f)),0.042-0.008*f,0.052+0.005*f,-0.009)
            }
            for j in 0..<7 {
                let f=Float(j)/6
                place(.mantle,.init(-0.224+0.112*f,0.349+0.042*f),
                      .init(-0.012+0.232*f,0.236-0.032*f),0.036-0.006*f,0.004+0.002*f,0.013)
            }
        }
    }

    private func smooth(_ a:Float,_ b:Float,_ x:Float)->Float {
        let f=min(1,max(0,(x-a)/(b-a)));return f*f*(3-2*f)
    }
}
