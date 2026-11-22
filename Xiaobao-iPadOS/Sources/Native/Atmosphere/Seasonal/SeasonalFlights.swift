import simd

extension SeasonalScene {
    mutating func flightScene(_ theme:Festival,moon:SIMD4<Float>) {
        if let pose = SeasonalMotion.flight(theme,time:t,landing:motion.landing) {
            focusZ=pose.z
            let rabbit = theme == .midautumn
            // Angular extent on the same perspective camera as moonDisk(), in
            // fractions of the viewport height. The hare's nose-to-toe span is 1.99.
            let r=moon.w, dz=moon.z
            let lunarWidth=2*r*sqrt(moon.x*moon.x+dz*dz-r*r)/((dz*dz-r*r)*Self.span)
            let size:Float=rabbit ? 0.80*lunarWidth/1.99 : (theme == .christmasEve ? 0.057 : 0.078)
            place(pose.x,pose.y,pose.z,size)
            target = rabbit ? .rabbit : .sleigh
            if rabbit {
                part(.moonCut,.zero,.init(1,1,0.45),C.moonSilk,.init(0,0,0.035*sin(t*1.6)),0.08,.cutInk)
            } else {
                parcelOrigin=world(.init(-0.85,0.16,-0.07))
                procession(eve:theme == .christmasEve)
            }
        }
        if theme != .midautumn, let drop = motion.present {
            let age = t-drop.at
            if age>=0 && age<2.9 {
                // The gift origin belongs to the tap frame, never to the moving sleigh afterwards.
                basis = matrix_identity_float3x3; unit = 1; target = .none
                for j in 0..<3 {
                    let f = Float(j), age = max(0,age-f*0.11)
                    guard age > 0 else { continue }
                    origin = drop.origin+SkyPoint((0.36-0.40*f)*age,0.14*age-(0.88+0.11*f)*age*age,0.46*age*(f-1))
                    basis = Self.rotation(.init(age*(1.4+f),age*(2.0+f),age*(f-0.71)))
                    parcel(.zero,0.095+f*0.017,j==1 ? C.jade : C.vermilion)
                }
            }
        }
    }

    private mutating func procession(eve:Bool) {
        let dye=eve ? C.silver*0.67+C.moonSilk*0.14 : C.berry, pole=eve ? C.moonSilk*0.63 : C.brass
        part(.sailCut,.init(-0.59,0,0),.init(0.82,0.82,0.8),dye,.zero,0,.cutInk)
        part(.riderCut,.init(-0.55,0.22,0.08),.init(repeating:0.64),eve ? dye : C.vermilion,.zero,0,.cutInk)
        part(.rock,.init(-0.96,0.14,0.065),.init(0.24,0.23,0.14),dye,.init(0.3,0,-0.4),0,.cutInk)
        for side:Float in [-1,1] {
            let z=0.10*side
            arc(.init(-1.32,-0.265,z),.init(-0.70,-0.33,z),.init(-0.08,-0.245,z),0.020,pole,8,0,.cutInk)
            arc(.init(-0.08,-0.245,z),.init(0.17,-0.16,z),.init(0.12,-0.062,z),0.017,pole,8,0,.cutInk)
            for x:Float in [-1.03,-0.49] {rod(.init(x,-0.13,z),.init(x+0.05,-0.28,z),0.020,pole,0,.cutInk)}
        }
        for j in 0..<2 {
            let i=Float(j),phase=t*2.65+1.9*i
            let p=SkyPoint(0.51+0.98*i,0.19+0.14*i+0.051*sin(phase),0.06-0.14*i),s:Float=0.57+0.026*i
            part(.stagCut,p,.init(repeating:s),eve ? dye : C.umber,.init(0,0,0.085*sin(phase)),0,.cutInk)
            let ant=p+SkyPoint(0.48,0.51,-0.08)*s
            for k in 0..<2 {
                let z=Float(k)*0.09,tip=ant+SkyPoint(-0.24-0.03*Float(k),0.26,z)*s
                arc(ant,ant+SkyPoint(-0.06,0.16,z)*s,tip,0.018,pole,7,0,.cutInk)
                for q in 1...3 {
                    let f=Float(q)/4,a=ant+(tip-ant)*f
                    rod(a,a+SkyPoint(0.025,0.064+0.035*f,0)*s,0.010,pole,0,.cutInk)
                }
            }
            arc(.init(-0.32,0.25,-0.02),.init(0.12+i*0.23,-0.02,-0.07),p+SkyPoint(0.22,0.20,-0.06),0.009,pole,7,0,.cutInk)
        }
    }

    private mutating func parcel(_ at:SkyPoint,_ r:Float,_ color:SkyPoint) {
        part(.cube,at,.init(r,r*0.85,r*0.85),color,.zero,0,.paper)
        part(.cube,at,.init(r*0.15,r*0.86,r*0.88),C.gold,.zero,0,.cloth)
        part(.cube,at,.init(r*1.02,r*0.87,r*0.13),C.gold,.zero,0,.cloth)
        for side:Float in [-1,1] {
            part(.ring,at+SkyPoint(side*r*0.27,r*1.04,0),.init(r*0.34,r*0.41,r*0.22),C.gold,
                 .init(1.12,0,side*0.42),0,.cloth)
            leaf(at+SkyPoint(0,r*0.89,0),at+SkyPoint(side*r*0.51,r*0.88,r*0.65),r*0.108,C.brass,side*0.66,.blade,.cloth)
        }
    }
}
