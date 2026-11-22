import simd

extension SeasonalScene {
    mutating func house(_ p:SkyPoint,_ s:Float,_ warmth:Float,wide:Bool = false, bays:Int = 3) {
        let w:Float=wide ? 1.06 : 0.59
        func at(_ x:Float,_ y:Float,_ z:Float)->SkyPoint {p+SkyPoint(x,y,z)*s}
        func sz(_ x:Float,_ y:Float,_ z:Float)->SkyPoint {SkyPoint(x,y,z)*s}
        part(.cube,p,sz(w,0.40,0.37),C.chalk*0.78,.zero,0,.stone)
        part(.cube,at(0,-0.43,0),sz(w*1.03,0.15,0.41),C.slate,.zero,0,.stone)
        part(.roof,at(0,0.402,0),sz(w*1.14,0.36,0.52),C.slate*0.58,.zero,0,.tile)
        arc(at(-w*1.14,0.765,0),at(0,0.72,0),at(w*1.14,0.765,0),s*0.029,C.ink,8,0,.tile)
        for side:Float in [-1,1] {
            rod(at(-w,0.365,side*0.36),at(w,0.365,side*0.36),s*0.035,C.umber)
            for k in 0..<5 {
                let x=w*(Float(k)*0.47-0.94)
                rod(at(x,0.33,side*0.35),at(x,0.40,side*0.50),s*0.023,C.twig)
            }
        }
        let count=min(4,max(2,bays))
        for j in 0..<count {
            let step=1.88*w/Float(count),x=(Float(j)-Float(count-1)*0.5)*step,half=step*0.364,pigment=j==2 ? C.ivory : C.honey
            part(.cube,at(x,-0.006,-0.371),sz(half,0.238,0.022),C.umber,.zero,0,.bark)
            part(.cube,at(x,-0.005,-0.395),sz(half*0.86,0.198,0.008),pigment*0.60,.zero,warmth*(j==1 ? 0.77 : 1.1),.paper)
            for k in -1...1 {
                let dx=x+Float(k)*half*0.51
                rod(at(dx,-0.216,-0.412),at(dx,0.20,-0.412),s*0.011,C.umber)
            }
            for y:Float in [-0.202,0.046,0.13] {
                rod(at(x-half,y,-0.409),at(x+half,y,-0.409),s*0.012,C.umber)
            }
            part(.cube,at(x,-0.249,-0.412),sz(half*1.11,0.022,0.053),C.slate,.zero,0,.stone)
        }
    }

}
