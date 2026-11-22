import simd

extension SeasonalScene {
    mutating func riverTown(watchNight:Bool) {
        // A bend of the canal, not a row of identical front elevations. Light can
        // cross a real arch opening, never a roof, wall or stone parapet.
        place(watchNight ? 0.61 : 0.54,watchNight ? 0.90 : 0.93,9.4,watchNight ? 0.235 : 0.205);focusZ=9.4
        water(.init(0,-0.12,0),width:1.6,pick:false)
        part(.ridgeCut,.init(-0.38,1.22,3.9),.init(4.60,0.78,2.0),watchNight ? C.farIndigo*0.37 : C.riverMist,.zero,0,.cutInk)
        part(.ridgeCut,.init(0,0.58,1.92),.init(4.7,0.34,1),watchNight ? C.farIndigo*0.24 : C.celadon*0.65+C.slate*0.22,.zero,0,.cutInk)
        let layout:[(Float,Float,Float,Float,Float,Int)]=[
            (-2.65,0.19,1.42,0.49,-0.18,2),(-1.99,0.24,1.62,0.62,0.78,3),(-1.37,0.25,1.52,0.48,-0.31,2),
            (0.30,0.18,1.63,0.47,0.70,2),(1.06,0.26,1.72,0.63,0.10,3),(1.81,0.22,1.30,0.64,0.66,3),
            (2.73,0.32,1.73,0.81,-0.17,4),(-2.7,0.18,0.18,0.56,0.12,3),(2.21,0.18,0.08,0.68,-0.42,2)]
        let at=origin,axis=basis
        for (j,lot) in layout.enumerated() {
            let (x,y,z,s,a,bays)=lot
            // The camera looks up a tilted water plane. Receding lots rise off its
            // far bank as well; merely moving a house backwards submerges the facade.
            origin=at+axis*(SkyPoint(x,y+0.47*z,z)*unit);basis=axis*Self.rotation(.init(0,a,0))
            let vote=0.5+0.5*sin(0.61*t+Float(j)*2.41)
            let w:Float=(j==3 || j==8 ? 0.86 : 0.61)*s,d:Float=0.36*s,plaster=watchNight ? C.farIndigo*0.51 : C.chalk*0.81+C.moonSilk*0.20
            part(.cube,.zero,.init(w,0.42*s,d),plaster,.zero,0,.cutInk)
            part(.roof,.init(0,0.40*s,0),.init(w*1.20,0.34*s,d*1.46),C.midnight*0.72+C.slate*0.25,.zero,0,.cutInk)
            if j%3 != 0 {
                for k in 0..<8 {
                    let x = (Float(k)/7-0.5)*1.89*w
                    rod(.init(x,0.37*s,-d*0.89),.init(x,0.403*s,-d*1.41),0.012*s,C.umber,0,.cutInk)
                }
            }
            arc(.init(-w*1.20,0.44*s,-d*1.39),.init(0,0.33*s,-d*1.43),.init(w*1.20,0.44*s,-d*1.39),s*0.019,C.umber,7,0,.cutInk)
            for k in 0..<bays {
                let dx=(Float(k)+0.5)/Float(bays)*1.72*w-0.86*w,wide=w*0.51/Float(bays)
                let c=SkyPoint(dx,-0.012*s,-d-0.003),light=watchNight ? C.honey*(0.54+0.40*vote) : C.umber*0.45+C.ivory*0.43
                part(.cube,c,.init(wide+0.010*s,0.228*s,0.010*s),C.umber,.zero,0,.cutInk)
                part(.cube,c - .init(0,0,0.009),.init(wide,0.205*s,0.009*s),light,.zero,watchNight ? 0.65+0.42*vote : 0,.cutInk)
                for sign:Float in [-1,1] {
                    let x=dx+wide*0.36*sign,z = -d-0.040
                    rod(.init(x,-0.23*s,z),.init(x,0.19*s,z),0.008*s,C.umber,0,.cutInk)
                }
                rod(c + .init(-wide,0.074*s,-0.040),c + .init(wide,0.074*s,-0.040),0.009*s,C.umber,0,.cutInk)
            }
            part(.cube,.init(0,-0.48*s,0),.init(w*1.06,0.09*s,d*1.07),C.slate,.zero,0,.cutInk)
            // Retaining wall down to the canal bed; the raised quarter must not
            // leave a sky gap under its sills when seen through the lane or arch.
            part(.cube,.init(0,-0.55*s-0.58,0),.init(w*1.065,0.59,d*1.076),
                 watchNight ? C.midnight : C.slate*0.69+C.celadon*0.19,.zero,0,.cutInk)
            if j==2 || j==6 {
                // Stepped party wall; eaves and lower roofs terminate against it.
                for k in 0..<3 {
                    let f=Float(k)
                    part(.cube,.init(0.48*s,(0.32+0.12*f)*s,0.1*s),.init(0.054*s,0.103*s,(0.41-0.09*f)*s),C.chalk,.zero,0,.masonry)
                    part(.cube,.init(0.48*s,(0.42+0.12*f)*s,0.1*s),.init(0.069*s,0.020*s,(0.43-0.09*f)*s),C.slate,.zero,0,.cutInk)
                }
            }
            if watchNight && j%2==0 {
                for sg:Float in [-1,1] {
                    let p=SkyPoint(sg*s*0.41,s*0.225,-s*0.51)
                    rod(p + .init(0,0.09,0),p + .init(0,0.15,0),0.005,C.ink,0,.cutInk)
                    part(.lantern,p,.init(0.045,0.056,0.039),C.vermilion*1.75,.zero,1.24,.paper)
                }
            }
        }
        origin=at;basis=axis
        let stone=watchNight ? C.slate*0.76 : C.slate+C.chalk*0.26
        let center:Float = -0.56
        for k in 0..<31 {
            let a=Float(k)*Float.pi/31,b=Float(k+1)*Float.pi/31
            func arch(_ q:Float,_ r:Float)->SkyPoint {.init(center+cos(q)*r,0.035+sin(q)*r*0.76,-0.04)}
            let p=arch(a,0.67),q=arch(b,0.67)
            rod(p,q,0.048,stone,0,.masonry)
            let topY:Float=0.61-0.15*abs(cos((a+b)/2))
            let foot=arch((a+b)/2,0.68)
            part(.cube,.init(foot.x,(foot.y+topY)/2,-0.007),.init(0.67*(abs(cos(a)-cos(b)))*0.54,(topY-foot.y)*0.51,0.060),
                stone,.zero,0,.cutInk)
            if k%3==0 {
                let st=SkyPoint(foot.x,topY,-0.075)
                rod(st,st + .init(0,0.056,0),0.009,C.umber,0,.cutInk)
            }
        }
        arc(.init(center-0.675,0.50,-0.08),.init(center,0.82,-0.08),.init(center+0.675,0.50,-0.08),0.010,C.umber,8,0,.cutInk)
        for sg:Float in [-1,1] {
            part(.cube,.init(center+sg*2.21,0.022,-0.034),.init(1.55,0.122,0.15),stone*0.76,.zero,0,.cutInk)
            part(.cube,.init(center+sg*2.21,0.144,-0.034),.init(1.55,0.013,0.17),stone,.zero,0,.cutInk)
            for k in 0..<11 {
                let f=Float(k)/11,x=center+sg*(0.76+2.82*f),n=Self.noise(k+81)
                let top=SkyPoint(x,0.126,-0.190)
                if k%3 != 0 {
                    arc(top,top+SkyPoint(0.012, -0.051,0),top+SkyPoint(0.018,-0.081-0.016*n,0),0.004,stone*0.48,4,0,.cutInk)
                }
                rod(top+SkyPoint(-0.044,-0.064,0),top+SkyPoint(0.092+0.041*n,-0.066,0),0.004,stone*0.56,0,.cutInk)
            }
        }
        if watchNight {
            place(0.91,0.48,6.4,0.161,-0.13)
            let a=SkyPoint(-1.81,1.67,0.29),b=SkyPoint(1.33,0.63,0.11),sag=SkyPoint(0,-0.25,0)
            arc(a,(a+b)*0.5+sag,b,0.011,C.umber,10,0,.cutInk)
            for j in 0..<5 {
                let f=Float(j+1)/6.0,q=a+(b-a)*f+sag*(2*f*(1-f)),sw=0.033*sin(t*0.71+f*4)
                let lamp=q+SkyPoint(sw,-0.14,0),r:Float=0.073+0.025*f
                rod(q,lamp,0.005,C.brass,0,.cutInk)
                part(.lantern,lamp - .init(0,r*0.41,0),.init(r,r*1.29,r*0.86),C.vermilion*1.5,.init(0,f,sw),0.65,.paper)
                rod(lamp - .init(0,r*1.51,0),lamp - .init(-sw,r*2.1,0),0.008,C.honey,0,.cutInk)
            }
        }
        if !watchNight {
            for k in 0..<3 {
                let q=SkyPoint(-1.53+0.20*Float(k),0.94+0.11*sin(Float(k)*2)+0.025*sin(t+Float(k)),0.48)
                part(.magpieCut,q,.init(repeating:0.041+0.008*Float(k)),C.slate,.zero,0,.cutInk)
                part(.pinionCut,q,.init(repeating:0.047),C.slate,.init(1.1*sin(t*2.4+Float(k)),0,0),0,.cutInk)
            }
        }
    }

    mutating func hauntedEave() {
        place(0.73,0.20,6.6,0.194);focusZ=6.6
        // The wing of the building continues off the right edge. The last rafter
        // and the suspension ring share the same peg in world space.
        target = .none
        let tile=C.midnight*0.63+C.farIndigo*0.24, timber=C.umber*0.64+C.berry*0.15
        let peg=SkyPoint(0.02,0.044,-0.24)
        part(.roof,.init(1.23,0.22,0.09),.init(1.61,0.43,0.62),tile,.init(0,-0.12,0.025),0,.tile)
        arc(.init(-0.27,0.26,-0.49),.init(0.73,0.077,-0.51),.init(2.86,0.17,-0.51),0.034,tile,8,0,.cutInk)
        part(.cube,.init(1.46,0.09,-0.11),.init(1.43,0.058,0.16),timber,.zero,0,.timber)
        for j in 0..<12 {
            let f=Float(j)/11,x=0.02+2.89*f,tip=SkyPoint(x,0.206-0.06*sin(.pi*f),-0.47)
            rod(.init(x,0.15,0.13),tip,0.022,timber,0,.timber)
            part(.bead,tip,.init(0.030,0.039,0.027),tile,.zero,0,.cutInk)
        }
        part(.cube,.init(1.78,-2.77,0.17),.init(0.067,2.89,0.071),timber,.zero,0,.timber)
        part(.cube,.init(2.64,-2.60,0.57),.init(0.68,2.71,0.16),C.farIndigo*0.21+C.umber*0.18,.zero,0,.cutInk)
        for s:Float in [-1,1] {
            arc(.init(1.78,-0.34,0.13),.init(1.78+s*0.22,-0.24,0.10),.init(1.78+s*0.39,0.079,0.09),0.025,timber,7,0,.cutInk)
        }
        part(.cube,.init(2.24,-1.41,-0.035),.init(0.69,0.039,0.054),timber,.zero,0,.cutInk)
        for j in 0..<7 {let x=1.64+Float(j)*0.19;rod(.init(x,-1.95,-0.04),.init(x,-1.40,-0.04),0.019,timber,0,.cutInk)}
        let state=motion.haunt(t),p=peg+SkyPoint(0.039*sin(0.67*t),-1.15+state.rise,-0.048)
        arc(peg,peg+SkyPoint(0.12*state.rise,-0.23,0.012),p + .init(0,0.37,0),0.013,C.umber,7,0,.cutInk)
        part(.ring,peg,.init(0.052,0.67,0.05),C.brass,.init(1.57,0,0),0,.alloy)
        target = .subject
        let center=origin,frame=basis
        origin=world(p);basis=basis*Self.rotation(.init(0.014,0.12+state.turn,0.029*sin(t*0.67)))
        let fire=state.fire,color=simd_mix(C.gold,C.ghost,.init(repeating:fire))
        part(.pumpkin,.zero,.init(0.47,0.385,0.33),C.honey*0.76+C.berry*0.39,.zero,0,.gourd)
        part(.globe,.zero,.init(0.407,0.335,0.28),color,.zero,1.70+0.14*sin(t*3.1),.ember)
        part(.vessel,.init(0,0.323,0),.init(0.154,0.053,0.125),C.umber,.zero,0,.timber)
        for s:Float in [-1,1] {
            arc(.init(s*0.187,0.29,0),.init(s*0.17,0.47,0),.init(0,0.39,0),0.014,C.brass,6,0,.alloy)
        }
        if fire>0.001 {
            for j in 0..<9 {
                let n=Float(j),x:Float=j<4 ? (j<2 ? -0.16 : 0.16)+0.018*cos(n*3) : (n-6)*0.065
                let y:Float=j<4 ? 0.074 : -0.142+0.040*abs(x/0.15)
                let s:Float=(j==0 || j==3 ? 0.23 : 0.14)*(0.85+0.18*sin(8*t+n*2.21))*fire
                let shell=0.305*sqrt(max(0.01,1-pow(x/0.435,2)-pow(y/0.385,2)))
                let at=SkyPoint(x,y+s*0.35,-shell+0.014)
                part(.fireTongue,at,.init(0.091*fire,s,0.15*fire),C.ghost,.init(0,0,0.20*sin(6.4*t+n)),0.56,.cutInk)
                part(.fireTongue,at - .init(0,s*0.12,0.014),.init(0.039*fire,s*0.65,0.14*fire),C.ghost*0.55+C.moonSilk*0.51,.init(0,0,-0.14),0.50,.cutInk)
            }
        }
        lamp(.init(0,0,-0.23),color,0.23+0.25*fire);basis=frame;origin=center;target = .none
    }

    mutating func harvestWindow() {
        // An open kitchen window, seen from outside: one deep sill, a woven
        // harvest basket, split corn husks and a single candle. No full table on a slab.
        place(0.78,0.84,6.5,0.203,-0.10);focusZ=6.5
        let sill=SkyPoint(0,-0.24,-0.02)
        part(.cube,sill + .init(1.08,0,0),.init(2.20,0.075,0.42),C.umber,.zero,0,.timber)
        part(.cube,sill + .init(1.10,-0.90,0.17),.init(2.15,0.84,0.17),C.berry*0.46+C.umber*0.51,.zero,0,.cutInk)
        part(.cube,.init(1.72,0.69,0.35),.init(0.079,1.16,0.074),C.umber,.zero,0,.timber)
        part(.cube,.init(2.71,0.69,0.48),.init(0.98,1.16,0.08),C.umber*0.42,.zero,0,.cutInk)
        for j in 0..<8 {
            let f=Float(j);part(.cube,.init(2.32,0.09+0.17*f,0.35),.init(0.55,0.024,0.048),C.hay*0.51,.init(0.21,0,0),0,.timber)
        }
        let basket=SkyPoint(0.12,0.004,-0.051)
        part(.vessel,basket,.init(0.53,0.17,0.27),C.hay*0.75,.zero,0,.awn)
        arc(basket + .init(-0.44,0.073,0),basket + .init(-0.09,0.91,0.044),basket + .init(0.44,0.073,0),0.027,C.hay,9,0,.cutInk)
        for j in 0..<14 {
            let f=Float(j)/13,x=(f-0.5)*0.91,y=0.152*pow(abs(2*f-1),2)
            arc(basket + .init(x*0.81,-0.073,-0.18),basket + .init(x,0.009+y,-0.28),basket + .init(x*1.03,0.027+y,-0.21),
                0.008,C.copper,5,0,.cutInk)
        }
        for j in 0..<8 {
            let n=Self.noise(j+71),a=Float(j)*2.39996,r=(j<4 ? 0.22 : 0.12)
            let fruit=basket+SkyPoint(Float(r)*cos(a),0.09+0.14*n,0.10*sin(a))
            part(.pumpkin,fruit,.init(0.117,0.089+0.04*n,0.093),j%3==0 ? C.moss : (j%3==1 ? C.vermilion : C.honey),.init(0,a,0.13*cos(a)),0,.squash)
            rod(fruit + .init(0,0.072,0),fruit + .init(0.016,0.14,0),0.009,C.umber)
        }
        for j in 0..<3 {
            let f=Float(j),a=SkyPoint(-0.77+0.094*f,-0.13,0.05),b=a+SkyPoint(0.19+0.06*f,0.29-0.085*f,-0.02)
            taper(a,b,0.067,0.059,C.gold,.awn,.glume)
            for k in 0..<7 {
                let v=Float(k)/7,c=a+(b-a)*v
                for sg:Float in [-1,1] {part(.bead,c+SkyPoint(sg*0.027,0,-0.029),.init(0.018,0.019,0.014),C.honey+C.hay*0.18,.zero,0,.cutInk)}
            }
            for sg:Float in [-1,1] {vane(a,b+SkyPoint(0.11*sg,0.061,0.024),0.042,.init(0.3,0,-1),C.hay,.blade,.foliage)}
        }
        let candle=SkyPoint(0.95,-0.144,-0.09)
        part(.vessel,candle,.init(0.15,0.044,0.10),C.brass,.zero,0,.alloy)
        part(.stem,candle + .init(0,0.176,0),.init(0.061,0.17,0.055),C.ivory,.zero,0,.wax)
        let wick=candle + .init(0,0.37,0)
        part(.fireTongue,wick,.init(0.075,0.11,0.09),C.gold,.init(0,0,0.10*sin(3.7*t)),1.56,.cutInk)
        lamp(wick,C.honey,0.56)
    }

    mutating func midnightQuay() {
        place(0.57,0.89,7.9,0.173);focusZ=7.9
        water(.init(0,-0.089,0),width:1.5,pick:false)
        for j in 0..<3 {
            let f=Float(j)
            part(.ridgeCut,.init(-0.93+0.94*f,-0.01+0.065*f,0.95+1.05*f),.init(2.13+f,0.24+f*0.11,1),C.farIndigo*(0.29+0.11*f),.zero,0,.cutInk)
        }
        let base=SkyPoint(0.85,-0.02,-0.07)
        part(.cube,base + .init(0,0.27,0),.init(0.135,0.30,0.13),C.ink,.zero,0,.cutInk)
        part(.roof,base + .init(0,0.57,0),.init(0.242,0.14,0.21),C.slate,.zero,0,.cutInk)
        for x:Float in [-0.089,0.089] {
            rod(base + .init(x,0.54,-0.04),base + .init(x,0.81,-0.04),0.011,C.umber,0,.cutInk)
        }
        part(.roof,base + .init(0,0.81,0),.init(0.201,0.16,0.16),C.midnight,.zero,0,.cutInk)
        let phase=t.truncatingRemainder(dividingBy:4.2)
        part(.vessel,base + .init(0,0.70,-0.065),.init(0.079,0.082,0.061),C.brass,.init(0,0,0.18*exp(-phase)*sin(phase*8)),0,.alloy)
        for j in 0..<9 {
            let n=Self.noise(170+j),p=SkyPoint(-1.72+Float(j)*0.41,0.11+0.15*n,0.87+0.41*n)
            part(.cube,p,.init(0.030+0.015*n,0.041,0.024),C.honey,.zero,1.32,.paper)
        }
        waterImpulse = .init(world(.init(0.50,-0.089,0)),phase)
        lamp(base + .init(0,0.54,0),C.honey,0.18)
    }
}
