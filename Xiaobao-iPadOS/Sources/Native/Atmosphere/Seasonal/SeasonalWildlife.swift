import simd

extension SeasonalScene {
    mutating func insect(_ p:SkyPoint,_ size:Float,_ fold:Float,dragonfly:Bool) {
        let s=size
        func P(_ x:Float,_ y:Float,_ z:Float)->SkyPoint {p+SkyPoint(x,y,z)*s}
        if !dragonfly {
            part(.beetle,p,.init(repeating:s),C.teal,.zero,0,.shell)
            for side:Float in [-1,1] {
                part(.globe,P(0.216,side*0.066,-0.025),.init(0.025,0.022,0.024)*s,C.ink,.zero,0,.glaze)
                let a=P(0.222,side*0.053,-0.039), e=P(0.303,side*0.142,-0.032)
                arc(a,P(0.237,side*0.129,-0.051),e,0.007*s,C.umber,5,0,.hide)
                taper(e,P(0.336,side*0.172,-0.03),0.010*s,0.009*s,C.umber,.hide)
                for j in 0..<3 {
                    let f=Float(j)-1
                    let hip=P(0.013+f*0.10,side*0.101,0.010),knee=P(f*0.130+0.021,side*(0.172-0.050*fold),0.015)
                    let tibia=P(f*0.205-0.004,side*(0.208-0.091*fold),0.041)
                    taper(hip,knee,0.016*s,0.013*s,C.umber,.hide)
                    taper(knee,tibia,0.011*s,0.009*s,C.ink,.hide)
                    let foot=tibia+SkyPoint(-0.024,side*0.025,0.006)*s
                    rod(tibia,foot,0.0048*s,C.bark,0,.hide)
                    for k in 1...3 {
                        let at=knee+(tibia-knee)*Float(k)/4
                        taper(at,at+SkyPoint(-0.020,side*0.014,0)*s,0.004*s,0.004*s,C.ink,.hide,.hair)
                    }
                }
            }
            return
        }
        for j in 0..<10 {
            let f=Float(j)/9,x = -0.49+0.56*f
            let ink=simd_mix(C.teal,C.umber,SkyPoint(repeating:j%3==0 ? 0.63 : 0.17))
            part(.globe,P(x,0.012*sin(f*4),0),.init(0.052,0.020+0.017*f,0.023+0.015*f)*s,ink,.zero,0,.shell)
        }
        part(.globe,P(0.079,0.015,0),.init(0.119,0.076,0.074)*s,C.teal,.zero,0,.shell)
        for side:Float in [-1,1] {
            part(.globe,P(0.195,0.039,side*0.055),.init(0.068,0.058,0.052)*s,C.umber,.zero,0,.glaze)
            for j in 0..<2 {
                let root=P(0.032+Float(j)*0.11,0.041,side*0.045)
                let tip=root+SkyPoint(j==0 ? -0.33 : 0.092,0.17+fold*0.45,side*(0.595-fold*0.15))*s
                let breadth=(j==0 ? 0.091 : 0.070)*s
                leaf(root,tip,breadth,C.silver,side*0.22,.wing,.membrane)
                rod(root,tip,0.004*s,C.umber,0,.hide)
                for m in 2...8 {
                    let f=Float(m)/10, at=root+(tip-root)*f, span=breadth*sin(.pi*f)
                    let edge=at+SkyPoint(-span,0.012*s,0)
                    rod(edge,at+(tip-root)*0.068,0.0026*s,C.umber,0,.hide)
                }
                let stigma=root+(tip-root)*0.84
                taper(stigma,stigma+(tip-root)*0.081,0.008*s,0.005*s,C.umber,.hide)
            }
        }
    }
}
