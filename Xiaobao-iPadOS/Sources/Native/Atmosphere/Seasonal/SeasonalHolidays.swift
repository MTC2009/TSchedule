import simd

extension SeasonalScene {
    mutating func holiday(_ day:Festival) {
        switch day {
        case .spring: fireworks()
        case .lantern: fireworks(distant:true);lanternNight()
        case .lunarEve, .newyear: riverTown(watchNight:day == .lunarEve)
        case .yearEve: midnightQuay()
        case .dragonBoat: riverRace()
        case .qixi: magpieSpan()
        case .doubleNinth: highPath()
        case .halloween: hauntedEave()
        case .thanksgiving: harvestWindow()
        default: break
        }
    }

    private mutating func fireworks(distant:Bool = false) {
        // A lane has at most one live shell; the next launch is sampled only
        // once per event. No frame-rate-dependent random numbers or repeated burst map.
        var brightest:Float=0
        for j in 0..<(distant ? 2 : 4) {
            let lane=distant ? 20+j : j, f=Float(j), period:Float=(distant ? 7.65 : 4.95)+0.49*f
            let clock=t+[1.2,3.1,4.9,0.2][j]+0.48*motion.sample(lane,0,7)
            let cycle=Int(floor(clock/period))
            func choose(_ k:Int)->Float {motion.sample(lane,cycle,k)}
            let age=clock-Float(cycle)*period-0.06-0.53*choose(0)
            guard age>=0 else {continue}
            let range:Float=(distant ? 15.4 : 8.2)+6.4*choose(2), u:Float=0.12+(distant ? 0.49 : 0.77)*choose(1)
            let size:Float=distant ? 0.061+0.053*choose(4) : 0.078+0.119*choose(4)
            place(u,(distant ? 0.39 : 0.22)+(distant ? 0.20 : 0.39)*choose(3),range,size)
            let dyes=[C.gold,C.vermilion*1.65,C.blush,C.honey,C.ivory]
            let ink=dyes[Int(choose(5)*Float(dyes.count))],pattern=Int(choose(6)*3)
            if age < 0.82 {
                let p = SkyPoint(0,-1.62+age*1.98,0.18)
                rod(p - .init(0.014,0.21,0.015),p,0.008,C.honey,1.4)
                part(.globe,p,.init(repeating:0.014),C.ivory,.zero,2.7); continue
            }
            let a = age-0.82
            guard a<2.98 else { continue }
            let intensity=(1.4+choose(8))*exp(-a*1.25)
            // The lantern plate keeps its near paper lamp as its key light. A
            // far burst has its own emissive sparks but must not move the close lamp's smoke or focus.
            if !distant && intensity>brightest {brightest=intensity;lamp(.zero,ink,intensity);smoke=min(1,a*1.6)*exp(-0.53*a);focusZ=range}
            if a<0.27 { part(.globe,.zero,.init(repeating:0.054*(1-a/0.27)),C.ivory,.zero,3.0) }
            let count=distant ? 46 : 78
            for i in 0..<count {
                let y = 2*(Float(i)+0.5)/Float(count)-1, ring = sqrt(max(0,1-y*y))
                let theta = Float(i)*2.39996+6.28*choose(9)
                let seed = motion.sample(lane,cycle,20+i), life = 1.69+1.27*seed
                guard a<life else { continue }
                let fade = min(1,(life-a)*2.7), inner = i%4==0
                let dir = SkyPoint(ring*cos(theta),pattern==2 ? 0.37*y+0.52*ring*sin(theta) : y,ring*sin(theta))*(inner ? 0.54+0.16*seed : 1.0+0.32*seed)
                func position(_ s:Float) -> SkyPoint {
                    dir*(1-exp(-1.12*s)) + SkyPoint(0.021*s*s,-(pattern==1 ? 0.18 : 0.070)*s*s,0)
                }
                let tail = max(0,a-0.51-seed*0.24), middle = max(0,a-0.24-seed*0.06)
                let p=position(a), warm = inner ? C.honey : ink
                rod(position(tail),position(middle),0.0031*fade,warm*0.58,0.64*fade,.ember)
                rod(position(middle),p,0.0062*fade,warm,1.3*fade,.ember)
                if i%3 != 0 {
                    for k in 0..<3 {
                        let lapse=(0.075+0.15*Float(k))*(0.84+0.42*seed),q=position(max(0,a-lapse))
                        let ember=q+SkyPoint(0.033*sin(theta+lapse*4),-0.12*lapse,0.018*cos(theta))
                        part(.bead,ember,.init(repeating:0.0088*fade*(1-lapse)),warm,.zero,(1.05+seed)*fade,.ember)
                    }
                }
                let shimmer = 0.82+0.18*cos(9*a+theta)
                part(.globe,p,.init(repeating:(0.012+0.005*seed)*fade),i%5==0 ? C.pearl : C.ivory,
                     .zero,(1.45+shimmer)*fade)
            }
        }
    }

    private mutating func lanternNight() {
        // Airborne paper lights leave the frame before their next lifetime
        // starts. Each has its own altitude, breeze, depth and flame rhythm.
        for j in 0..<9 {
            let lane=j+41,period:Float=15+9*motion.sample(lane,0,0)
            let clock=t+period*motion.sample(lane,0,1),cycle=Int(floor(clock/period))
            let q=clock/period-Float(cycle),n=motion.sample(lane,cycle,2),z=motion.sample(lane,cycle,3)
            let x=0.06+0.72*n+(0.10*z-0.03)*q+0.031*sin(4*q+6*n)
            place(x,1.14-1.31*q,9+13*z,0.012+0.020*(1-z),0.53*sin(6*q+n))
            basis=basis*Self.rotation(.init(0.08*cos(q*6+n),0,0.13*sin(6*q+4*n)))
            part(.lantern,.zero,.init(0.49,0.66,0.42),j%3==0 ? C.vermilion*1.7 : C.honey,.zero,0.71+0.14*sin(2.7*t+9*n),.paper)
            part(.ring,.init(0,-0.56,0),.init(0.33,0.14,0.29),C.copper)
            part(.bead,.init(0,-0.41,-0.16),.init(0.10,0.19,0.09),C.gold,.zero,2.0,.ember)
        }
        place(0.845,0.29,5.9,0.112)
        focusZ=5.9
        let peg=world(.init(0,1.76,0)),wind=0.065*sin(0.83*t)+0.034*sin(1.31*t+4*motion.sample(12,0,0))
        basis=Self.rotation(.init(0.02*cos(t),0.30+0.22*sin(t*0.46),wind))
        origin=peg-basis*(SkyPoint(0,1.76,0)*unit)
        rod(.init(0,0.83,0),.init(0,2.18,0),0.014,C.brass)
        part(.lantern,.zero,.init(0.67,0.78,0.67),C.honey,.zero,0.94,.paper)
        part(.lantern,.init(0,0.68,0),.init(0.76,0.094,0.76),C.berry,.zero,0,.hide)
        part(.lantern,.init(0,0.746,0),.init(0.69,0.074,0.69),C.brass,.zero,0,.alloy)
        part(.lantern,.init(0,0.793,0),.init(0.63,0.087,0.63),C.berry,.zero,0,.glaze)
        part(.ring,.init(0,-0.70,0),.init(0.51,0.33,0.51),C.brass,.zero,0,.alloy)
        part(.vessel,.init(0,-0.69,0),.init(0.23,0.092,0.23),C.brass,.zero,0,.alloy)
        part(.lantern,.init(0,0.85,0),.init(0.41,0.12,0.41),C.brass)
        for i in 0..<8 {
            let a = (Float(i)+0.5) * .pi/4
            let dir = SkyPoint(cos(a),0,sin(a)), tip = dir*0.76+SkyPoint(0,0.47,0)
            rod(dir*0.46+SkyPoint(0,0.63,0),tip,0.023,C.brass)
            rod(tip,dir*0.67+SkyPoint(0,-0.38,0),0.018,C.berry)
            rod(dir*0.67+SkyPoint(0,-0.38,0),dir*0.39+SkyPoint(0,-0.77,0),0.022,C.brass)
            let interior=dir*0.17+SkyPoint(0,-0.742,0),edge=dir*0.52+SkyPoint(0,-0.705,0)
            arc(edge,(edge+interior)*0.5+SkyPoint(0,-0.119,0),interior,0.015,C.brass,7,0,.alloy)
            let crown=dir*0.67+SkyPoint(0,0.73,0),finial=dir*0.81+SkyPoint(0,0.823,0)
            arc(crown,(crown+finial)*0.5-SkyPoint(0,0.071,0),finial,0.019,C.brass,8,0,.alloy)
            let faceAngle = a + Float.pi/8, front = SkyPoint(cos(faceAngle),0,sin(faceAngle))*0.666
            let tangent = SkyPoint(-sin(faceAngle),0,cos(faceAngle))
            let out=simd_normalize(front),base=front-out*0.020
            // A raised gilded peony tracery conforms to each of eight paper panels.
            // Small brackets, chains and tassels break the silhouette in both cameras.
            for k in 0..<7 {
                let angle=Float(k)*2 * .pi/7,up=SkyPoint(0,1,0)
                let dir=tangent*cos(angle)+up*sin(angle),side=up*cos(angle)-tangent*sin(angle)
                let root=base+out*0.019+dir*0.022,tip=base+dir*(0.173+0.019*cos(3*angle))
                for sign:Float in [-1,1] {
                    arc(root,base+dir*0.096+side*sign*0.087+out*0.032,tip,0.0087,C.brass,6,0,.alloy)
                }
            }
            for sign:Float in [-1,1] {
                let rail=base+tangent*sign*0.193
                arc(rail+SkyPoint(0,-0.278,0),rail+tangent*sign*0.020+SkyPoint(0,0.04,0),rail+SkyPoint(0,0.275,0),0.007,C.brass,6,0,.alloy)
                for k in 0..<3 {
                    let c=rail-tangent*sign*0.043+SkyPoint(0,Float(k-1)*0.153,0)
                    arc(c+tangent*sign*0.027,c+SkyPoint(0,0.091,0),c-tangent*sign*0.048+SkyPoint(0,0.052,0),0.0048,C.copper,4,0,.alloy)
                }
                for y:Float in [-0.43,0.39] {
                    let a=base+tangent*sign*0.20+SkyPoint(0,y,0),b=a-tangent*sign*0.157
                    arc(a,a+SkyPoint(0,y>0 ? -0.21 : 0.21,0),b,0.012,C.berry,6,0,.hide)
                    arc(b,b+tangent*sign*0.056+SkyPoint(0,y>0 ? -0.11 : 0.11,0),b+tangent*sign*0.095,0.006,C.brass,4,0,.alloy)
                }
            }
            let bob=tip+SkyPoint(0.022*sin(t+a),-0.20,0)
            rod(tip,bob,0.007,C.brass,0,.alloy); part(.globe,bob,.init(0.036,0.047,0.036),C.brass,.zero,0,.alloy)
            let below=dir*0.38+SkyPoint(0,-0.77,0)
            part(.globe,below,.init(0.035,0.065,0.035),C.berry,.zero,0,.cloth)
            for k in 0..<7 {
                let rad=Float(k)*2.39996,r=SkyPoint(0.019*cos(rad),0,0.019*sin(rad))
                let end=below+r*1.8+SkyPoint(0.036*sin(t+a),-0.29-0.047*cos(rad),0)
                arc(below+r,below+SkyPoint(0,-0.17,0)+r*1.6,end,0.0065,k%3==0 ? C.vermilion : C.berry,4,0,.cloth)
            }
        }
        for y:Float in [-0.62,-0.48,0.51,0.64] {
            let r:Float = abs(y)>0.60 ? 0.54 : 0.63
            part(.ring,.init(0,y,0),.init(r,0.35,r),C.brass)
        }
        part(.globe,.init(0,-0.82,0),.init(repeating:0.075),C.gold,.zero,0.18)
        lamp(.zero,C.honey,0.64)
    }

}
