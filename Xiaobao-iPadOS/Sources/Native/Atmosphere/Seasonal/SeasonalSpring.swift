import simd

extension SeasonalScene {
    mutating func springStudy(_ theme:Festival) {
        target = .subject
        switch theme {
        case .springBegins:
            let bud = SkyPoint(0.02+0.09*bend,0.34,-0.08)
            bareBranch(.init(-0.88,-0.85,0.22),bud)
            let heel=SkyPoint(-0.42,-0.19,0.11),fork=heel+SkyPoint(-0.12,0.26,0.028)
            arc(heel,heel+SkyPoint(-0.11,0.09,0),fork,0.016,C.twig)
            for s:Float in [-1,1] {
                vane(fork,fork+SkyPoint(s*0.039,0.094,0.016),0.034,.init(0,0,-1),C.copper,.petal,.cutInk)
            }
            for i in 0..<5 {
                let a = Float(i)*2.4+t*0.05, open = 0.17+lift*0.36
                let direction=SkyPoint(cos(a)*open,0.25+0.065*Float(i)+0.09*lift,sin(a)*open)
                leaf(bud,bud+direction,0.091-0.008*Float(i),i%2==0 ? C.bud : C.moss,a,.blade)
                vane(bud - .init(0,0.04,0),bud+direction*0.30,0.051,.init(cos(a),0,sin(a)),C.copper,.petal,.bark)
            }
            leaf(.init(-0.19,0.03,0),.init(-0.52,0.17,0.02),0.085,C.jade)
        case .springRain:
            water()
            let root = SkyPoint(-0.10,0.50,0)
            arc(.init(2.8,1.02,0.38),.init(0.64,0.85,0.16),root,0.043,C.twig)
            leaf(.init(0.64,0.68,0.14),.init(0.88,0.91,0.12),0.085,C.moss)
            leaf(.init(0.37,0.61,0.10),.init(0.11,0.82,0.16),0.080,C.bud)
            let tip = SkyPoint(-0.65,0.14+0.09*bend,-0.06)
            leaf(root,tip,0.16,C.jade,-0.35)
            let touched = motion.gesture?.target == .subject, a = motion.age(t)
            let f = touched && a<1.4 ? min(1,a*1.55) : 0
            let p = tip+SkyPoint(0,-0.072-0.73*f*f,0)
            let r = touched && a<1.4 && f>=1 ? 0.016 : 0.072+0.014*sin(t)
            part(.globe,p,.init(r,r*1.28,r),C.silver,.zero,0.15,.dew)
            if touched && a>0.57 && a<3.3 {
                waterImpulse = .init(world(.init(tip.x,-0.48,-0.08)),a-0.57)
            }
        case .awakening:
            let base = SkyPoint(-0.72,-0.5,0.04), tip = SkyPoint(0.56,0.38,0.08)
            // Only the visible insect is a touch target. Its leaf still writes depth;
            // while tucked behind it, the insect cannot be tapped through the blade.
            target = .none
            arc(base,.init(-0.62,0.08,0.18),.init(-0.19,0.1,0.1),0.028,C.twig)
            arc(.init(-1.45,-1.68,0.24),.init(-0.91,-0.86,0.15),base,0.035,C.twig)
            leaf(base,tip,0.29,C.jade,-0.65)
            target = .subject
            // The beetle retracts its legs and moves behind the blade in depth; never flies away.
            let tucked = lift
            let p = SkyPoint(0.02+0.045*sin(t*0.69)-0.12*tucked,0.03-0.09*tucked,-0.22+0.56*tucked)
            insect(p,0.94-0.23*tucked,tucked,dragonfly:false)
        case .springEquinox:
            water(.init(0,-0.60,0),width:1.38)
            for i in 0..<2 {
                let f=Float(i),phase=sin(t*(3.7-0.6*f)+2.6*f),x:Float=(i==0 ? -0.34 : 0.53)+0.22*sin(t*0.60+f*2.5)
                let p=SkyPoint(x,0.38-f*0.35+0.26*lift,0.19-f*0.28),s:Float=i==0 ? 0.27 : 0.17
                let axis=basis,at=origin;origin=world(p)
                basis=basis*Self.rotation(.init(-0.06,i==0 ? 0.23 : 2.98,0.03+0.21*phase+0.35*lift))
                part(.swallowCut,.zero,.init(repeating:s),C.midnight,.zero,0,.cutInk)
                for side:Float in [-1,1] {
                    let rot=Self.rotation(.init(0.75*side+0.96*phase,side*0.19,0.36*phase+side*0.65+0.24*bend))
                    primitive(.pinionCut,.init(0,0,s*0.025*side),.init(s,s*1.16,s),C.midnight,rot,0,.cutInk)
                }
                part(.bead,.init(0.19*s,0.006,-0.05*s),.init(0.18*s,0.045*s,0.013*s),C.ivory,.zero,0,.cutInk)
                basis=axis;origin=at
            }
        case .qingming:
            water(.init(-0.12,-0.5,0),width:1.48)
            // The willow enters from the bank outside the viewport; it is not suspended over the lake.
            arc(.init(2.85,1.89,0.31),.init(1.38,1.13,0.22),.init(0.83,1.16,0.16),0.058,C.bark)
            arc(.init(0.83,1.16,0.16),.init(0.40,0.95,0),.init(-0.56,0.81,0),0.035,C.bark)
            for i in 0..<11 {
                let f = Float(i)/10, n=Self.noise(i*7+24), x = -0.55+f*1.30+0.058*(n-0.5)
                let len = 0.51+0.44*sin(f*4.3+0.5)+0.30*n
                let start = SkyPoint(x,0.81+0.22*f,0.09*cos(f*7))
                let drift = 0.12*sin(t*0.88+f*3)+0.39*bend
                let tip = start+SkyPoint(-0.13+drift,-len,0.11)
                arc(start,start+SkyPoint(-0.15,-0.50*len,0),tip,0.012,C.jade,5)
                for k in 1...8 {
                    let v = Float(k)/8, p = simd_mix(start,tip,SkyPoint(repeating:v))
                    leaf(p,p+SkyPoint((k.isMultiple(of:2) ? 0.10 : -0.09)+0.08*drift,-0.17-0.051*sin(f*8+v),0.038*cos(7*f)),0.024+0.010*v,C.moss*(0.79+0.28*f),v,.blade)
                }
            }
        case .grainRain:
            arc(.init(-1.24,-2.6,0.25),.init(-0.52,-1.11,0.03),.init(-0.344,-0.699,0),0.053,C.bark)
            sprig(.init(-0.36,-0.73,0),1.06,0.24+0.29*bend,5,C.jade,blade:0.60,woody:true)
            let start = SkyPoint(-0.11+0.23*bend,0.31,0)
            leaf(start,start+SkyPoint(-0.13-0.26*lift,0.39,0.12),0.11,C.bud)
            leaf(start,start+SkyPoint(0.10+0.34*lift,0.43,-0.05),0.12,C.moss)
            let furl=start+SkyPoint(0.014,0.05,-0.041)
            vane(furl,furl+SkyPoint(0.074+0.072*lift,0.27,-0.016),0.048,.init(0.30,0.16,-1),C.bud+C.ivory*0.13,.petal,.foliage)
        default: break
        }
    }
}
