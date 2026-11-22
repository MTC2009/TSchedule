import simd

extension SeasonalMeshAtlas.Mesh {
    /// Closed laminas: one longitude goes around the obverse, folded edge and
    /// reverse. Map the same longitudinal fibres onto both sides of a bamboo leaf.
    mutating func festivalLamina(_ shape:SeasonalShape) {
        grid(shape == .bambooLeaf ? 40 : 26,shape == .mumLeaf ? 66 : 40) { u,v in
            let angle=2*Float.pi*u,w=cos(angle),back=sin(angle),a=max(0,sin(.pi*v))
            let width,fold,sweep,rib,turn:Float
            switch shape {
            case .bambooLeaf:
                // A broad, elongated wrapper with a shoulder near the base,
                // a long drawn point, parallel fibres and a slight change of hand.
                width=pow(a,0.63)*(1.16-0.35*v)*(1+0.039*w)
                fold = abs(w)*0.60+0.086*w*w; sweep=0.62*a-0.63*v*v
                rib=0.057;turn = -0.37+0.81*v+0.20*sin(1.5 * .pi*v)
            case .mumLeaf:
                let p=v+0.024*w
                let cuts=exp(-pow((p-0.28)/0.048,2))+0.94*exp(-pow((p-0.52)/0.055,2))+0.67*exp(-pow((p-0.70)/0.046,2))
                width=pow(a,0.75)*(1.24-0.44*v)*(1-0.50*cuts)*(0.963+0.037*cos(52*p+0.24*w))
                fold=0.34*abs(w);sweep=0.25*a-0.11*v;rib=0.074;turn=0.13-0.36*v
            case .oliveLeaf:
                width=pow(a,0.81)*(1.14-0.34*v)*(0.992+0.008*cos(104*v+0.7*w))
                fold=0.24*abs(w);sweep=0.27*a-0.24*v*v;rib=0.065;turn = -0.12+0.42*v
            case .bulbLeaf:
                width=pow(a,0.39)*(1.06-0.19*v)
                fold=0.60*w*w+0.08*abs(w);sweep=0.33*a-0.44*v*v;rib=0.082;turn=0.43*v
            default: // Ligulate chrysanthemum floret: rolled stem, open spoon at the end.
                let cup=max(0,(v-0.53)/0.47)
                width=pow(a,0.51)*(0.43+0.57*cup+0.32*v)
                fold=(0.92-0.36*v)*w*w;sweep = -0.61*a+0.71*v*v;rib=0.084;turn=0.44*v-0.11
            }
            let x=width*w,z=width*(fold+rib*back)+sweep
            return .init(x*cos(turn)-z*sin(turn),2*v-1,x*sin(turn)+z*cos(turn))
        }
        if shape == .bambooLeaf || shape == .bulbLeaf {
            for i in vertices.indices {vertices[i].positionU.w=0.5+0.5*cos(vertices[i].positionU.w*2 * .pi)}
        }
    }

    /// A whole corolla is one instance, but each overlapping petal has two
    /// curved surfaces and a continuous edge. A side blossom can turn edge on.
    mutating func festivalCorolla(_ shape:SeasonalShape) {
        let count=shape == .osmanthusFlower ? 4 : (shape == .plumFlower ? 5 : 6)
        for j in 0..<count {
            let n=SeasonalScene.noise(j*13+6),theta=(Float(j)+0.068*n)*2 * .pi/Float(count)
            let axis=SIMD2<Float>(cos(theta),sin(theta)),cross=SIMD2<Float>(-axis.y,axis.x)
            grid(count==4 ? 12 : 20,count==4 ? 14 : 24) {u,v in
                let ang=2*Float.pi*u,w=cos(ang),a=max(0,sin(.pi*v)),side=sin(ang)
                let breadth:Float,rad:Float,z:Float
                if shape == .narcissusFlower {
                    breadth=0.42*pow(a,0.69)*(0.71+0.45*v)
                    rad=0.087+v*(0.91+0.055*n);z=0.24*a-0.22*v*v+0.12*breadth*w*w+0.075*n
                } else if shape == .osmanthusFlower {
                    breadth=0.53*pow(a,0.57)*(0.67+0.56*v)
                    rad=0.026+v*(0.91+0.055*n);z=0.39*sin(v*1.6)-0.14*v*v+0.21*breadth*w*w
                } else {
                    breadth=0.58*pow(a,0.48)*(0.76+0.36*v)
                    rad=0.03+v*(0.94+0.052*n);z=0.30*sin(v*1.89)+0.10*breadth*w*w+0.091*n*v
                }
                let xy=axis*rad+cross*(w*breadth+0.069*a*(n-0.5))
                return .init(xy.x,xy.y,z+0.054*side*breadth)
            }
        }
    }

    mutating func narcissusCup() {
        // Return along the inside of the corona: the yellow cup has a real
        // shadowed opening rather than a yellow disc stuck on a white flower.
        let profile:[SIMD2<Float>]=[.init(0,-0.08),.init(0.36,-0.07),.init(0.60,0.12),.init(0.76,0.49),
            .init(1,0.84),.init(0.86,0.89),.init(0.69,0.60),.init(0.50,0.21),.init(0,0.14)]
        grid(32,24) {u,v in
            let f=min(1,max(0,v))*Float(profile.count-1),i=min(profile.count-2,Int(f)),g=f-Float(i)
            let q=profile[i]*(1-g)+profile[i+1]*g,a=2*Float.pi*u
            let lip=0.105*sin(6*a+0.4)+0.039*sin(10*a),r=q.x*(1+0.033*cos(6*a))
            return .init(r*cos(a),r*sin(a),q.y+lip*smoothstep(0.42,0.87,q.y))
        }
    }
}

extension SeasonalScene {
    /// Orient a bloom in its stem's frame, not towards a screen. The same tilt
    /// is used by the corolla, its centre, reflections and solar shadows.
    static func bloomFrame(_ normal:SkyPoint,spin:Float = 0)->simd_float3x3 {
        let az=simd_normalize(normal)
        let reference:SkyPoint=abs(az.y)>0.94 ? .init(1,0,0) : .init(0,1,0)
        let ax=simd_normalize(simd_cross(az,reference))
        return simd_float3x3(columns:(ax,simd_cross(az,ax),az))*rotation(.init(0,0,spin))
    }
    /// Quadratic shared by a woody stem, its lateral shoots and foliage. Arc's
    /// middle argument is the Bézier control, not a point on the visible wood.
    static func stemPoint(_ a:SkyPoint,_ control:SkyPoint,_ b:SkyPoint,_ f:Float)->SkyPoint {
        let g=1-f
        return a*(g*g)+control*(2*f*g)+b*(f*f)
    }
}
