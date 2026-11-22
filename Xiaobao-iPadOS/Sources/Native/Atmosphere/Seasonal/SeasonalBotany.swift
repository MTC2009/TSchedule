import simd

/// The water/mirror equation transferred into the current object's rigid frame.
/// Height is local y; clearance measures perpendicular distance in local units.
struct SeasonalWaterline {
    let normal:SkyPoint, offset:Float
    func height(_ x:Float,_ z:Float,clearance:Float = 0)->Float {
        (clearance-offset-normal.x*x-normal.z*z)/normal.y
    }
    var frame:simd_float3x3 {
        let across=simd_normalize(simd_cross(normal,SkyPoint(0,0,1)))
        return .init(columns:(across,normal,simd_cross(across,normal)))
    }
}

extension SeasonalScene {
    /// A bent, tapered stem with alternating leaf blades, not a repeated leaf silhouette.
    mutating func sprig(_ root:SkyPoint,_ height:Float,_ lean:Float,_ count:Int,_ color:SkyPoint,
                        blade:Float = 0.35, woody:Bool = false) {
        let wind = 0.052*sin(t*1.2+root.x) + lean
        func stem(_ f:Float) -> SkyPoint {
            root+SkyPoint(wind*f*f,height*f,0.16*sin(3*f)*f)
        }
        var previous = root
        for j in 1...count {
            let f = Float(j)/Float(count), joint = stem(f), rnd = Self.noise(j*19+count)
            arc(previous,(joint+previous)*0.5+SkyPoint(-0.009,0,0.014),joint,(woody ? 0.039 : 0.021)*(1.18-f*0.72),woody ? C.twig : C.jade,5)
            let side:Float = j%2==0 ? -1 : 1, size=blade*(1.39-0.76*f)*(0.85+rnd*0.24)
            let petiole=joint+SkyPoint(0.09*side,0.066,-0.02+0.054*rnd)
            taper(joint,petiole,0.014,0.01,C.moss,.foliage)
            let end=petiole+SkyPoint(side*size,(0.29+0.38*rnd)*size+wind*side*0.13,(rnd-0.45)*size)
            vane(petiole,end,size*(0.22+0.07*rnd),.init(0.18*side,0.31,-1),color*(0.72+0.29*f),.leaf,.foliage)
            if woody && j%2==1 {
                let lateral=joint+SkyPoint(-side*0.18,0.24,0.19)
                arc(joint,joint+SkyPoint(-side*0.12,0.06,0.03),lateral,0.014,C.twig,4)
                leaf(lateral,lateral+SkyPoint(-side*size*0.62,0.11,0.04),0.10,color*0.88,0.72)
            }
            previous=joint
        }
    }

    mutating func bareBranch(_ base:SkyPoint,_ top:SkyPoint,_ weight:Float = 1, extend:Bool = true) {
        let mid=(base+top)*0.5+SkyPoint(-0.15,0,0.11)
        func locus(_ f:Float)->SkyPoint {base*(1-f)*(1-f)+2*(1-f)*f*mid+f*f*top}
        // The thicker end continues off frame; short fruiting spurs grow out of the wood
        // with scales, bud scars and an actual terminal bud rather than exposed cylinder caps.
        if extend {
            let foot=base+(base-top)*2.7+SkyPoint(-0.37,0,0.18)
            arc(foot,base+(base-mid)*1.68,base+(mid-base)*0.088,0.109*weight,C.bark)
        }
        arc(base,mid,top,0.050*weight,C.bark)
        for j in 0..<5 {
            let f=0.14+Float(j)*0.158,n=Self.noise(j+13),p=locus(f),side:Float=j%2==0 ? -1 : 1
            let end=p+SkyPoint(side*(0.31-0.14*f),0.15+0.19*n,0.17*cos(6*f))
            let elbow=p+SkyPoint(side*0.19,0.05,0.045)
            arc(p,elbow,end,0.024*weight*(1-0.42*f),C.twig,7)
            let spur=end+(end-elbow)*(0.15+0.18*n)
            taper(end,spur,0.012*weight,0.010*weight,C.umber,.bark,.glume)
            let q=p*0.24+end*0.76
            taper(q,q+SkyPoint(-side*0.062,0.11+0.04*n,-0.022),0.011*weight,0.010*weight,C.copper,.bark,.glume)
            part(.rock,p,.init(0.053,0.035,0.038)*weight,C.umber,.init(0,n,0.30*side),0,.bark)
        }
    }

    mutating func flower(_ p:SkyPoint,_ size:Float,_ openness:Float,_ color:SkyPoint,petals:Int = 5) {
        let o=min(1,max(0,openness)),mum=petals==12
        let normal=simd_normalize(SkyPoint(0.27*sin(17*p.y+1.2),0.15+0.24*sin(7*p.x),-1)), right=simd_normalize(simd_cross(normal,SkyPoint(0,1,0))), up=simd_cross(right,normal)
        let layers=mum ? 4 : 1, seed=sin(p.x*11+p.y*17)
        for j in 0..<5 {
            let a=Float(j)*2 * .pi/5+0.43,ray=cos(a)*right+sin(a)*up
            vane(p-normal*(size*0.08),p+ray*size*0.46-normal*size*0.13,size*0.135,normal,C.moss*0.74,.petal,.foliage)
        }
        for layer in 0..<layers {
            let lf=Float(layer)/Float(max(1,layers-1)), count=mum ? 16-layer*2 : petals
            for j in 0..<count {
                let q=Self.noise(7+j+layer*27),a=2*Float.pi*(Float(j)+0.47*Float(layer))/Float(count)+seed*0.29
                let dir=cos(a)*right+sin(a)*up,root=p+dir*size*(0.03+0.13*lf)+normal*size*0.065*lf
                let out=(0.35+0.79*o)*(1-0.47*lf)*(0.93+0.14*q)
                let cup=(1-o)*0.61+lf*0.40+0.015+0.07*q
                let width=size*(mum ? 0.115 : 0.43)*(1-0.30*lf)
                let pigment=simd_mix(color,color*0.62+C.ivory*0.40,SkyPoint(repeating:0.24+0.43*q))
                vane(root,root+(dir*out+normal*cup)*size,width,normal,pigment,.petal,.petal)
            }
        }
        let center=p+normal*size*(0.12+0.25*(1-o))
        part(.rock,center,.init(0.15,0.13,0.12)*size,C.honey,.zero,0,.awn)
        for j in 0..<(petals==4 ? 5 : 19) {
            let a=Float(j)*2.39996,dir=cos(a)*right+sin(a)*up
            let h=Self.noise(j+3),tip=center+(dir*(0.10+0.13*h)+normal*(0.10+0.15*h))*size
            rod(center+dir*size*0.076,tip,size*0.012,C.ivory,0,.awn)
            part(.bead,tip,.init(0.031,0.041,0.029)*size,C.gold,.init(a,0,0),0,.awn)
        }
    }

    mutating func reed(_ p:SkyPoint,_ h:Float,_ lean:Float,_ fluffy:Bool, snow:Float = 0) {
        let lean=lean+(fluffy ? 0.115*sin(8*p.x+3*p.z)+0.069 : 0)
        let tip=p+SkyPoint(lean,h,0.07*sin(p.x)), stalk=fluffy ? C.hay : C.moss
        arc(p,p+SkyPoint(lean*0.18,h*0.55,0),tip,0.014,stalk,8,0,.awn)
        for j in 0..<3 {
            let f=0.21+Float(j)*0.19,sgn:Float=j%2==0 ? -1 : 1
            let at=p+SkyPoint(lean*f*f,h*f,0),end=at+SkyPoint(sgn*(0.32-0.05*f)+lean*0.29,0.27+0.15*f,0.15*cos(p.x+f*4))
            vane(at,end,0.039-0.013*f,.init(0,0.3,-1),stalk*(0.78+f*0.33),.blade,.foliage,rime:snow)
        }
        if fluffy {
            let roll = -lean*1.16-0.19*sin(p.x*14),head=tip+SkyPoint(-sin(roll)*0.151,0.156,0.013)
            part(.plume,head,.init(0.117,0.192,0.090),simd_mix(C.hay,C.ivory,SkyPoint(repeating:0.38+snow*0.35)),.init(0,p.x*4,roll),0,.awn)
            if snow>0 {
                let k=SeasonalShape.plume.rawValue,i=instances[SeasonalShape.plume.rawValue].count-1
                instances[k][i].extras.w=snow
                for j in 0..<8 {
                    let f=Float(j)/8,sgn:Float=j%2==0 ? -1 : 1
                    let q=head+SkyPoint(sgn*0.046*(1-f)-sin(roll)*(f-0.3)*0.13,(f-0.48)*0.26,-0.018)
                    part(.rock,q,.init(0.038+0.014*(1-f),0.020+0.022*snow,0.029)*snow,C.pearl,.init(0,2*f,roll+sgn*0.12),0,.snow)
                }
            }
        } else {
            let head=tip+SkyPoint(0.064+lean*0.12,0.30,0.038)
            arc(tip,tip+SkyPoint(0.014,0.17,0),head,0.009,C.bud,4,0,.awn)
            for j in 0..<19 {
                let f=Float(j)/19,a=Float(j)*2.39996,dir=SkyPoint(cos(a),0,sin(a))
                let base=tip+(head-tip)*f,end=base+dir*(0.065-0.022*f)+SkyPoint(0.018,0.084-0.029*f,0)
                taper(base,end,0.027*(1-0.29*f),0.020,C.bud*(0.68+0.29*f)+C.hay*0.11,.awn,.glume)
                arc(end,end+(end-base)*0.93,end+(end-base)*2.3+SkyPoint(0.010,0.043,0),0.0028,C.hay,3,0,.awn)
            }
        }
    }

    /// A fork hierarchy, not a ball of foliage on a pole. The same branch tips carry
    /// the leaves in June and expose their small, light-casting shoots in December.
    mutating func solsticeTree(winter:Bool) {
        let base=SkyPoint(-0.11,-0.56,0.03), root=base+SkyPoint(0.084,0.47,0.01)
        let response=0.40*bend+0.22*lift
        arc(base,base+SkyPoint(-0.060,0.26,-0.02),root,0.075,C.bark,11)
        for j in 0..<5 {
            let angle=Float(j)*2.39996
            let heel=base+SkyPoint(cos(angle)*0.24,-0.007,sin(angle)*0.18)
            arc(heel,base+SkyPoint(0,0.028,0),base+SkyPoint(0.013,0.19,0),0.030,C.bark)
        }
        func fork(_ scene:inout SeasonalScene,_ from:SkyPoint,_ heading:SkyPoint,_ len:Float,_ radius:Float,_ order:Int,_ seed:Int) {
            let n=SeasonalScene.noise(seed),d=simd_normalize(heading)
            let end=from+d*len,mid=(from+end)*0.5+SkyPoint((n-0.48)*len*0.23,len*0.046,0.07*len*cos(Float(seed)))
            scene.arc(from,mid,end,radius,order==3 ? C.bark : C.twig,order>1 ? 8 : 5)
            if order==0 {
                if !winter {
                    for k in 0..<6 {
                        let f=Float(k)/6,ang=f*6.28+n*5,q=from+(end-from)*f
                        let tip=q+SkyPoint(0.101*cos(ang)+response*0.06,0.041+0.086*n,0.105*sin(ang))
                        scene.leaf(q,tip,0.036+0.008*n,C.jade*(0.64+0.57*n)+C.moss*(0.16+0.21*f),ang,.leaflet)
                    }
                } else {
                    scene.taper(end,end+d*(0.030+0.031*n),0.005,0.004,C.umber,.bark,.hair)
                }
                return
            }
            let angle=n*6.283+Float(order)*0.9, wing=SkyPoint(cos(angle),0.31,sin(angle))
            let up=SkyPoint(response*0.14,0.40,0)
            fork(&scene,end,d*0.72+wing*0.86+up,len*(0.65+0.06*n),radius*0.52,order-1,seed*2+7)
            fork(&scene,from+(end-from)*0.82,d*0.87-wing*0.69+up,len*(0.63+0.09*n),radius*0.49,order-1,seed*2+11)
        }
        for i in 0..<8 {
            let n=Self.noise(i+74),theta=Float(i)*2.39996,sg=1-(i==6 ? 0.62 : 0)
            fork(&self,root+SkyPoint(0.015*n,0.071*Float(i%3),0),.init(cos(theta)*Float(sg)+response,0.61+0.48*n,sin(theta)),
                 (0.37+0.10*n)*(winter ? 1-0.27*lift : 1),0.030+0.008*n,3,i+21)
        }
    }

    var waterline:SeasonalWaterline? {
        guard let plane=waterPlane else {return nil}
        let n=SkyPoint(plane.x,plane.y,plane.z),localN=basis.transpose*n
        guard localN.y>0.001 else {return nil}
        return .init(normal:localN,offset:(simd_dot(n,origin)+plane.w)/unit)
    }

    mutating func water(_ center:SkyPoint = .init(0,-0.49,0), width:Float = 1.15, pick:Bool = true) {
        let old = target, savedOrigin = origin, savedBasis = basis
        origin = world(center); basis = matrix_identity_float3x3
        defer { origin=savedOrigin; basis=savedBasis; target=old }
        target = pick ? .water : .none
        let angle:Float = -0.74
        let normal=SkyPoint(0,cos(angle),sin(angle))
        waterPlane = .init(normal,-simd_dot(normal,origin))
        // The far bank is behind the subject; the water extends towards the camera and
        // beyond the frame, rather than looking like a floating turquoise disc.
        let forward = SkyPoint(0,-sin(angle),cos(angle))
        let middle = -forward*1.45
        part(.lake,middle,.init(max(6,width*4),1,2.12),C.water,.init(angle,0,0),0,.water)
        target = .none
        let shore = forward*0.66
        part(.bank,shore+SkyPoint(0,0.045,0.15),.init(max(7,width*4.5),0.15,0.22),C.slate)
        target = old
    }

}
