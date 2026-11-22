import simd

extension SeasonalScene {
    mutating func autumnStudy(_ theme:Festival) {
        target = .subject
        switch theme {
        case .autumnBegins:
            let stem = SkyPoint(-0.12,0.34,0.08)
            arc(.init(-5.9,-2.7,0.65),.init(-1.73,-0.43,0.24),.init(-0.925,0.072,0.22),0.055,C.bark)
            bareBranch(.init(-0.93,0.07,0.22),stem,0.72,extend:false)
            let twig=SkyPoint(-0.56,0.18,0.13),tip=twig+SkyPoint(-0.19,0.22,0.08)
            arc(twig,twig+SkyPoint(-0.09,0.035,0.04),tip,0.012,C.twig)
            vane(tip,tip+SkyPoint(-0.29,-0.028,0.043),0.085,.init(0.13,0.11,-1),C.moss,.leaf,.foliage)
            let roll = 0.24*sin(t*0.54)+bend*1.6+lift*1.8
            let root=stem+SkyPoint(0.017,-0.019,-0.026),at=origin,axes=basis
            origin=world(root);basis=basis*Self.rotation(.init(0,0,-2.35))*Self.rotation(.init(0,0.16+roll,0))
            let mid=SkyPoint(0,0.27,0)
            rod(.zero,mid,0.013,C.copper,0,.bark)
            part(.mapleCut,mid,.init(0.25,0.29,0.37),C.brass*0.71+C.vermilion*0.55,.zero,0,.foliage)
            for side:Float in [-1,1] {for k in 0..<3 {
                let f=Float(k)/3,p=mid+SkyPoint(0,-0.14+0.14*f,-0.017),tip=p+SkyPoint(side*(0.15-0.076*f),0.053+0.075*f,0)
                arc(p,(p+tip)*0.5+SkyPoint(0,-0.014,0),tip,0.0035,C.hay,4,0,.cutInk)
            }}
            origin=at;basis=axes
            leaf(stem,stem+SkyPoint(-0.30,-0.19,0.18),0.12,C.moss,-0.5)
        case .endOfHeat:
            for j in 0..<4 {
                let f = Float(j), g = 0.12*sin(t*0.91+f)+0.63*bend
                reed(.init(-0.54+0.32*f,-0.70,0.21*cos(f)),0.86+0.17*sin(f),g,true)
            }
            driftingSeeds(count:8, spread:lift, pale:false)
        case .whiteDew:
            let b = SkyPoint(-0.58,-0.53,0.04), top = SkyPoint(0.39,0.42+0.11*bend,0)
            arc(.init(-1.32,-1.54,0.26),.init(-0.88,-0.65,0.13),b,0.037,C.twig)
            leaf(b,top,0.25,C.jade,-0.21)
            let pos = simd_mix(top,b,SkyPoint(repeating:0.31+0.48*lift))+SkyPoint(0.01,0.025,-0.11)
            part(.globe,pos,.init(0.090,0.096,0.091),C.silver,.zero,0.04,.dew)
            for j in 0..<8 {
                let f=0.14+Float(j)*0.087,n=Self.noise(j+43), side:Float=j%2==0 ? -1 : 1
                let q=b+(top-b)*f+SkyPoint(-0.085*side,0.080*side,-0.064)
                let r=0.012+0.028*n
                part(.bead,q,.init(r,r*0.92,r),C.silver,.zero,0,.dew)
            }
            part(.globe,top+SkyPoint(-0.30,-0.23,-0.12),.init(repeating:0.041),C.pearl,.zero,0.1,.dew)
        case .autumnEquinox:
            water(.init(0,-0.27,0),width:1.27)
            let p = SkyPoint(-0.38,-0.26,-0.005)
            sprig(p,0.85,0.33+0.23*bend,4,C.jade,blade:0.33,woody:true)
            for j in 0..<3 {
                let y = Float(j)*0.16
                flower(p+SkyPoint(0.12+y*0.4,0.35+y,-0.05),0.13,0.86,C.gold,petals:4)
            }
            // A second submerged branch is a reflected silhouette below the actual water surface.
            for j in 0..<4 {
                let f = Float(j)/4
                leaf(p+SkyPoint(0.27*f,-0.36*f,-0.11-f*0.09),
                     p+SkyPoint(0.27*f+0.22,-0.36*f-0.10,-0.13-f*0.09),0.050,C.teal)
            }
        case .coldDew:
            dewLoom()
        case .frostDescent:
            let root = SkyPoint(-0.70,-0.63,0), top = SkyPoint(0.42,0.49,0.08)
            arc(root-SkyPoint(0.46,1.5,0),root-SkyPoint(0.15,0.37,0),root + .init(0.02,0.02,0),0.049,C.bark)
            arc(root,.init(-0.28,0.10,0),top,0.036,C.bark)
            for j in 0..<6 {
                let f = Float(j)/6, side:Float = j%2==0 ? -1 : 1
                let p = simd_mix(root,top,SkyPoint(repeating:f))
                let end = p+SkyPoint(0.36*side+0.10*bend,0.27,0.13*sin(f*5))
                let col = simd_mix(C.copper,C.vermilion,SkyPoint(repeating:min(1,0.2+f*0.5+lift)))
                leaf(p,end,0.118,col,0.43*side+bend)
                for k in 1...6 {
                    let u=Float(k)/8,q=p+(end-p)*u
                    let crystal=SkyPoint(-side*0.030,0.043,0.011)*(1-0.68*lift)
                    taper(q + .init(0.009,0.014,-0.014),q+crystal,0.009,0.006,C.pearl,.snow,.glume)
                }
            }
        default: break
        }
    }

    /// Each spiral crosses a radius at a shared knot. Deposits are sampled on
    /// the bowed thread itself; wind, tension and touch move the two together.
    private mutating func dewLoom() {
        let count=16,turns=7,hub=SkyPoint(-0.039,0.075,-0.080)
        let hit=motion.gesture.map {local($0.point)} ?? hub,age=motion.age(t)
        var outer:[SkyPoint]=[]
        for j in 0..<count {
            let n=Self.noise(j+52),a=2*Float.pi*(Float(j)+0.24*(n-0.5))/Float(count)-0.091
            let x=cos(a)*(0.65+0.059*n), y=sin(a)*(sin(a)>0 ? 0.359 : 0.548)
            outer.append(hub+SkyPoint(x,y+0.098*x,0.097*x+0.037*cos(3*a)))
        }
        // Upper scaffold, slender tether twigs and a lower reed. The frame
        // belongs to the habitat (not the touch ID of a vibrating silk strand).
        let wood=[SkyPoint(0.83,0.33,0.065),SkyPoint(-0.67,0.51,-0.060),SkyPoint(-0.90,-0.015,-0.12),SkyPoint(0.19,-0.69,-0.016)]
        target = .none
        let fork=SkyPoint(-0.82,0.49,-0.10),knuckle=SkyPoint(0.66,0.68,0.12),joint=SkyPoint(-0.23,0.56,-0.02)
        arc(.init(4.1,1.37,0.32),.init(1.91,0.82,0.19),knuckle,0.043,C.bark)
        arc(knuckle,.init(0.28,0.53,0.051),joint,0.034,C.bark)
        arc(joint,.init(-0.53,0.585,-0.076),fork,0.023,C.bark)
        let spur=fork+SkyPoint(-0.19,0.073,-0.03)
        arc(fork,fork+SkyPoint(-0.11,0.018,0.014),spur,0.012,C.twig)
        taper(spur,spur+SkyPoint(-0.105,0.076,0),0.009,0.008,C.twig,.bark)
        arc(knuckle,.init(0.83,0.55,0.14),wood[0],0.017,C.twig)
        taper(wood[0],wood[0]+SkyPoint(-0.049,-0.073,-0.013),0.013,0.011,C.twig,.bark)
        arc(fork,fork+SkyPoint(0.12,0.014,0),wood[1],0.021,C.twig)
        arc(fork,fork+SkyPoint(0.16,-0.20,-0.006),wood[2],0.018,C.twig)
        taper(wood[2],wood[2]+SkyPoint(-0.040,-0.073,0),0.013,0.010,C.bark,.bark)
        arc(.init(-0.20,-2.7,0.29),.init(-0.08,-1.32,0.093),wood[3],0.023,C.twig)
        taper(wood[3],wood[3]+SkyPoint(0.029,0.084,-0.009),0.016,0.010,C.hay,.awn)
        for (j,p) in [knuckle,fork,wood[1]].enumerated() {
            let side:Float=j==1 ? -1 : 1
            let q=p+SkyPoint(0.087*side,0.09,-0.013)
            arc(p,p+SkyPoint(0.02*side,0.068,0),q,0.008,C.twig,4,0,.bark)
            taper(q,q+SkyPoint(0.064*side,0.071,0.012),0.017,0.014,C.umber,.awn,.glume)
        }
        target = .subject
        let silk=C.farIndigo*0.57+C.chalk*0.27,rims=C.pearl*0.61+C.riverMist*0.28
        for (j,pin) in [1,6,8,12].enumerated() {
            let root=wood[j],tip=outer[pin]
            arc(root,(root+tip)*0.5+SkyPoint(0,-0.025,0),tip,0.0046,silk,5,0,.cutInk)
        }
        func knot(_ j:Int,_ u:Float)->SkyPoint {
            let end=outer[j%count],nu=1-u
            var p=hub+(end-hub)*u
            let d=simd_length(SIMD2<Float>(p.x-hit.x,p.y-hit.y))
            let arrival=age-d*0.49, impulse:Float
            if motion.gesture?.target != .subject {impulse=0}
            else if motion.gesture?.held==true {impulse=bend*exp(-1.5*d)}
            else if arrival>0 && arrival<2.65 {impulse=sin(arrival*15.4)*exp(-arrival*3.15-1.12*d)}
            else {impulse=0}
            let air=0.009*sin(t*1.52+p.y*3.1+p.x*2.3)
            p.y+=nu*(air-0.019*u+0.073*impulse);p.z+=nu*(air*0.69-0.15*impulse)
            return p
        }
        func radius(_ j:Int,_ turn:Int)->Float {0.06+(Float(turn)+Float(j)/Float(count))*0.124}
        for j in 0..<count {
            let next=(j+1)%count,edge=outer[j],end=outer[next]
            arc(edge,(edge+end)*0.5+SkyPoint(0,-0.011,0.002),end,0.0035,silk,4,0,.cutInk)
            var prev=knot(j,0)
            for turn in 0..<turns {
                let u=radius(j,turn),v=radius(j+1,turn),p=knot(j,u),q=knot(next,v)
                rod(prev,p,0.00275,silk,0,.cutInk);prev=p
                let rnd=Self.noise(61*turn+j+9),sag=0.010+0.11*simd_distance(p,q)
                let control=(p+q)*0.5+SkyPoint(0,-sag,0.009*rnd)
                let glint=pow(0.5+0.5*cos(Float(j)*0.76+Float(turn)*0.21),2.2)
                let fiber=simd_mix(silk*(0.59+0.17*rnd),rims,.init(repeating:glint))
                arc(p,control,q,0.0023+0.0011*glint,fiber,4,0,.cutInk)
                if rnd>0.61 {
                    let v=0.32+0.39*Self.noise(j*17+turn),u=1-v,r=0.007+0.0149*pow(rnd,4)
                    let bead=p*(u*u)+control*(2*u*v)+q*(v*v)
                    part(.bead,bead+SkyPoint(0,-0.37*r,0),.init(r,1.12*r,r),C.silver,.zero,0,.dew)
                    if rnd>0.85 {
                        let k=max(0.06,v-0.24),l=1-k,small=p*(l*l)+control*(2*k*l)+q*(k*k)
                        part(.bead,small,.init(repeating:0.41*r),C.pearl,.zero,0,.dew)
                    }
                }
            }
            rod(prev,edge,0.00275,silk,0,.cutInk)
        }
    }

    mutating func driftingSeeds(count:Int, spread:Float, pale:Bool) {
        for j in 0..<count {
            let f = Float(j), phase = t*0.28+f*2.4
            let p = SkyPoint(-0.79+1.53*Self.noise(j+41)+0.12*cos(phase)+0.47*spread,
                             0.22+0.50*Self.noise(j+72)+0.11*sin(phase)+0.22*spread,
                             0.23*sin(f*3.3)+0.38*spread*cos(f))
            let cap=p+SkyPoint(0.014*cos(phase),0.039,0.020*sin(phase))
            taper(p,cap,0.008,0.007,C.hay,.awn,.glume)
            for k in 0..<13 {
                let a=Float(k)*2.39996+phase,n=Self.noise(j*19+k)
                let end=cap+SkyPoint(cos(a)*(0.039+0.015*n),0.027+0.028*n,sin(a)*(0.039+0.013*n))
                arc(cap,(end+cap)*0.5+SkyPoint(0,0.008,0),end,0.0026,pale ? C.pearl : C.ivory,3,0,.awn)
            }
        }
    }
}
