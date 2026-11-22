import simd

extension SeasonalScene {
    mutating func winterStudy(_ theme:Festival) {
        target = .subject
        switch theme {
        case .winterBegins:
            target = .none
            let ground=SkyPoint(0,0.75,0.66)
            part(.floor,SkyPoint(0,-0.596,0.15)-ground*2.4,.init(5.5,0.13,2.89),C.umber,.init(-0.85,0,0),0,.soil)
            target = .subject
            house(.init(0.35,-0.21,0.35),0.78,0.43+1.8*lift,wide:true,bays:2)
            // A reed blind is rolled up above the glowing casement. Its ties,
            // warm threshold and the wood laid in for winter all meet the building.
            let lintel=SkyPoint(0.35,0.055,0.023)
            rod(lintel - .init(0.61,0,0),lintel + .init(0.61,0,0),0.061,C.hay,0,.awn)
            for x:Float in [-0.43,0.39] {
                arc(lintel + .init(x,0.043,-0.017),lintel + .init(x+0.015,0,-0.094),lintel + .init(x,-0.09,-0.04),0.009,C.umber,5,0,.cutInk)
            }
            bareBranch(.init(-0.85,-0.67,-0.13),.init(-0.34,0.73,-0.13),0.79)
            lamp(.init(0.22,-0.20,-0.05),C.honey,0.16+lift)
        case .lightSnow:
            reed(.init(-0.61,-0.69,0.03),1.01,0.25+0.26*bend,true,snow:0.50)
            driftingSeeds(count:12,spread:lift,pale:true)
            for j in 0..<8 {
                let n=Self.noise(j+77),p=SkyPoint(-0.92+1.58*n+0.064*sin(t*0.59+Float(j)),0.64-0.14*Float(j%4)+0.044*sin(t+n),0.18*n)
                let r=0.017+0.016*n
                for k in 0..<3 {
                    let a=Float(k)*Float.pi/3+t*0.12+n,ray=SkyPoint(cos(a),sin(a),0)*r
                    rod(p-ray,p+ray,0.0028,C.moonSilk,0,.cutInk)
                }
            }
        case .heavySnow:
            for j in 0..<11 {
                let f = Float(j)/10, d = Float(j%3)
                let at = motion.gesture.map { local($0.point).x } ?? 0
                let x = -0.98+f*1.9+0.042*Self.noise(j+18)
                let wave = 0.34*lift*cos(4*(x-at)-2.6*min(3,motion.age(t)))*exp(-abs(x-at))
                reed(.init(x,-0.83+0.055*d,0.16*d),0.77+0.24*sin(f*4)+0.24*Self.noise(j+11),
                     0.22+0.17*sin(t*1.2+f*3)+0.12*cos(Float(j)*3)+wave+0.42*bend,true,snow:0.94)
            }
        case .winterSolstice: summerStudy(.winterSolstice)
        case .lesserCold:
            perchedSparrow()
        case .greaterCold:
            let a = SkyPoint(-0.88,-0.59,0.1), b = SkyPoint(0.49,0.43,0)
            bareBranch(a,b,1.02)
            let fork=a+(b-a)*0.63,spur=fork+SkyPoint(-0.15,0.41,0.035)
            arc(fork,fork+SkyPoint(-0.038,0.22,0.07),spur,0.031,C.bark)
            flower(spur,0.12,0.28+0.65*lift,C.blush,petals:5)
            for j in 0..<10 {
                let rnd=Self.noise(j+23), f=0.13+Float(j/2)*0.177+0.041*rnd
                let p=a+(b-a)*f+SkyPoint(-0.08*sin(f*3),0,0.033)
                let side:Float=j%2==0 ? -1 : 1, q=p+SkyPoint(side*(0.09+0.16*rnd),0.10+0.09*rnd,-0.036-0.059*rnd)
                arc(p,p+SkyPoint(side*0.069,0.031,0),q,0.013,C.twig,5)
                let open:Float=j%3==0 ? 0.70 : (j%3==1 ? 0.16 : 0.37)
                let size:Float=j%3==1 ? 0.071+0.030*rnd : 0.135+0.06*rnd
                let pigment=simd_mix(C.blush,C.pearl,SkyPoint(repeating:0.35+0.37*rnd))
                flower(q,size,min(1,open+0.65*lift),pigment)
            }
        default: break
        }
    }
}
