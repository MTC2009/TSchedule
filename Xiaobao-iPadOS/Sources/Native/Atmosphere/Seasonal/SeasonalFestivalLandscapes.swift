import simd

extension SeasonalScene {
    /// The load-bearing silhouette is two flights of feathers sweeping towards a
    /// meeting. Open slots show the *real* sky; no sky-coloured strokes hide a ribbon.
    mutating func magpieSpan() {
        place(0.441,0.414,9.2,0.217);focusZ=9.2
        func deck(_ f:Float)->SkyPoint {.init(-1.96+3.92*f,SeasonalShape.spanHeight(f),0)}
        let blue=C.farIndigo*0.93+C.midnight*0.16, grey=C.riverMist*0.77+C.blush*0.16
        part(.spanCut,.zero,.init(1,1,0.32),grey,.zero,0,.carvedInk)
        let stations:[Float]=[0.105,0.203,0.347,0.457,0.526,0.632,0.722,0.86,0.945]
        for (i,f) in stations.enumerated() {
            let left=f<0.52,sg:Float=left ? -1 : 1
            let slope=(SeasonalShape.spanHeight(f+0.001)-SeasonalShape.spanHeight(f-0.001))/0.00784
            let az=atan(slope),q=deck(f),span=abs(2*f-1),n=Self.noise(81+i)
            let lengths:[Float]=[0.27,0.38,0.54,0.61,0.48]
            for j in 0..<lengths.count {
                let g=Float(j)/4, length=lengths[j]*(0.76+0.22*span+0.23*n)
                let root=q+SkyPoint(-sg*(0.075-0.054*g),-0.006-sg*slope*(0.075-0.054*g),0.046-0.016*g)
                // The quills share a wrist, but each primary has its own taper,
                // pitch and depth. Only the leading vane carries a light stroke.
                let roll=az+sg*(-0.27+0.46*g-0.044*sin(t*0.83+Float(i)+g))
                let rot=Self.rotation(.init(0,sg<0 ? .pi : 0,roll))
                let ink=simd_mix(blue*(0.46+0.23*n),grey,.init(repeating:0.055+0.42*g))
                primitive(.bridgeQuill,root,.init(length,length*(0.44+0.17*g),0.28),ink,rot,0,.carvedInk)
                if j==4 && i%3 == 0 {
                    let m=root+rot*SkyPoint(length*0.38,length*0.030,-0.012)
                    let end=root+rot*SkyPoint(length*0.98,-length*0.093,-0.012)
                    arc(root,m,end,0.0039,grey*0.91,6,0,.carvedInk)
                }
            }
        }
        // Two loose flights approach from opposite banks. A bird crosses a
        // whole span rather than flapping on a pin. The loop closes offstage.
        let flock:[Float]=[0.01,0.103,0.143,0.304,0.358,0.563,0.699,0.849,0.93]
        let limit=max(abs(local(space(-0.03,0.5,focusZ)).x),abs(local(space(1.03,0.5,focusZ)).x))
        let runway=max(4.1,limit+0.18) // even an unusually wide window wraps outside the camera
        for (i,start) in flock.enumerated() {
            let n=Self.noise(i+41),dir:Float=i%3==0 ? -1 : 1
            let travel=start+t*(0.026+0.007*n)*(4.1/runway),u=travel-floor(travel),x=dir*(2*runway*u-runway)
            let f=min(1,max(0,(x+1.96)/3.92)),span=abs(2*f-1)
            // The passage at the crest is above the figures, never through their heads.
            let h=0.086+0.19*n+0.19*exp(-pow((f-0.52)/0.13,2))+0.09*span
            let y=SeasonalShape.spanHeight(f)+h+0.064*sin(5*u+Float(i)*2.1)
            let scale=(0.083+0.085*n)*(0.76+0.24*span)
            let angle=atan(0.48*cos(.pi*f)*dir)+0.18*sin(7*u+Float(i))
            spanBird(.init(x,y,-0.075-0.14*n),size:scale,direction:dir,bank:angle,index:i)
        }
        // Silhouette anchors: two near birds read first. Their shoulders grow a
        // fan into the sweep of the bridge, in contrast to the small airborne flock.
        let bearers:[(Float,Float,Float)]=[(0.085,0.136,0.1),(0.218,0.274,0.15),(0.383,0.105,-0.15),
                                           (0.603,0.137,0.03),(0.752,0.237,-0.10),(0.923,0.123,0.05)]
        for (i,bird) in bearers.enumerated() {
            let (f,size,extra)=bird,dir:Float=f<0.5 ? 1 : -1
            spanBird(deck(f)+SkyPoint(0,(size>0.18 ? 0.093 : 0.020)+0.012*sin(t+Float(i)),-0.065),size:size,
                     direction:dir,bank:0.32*cos(.pi*f)*dir+extra,index:i+19)
        }
        let size:Float=0.176,base=deck(0.506)
        let woman=base+SkyPoint(-0.079,0.64*size,-0.055),man=base+SkyPoint(0.089,0.64*size+0.004,-0.053)
        let rose=C.blush*0.78+C.ivory*0.17
        part(.weaverCut,woman,.init(repeating:size),rose,.init(0,0,-0.064),0,.carvedInk)
        part(.herdsmanCut,man,.init(repeating:size*1.05),C.riverMist*0.91,.init(0,.pi,0.033),0,.carvedInk)
        let scarf=woman+SkyPoint(-0.020,0.042,-0.011),sw=0.013*sin(t*1.23)
        let fold=scarf+SkyPoint(-0.139,-0.028+sw,0.026)
        arc(scarf,scarf+SkyPoint(-0.086,-0.068,0.014),fold,0.0089,rose,7,0,.carvedInk)
        arc(fold,fold+SkyPoint(-0.061,0.047,0.012),fold+SkyPoint(-0.116,0.019-sw,0.013),0.0058,rose,6,0,.carvedInk)
        for j in 0..<21 {
            let f=Self.noise(j*5+24),n=Self.noise(j+91)
            let p=deck(f)+SkyPoint(0.018*sin(0.47*t+17*f),-0.032-n*n*0.26,0.018)
            part(.bead,p,.init(repeating:0.0029+0.0031*n),C.moonSilk,.zero,0.28+0.26*sin(t+12*f),.ember)
        }
    }

    private mutating func spanBird(_ p:SkyPoint,size s:Float,direction dir:Float,bank:Float,index:Int) {
        let n=Self.noise(index+41),phase=t*(2.05+1.39*n)+Float(index)*1.77
        let flap=0.76*sin(phase)+0.24*sin(2*phase-0.62),turn:Float=dir>0 ? 0 : .pi
        let original=basis,at=origin
        origin=world(p);basis=basis*Self.rotation(.init(0.17+0.30*n,turn,dir*bank))
        defer {basis=original;origin=at}
        let dye=simd_mix(C.midnight,C.farIndigo,.init(repeating:(s>0.18 ? 0.30 : 0.32)+0.19*(1-n)))
        let pearl=C.riverMist*0.33+C.moonSilk*0.49
        for near in [false,true] {
            if near {
                part(.magpieCut,.zero,.init(repeating:s),dye,.zero,0,.carvedInk)
                part(.flankFlashCut,.init(0,0,-dir*0.038*s),.init(s,s,0.14*s),pearl,.zero,0,.carvedInk)
            }
            let angle:Float=near ? -0.27+flap*1.12 : 2.04-flap*1.05
            let rot=Self.rotation(.init(angle,near ? 0.17 : -0.37,0.20+0.30*flap))
            let root=SkyPoint(0.05*s,0.048*s,(near ? -0.051 : 0.041)*s),scale=s*(near ? 1.10 : 0.96)
            primitive(.pinionCut,root,.init(repeating:scale),near ? dye : dye*0.76+C.riverMist*0.21,rot,0,.carvedInk)
            // Paint stays registered to each turning wing, including its underside.
            // Broad ellipse highlights, even when attached, read like separate beads.
            for side:Float in [-1,1] {
                let face=root+rot*SkyPoint(0,0,side*0.039*scale)
                let flash=near ? pearl : simd_mix(dye,pearl,.init(repeating:0.53))
                primitive(.wingFlashCut,face,.init(scale,scale,0.14*scale),flash,rot,0,.carvedInk)
            }
        }
    }

    mutating func highPath() {
        // The ridge, the walker, the steps and the pavilion use the same physical
        // station height. Their size diminishes towards the pass, not the reverse.
        place(0.62,0.78,10,0.234);focusZ=10
        part(.ridgeCut,.init(-1.42,0.17,2.18),.init(3.91,0.98,2.0),C.riverMist,.zero,0,.cutInk)
        part(.ridgeCut,.init(0.90,0.15,1.08),.init(3.20,0.71,1.0),C.farIndigo,.zero,0,.cutInk)
        part(.passCut,.zero,.init(1,1,1),C.teal*0.64+C.slate*0.54,.zero,0,.cutInk)
        // Broken masses of rock below the crest, not equally spaced hatching.
        for (j,x) in [Float(-1.53),-0.97,-0.39,0.11,0.85,1.61,2.18].enumerated() {
            let y=SeasonalShape.trailHeight(x),width:Float=[0.26,0.43,0.21,0.56,0.34,0.49,0.33][j]
            let n=Self.noise(j+75),length=0.47+n*0.49,cap=SkyPoint(x,y-0.05-0.13*n,-0.082)
            let shadow=C.teal*0.39+C.farIndigo*(0.39+0.19*n)
            part(.cragCut,cap,.init(width,length,0.34),shadow,.zero,0,.cutInk)
            part(.cragCut,cap + .init(-0.054,-0.041,-0.017),.init(0.43*width,0.67*length,0.19),C.celadon*0.72,.zero,0,.cutInk)
            for k in 0..<3 {
                let f=Float(k)*0.17+0.20,p=cap+SkyPoint(-width*f,-length*f,-0.036)
                arc(p,p+SkyPoint(-0.061,-0.037,0),p+SkyPoint(-0.12,-0.14+0.03*Float(k),0),0.0045,shadow*0.65,4,0,.cutInk)
            }
        }
        for i in 0..<34 {
            let f=Float(i)/33,x = -1.80+2.94*f
            let dy=SeasonalShape.trailHeight(x)
            let below=SeasonalShape.trailHeight(x-0.092),step=max(0.012,(dy-below)*0.54)
            part(.cube,.init(x,dy-step,-0.065),.init(0.046,step,0.044),C.umber*0.62+C.slate*0.67,.zero,0,.cutInk)
            part(.cube,.init(x,dy+0.002,-0.069),.init(0.046,0.006*(1-0.32*f),0.047),C.chalk*0.82,.zero,0,.cutInk)
        }
        let x:Float=1.22,y=SeasonalShape.trailHeight(x)
        part(.cube,.init(x,y+0.006,-0.09),.init(0.156,0.024,0.119),C.slate,.zero,0,.cutInk)
        for s:Float in [-1,1] {
            rod(.init(x+s*0.092,y+0.02,0.016),.init(x+s*0.092,y+0.186,0.016),0.009,C.ink,0,.cutInk)
            rod(.init(x+s*0.128,y+0.020,-0.15),.init(x+s*0.128,y+0.182,-0.15),0.011,C.umber,0,.cutInk)
            arc(.init(x+s*0.128,y+0.134,-0.15),.init(x+s*0.142,y+0.164,-0.15),.init(x+s*0.17,y+0.174,-0.15),0.007,C.berry,5,0,.cutInk)
        }
        part(.cube,.init(x,y+0.148,-0.14),.init(0.160,0.014,0.082),C.berry,.zero,0,.cutInk)
        part(.pavilionCut,.init(x,y+0.171,-0.13),.init(0.235,0.206,2.08),C.midnight,.zero,0,.cutInk)
        arc(.init(x-0.222,y+0.199,-0.211),.init(x,y+0.115,-0.212),.init(x+0.218,y+0.20,-0.211),0.007,C.copper,9,0,.cutInk)
        part(.bead,.init(x,y+0.336,-0.136),.init(0.015,0.030,0.016),C.brass,.zero,0,.cutInk)
        for g in 0..<4 {
            let xx:Float = [-1.32,-1.18,0.63,1.66][g],base=SkyPoint(xx,SeasonalShape.trailHeight(xx)-0.022,-0.063)
            let h:Float=[0.37,0.19,0.092,0.20][g],root=base+SkyPoint(0.04,h,0)
            arc(base,base+SkyPoint(-0.072,h*0.55,0),root,h*0.041,C.pine,7,0,.cutInk)
            for k in 0..<5 {
                let f=Float(k)/5,sg:Float=k%2==0 ? -1 : 1
                let p=base+(root-base)*(0.38+0.59*f),tip=p+SkyPoint(sg*h*(0.59-0.34*f),h*0.045,0)
                arc(p,p+SkyPoint(sg*h*0.2,-h*0.065,0),tip,h*0.027,C.pine,5,0,.cutInk)
                part(.crown,tip,.init(h*(0.32-0.09*f),h*0.086,h*0.105),C.pine,.init(0,0,0.04*sg),0,.cutInk)
            }
        }
        for j in 0..<2 {
            let xx:Float = -0.11+0.12*Float(j),p=SkyPoint(xx,SeasonalShape.trailHeight(xx)-0.008,-0.12)
            rod(p,p+SkyPoint(0.003,0.049,0),0.011,C.ink,0,.cutInk)
            part(.bead,p+SkyPoint(0.003,0.061,0),.init(repeating:0.010),C.umber,.zero,0,.cutInk)
        }
        place(0.14,0.985,5.9,0.137,-0.17)
        for j in 0..<4 {
            let f=Float(j),p=SkyPoint(-0.53+0.32*f,0.16+0.12*sin(f*4.7),0.08*cos(f))
            arc(p - .init(0.08,0.49,0),p - .init(0.06,0.23,0),p,0.012,C.pine)
            flower(p,0.085+0.028*sin(f),0.91,C.gold,petals:12)
        }
    }
}
