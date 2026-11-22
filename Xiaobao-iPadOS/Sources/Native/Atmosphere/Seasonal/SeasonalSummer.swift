import simd

extension SeasonalScene {
    mutating func summerStudy(_ theme:Festival) {
        target = .subject
        switch theme {
        case .summerBegins:
            water()
            let tip = SkyPoint(-0.07+0.15*bend,0.23,0.03)
            arc(.init(-0.29,-0.47,0),.init(-0.30,0.09,0),tip,0.024,C.jade)
            leaf(tip - .init(0.18,0.10,0),tip + .init(0.20,0.04,0.09),0.19,C.moss,0.6)
            let curled=SkyPoint(0.39,0.044+0.043*bend,0.19)
            arc(.init(0.27,-0.48,0.21),.init(0.28,-0.19,0.17),curled,0.014,C.jade)
            for side:Float in [-1,1] {
                vane(curled,curled+SkyPoint(-0.048+side*0.032,0.18,0.011),0.043,.init(side*0.56,0.32,-1),side<0 ? C.moss : C.celadon,.petal,.foliage)
            }
            insect(tip+SkyPoint(0.08,0.11,-0.07),0.95,0.13*sin(4*t)+0.85*lift,dragonfly:true)
        case .grainBuds:
            for i in 0..<8 {
                let f = Float(i)/7,n=Self.noise(i+71)
                reed(.init(-0.78+1.49*f+0.08*n,-0.80+0.056*n,0.34*sin(f*5.3)),0.70+0.36*n+0.16*cos(f*5),
                     0.15+0.22*sin(t*0.91+f*3.9)+0.37*bend-0.33*lift+0.11*n,false)
            }
        case .grainInEar:
            water(.init(0,-0.51,0),width:1.35)
            for row in 0..<4 { for col in 0..<6 {
                let i=col+row*6,n=Self.noise(i+57),r=Float(row)
                let z = -0.28+0.17*r+0.051*n
                let p=SkyPoint(-1.24+Float(col)*0.456+0.23*sin(r*1.3+0.25*Float(col))+0.094*n,-0.526+0.91*z,z)
                let near=motion.gesture.map {max(0,1-simd_distance(local($0.point),p)*0.64)} ?? 0
                let h=0.22+0.14*n+0.28*near*lift
                for j in 0..<5 {
                    let theta=Float(j)*2.39996+n*3
                    let end=p+SkyPoint(cos(theta)*(0.14+0.095*n)+0.16*bend*near,h*(0.75+0.24*sin(theta)),0.12*sin(theta))
                    vane(p,end,0.016+0.007*n,.init(0.3,0.38,-1),C.moss*(0.63+0.37*n),.blade,.foliage)
                }
                if i%3 != 0 {
                    part(.rock,p - .init(0,0.027,0),.init(0.089,0.032,0.062),C.umber,.init(-0.77,0.37*r,0),0,.soil)
                }
            }}
        case .summerSolstice, .winterSolstice:
            let winter = theme == .winterSolstice
            let angle:Float = -0.54, ground = SkyPoint(0,-0.52,0), forward=SkyPoint(0,-sin(angle),cos(angle))
            let earth = winter ? simd_mix(C.ivory,C.slate,.init(repeating:0.50)) : simd_mix(C.moss,C.twig,.init(repeating:0.45))
            target = .none
            part(.lake,ground-forward*1.5,.init(8,1,1.99),earth,.init(angle,0,0),0,.soil)
            part(.bank,ground+forward*0.51+SkyPoint(0,0.04,0),.init(9,0.19,0.36),earth*0.71)
            // The swaying crown changes the projected silhouette in the light camera, not a painted ellipse.
            target = .subject
            solsticeTree(winter:winter)
        case .lesserHeat:
            water()
            sprig(.init(-0.63,-0.53,0.1),0.60,-0.15,4,C.jade,blade:0.27)
            let at = motion.gesture.map { local($0.point) } ?? .zero
            for j in 0..<20 {
                let f = Float(j), a = t*0.42+f*2.40
                let p = SkyPoint(0.87*cos(a)+0.06*sin(t+f),0.15+0.40*sin(f*4.1+t*0.6),0.45*sin(a))
                let q = simd_mix(p,at+0.29*p,SkyPoint(repeating:0.83*lift))
                let bright = 0.8+0.65*cos(t*2.1+f)
                let axis=SkyPoint(0.041*cos(a),0.016*sin(2*a),0.038*sin(a))
                taper(q-axis*0.71,q+axis,0.012,0.012,C.umber,.hide)
                part(.bead,q-axis*0.61,.init(0.011+0.003*bright,0.010,0.012),C.bud,.zero,bright+0.6,.ember)
                for side:Float in [-1,1] {
                    let root=q+axis*0.36
                    leaf(root,q-axis+SkyPoint(side*0.021,0.026+0.025*sin(9*t+f),0.015),0.009,C.silver,side*0.4,.wing,.membrane)
                }
            }
        case .greaterHeat:
            water(.init(0,-0.52,0),width:1.27)
            guard let pond=waterline else {return}
            let blossom = SkyPoint(0.07+0.058*bend,0.13,0)
            arc(.init(-0.13,pond.height(-0.13,0,clearance:-0.16),0),.init(-0.07,-0.08,0),blossom,0.021,C.jade)
            lotus(blossom,0.52)
            let pod=SkyPoint(0.50,-0.025,0.21)
            arc(pod-SkyPoint(0.16,0.47,0),pod-SkyPoint(0.04,0.20,0),pod,0.019,C.jade)
            part(.vessel,pod,.init(0.103,0.048,0.085),C.hay,.init(-0.31,0,-0.19),0,.awn)
            for k in 0..<6 {let a=Float(k)*2.39996;part(.bead,pod+SkyPoint(0.066*cos(a),0.037,0.047*sin(a)),.init(repeating:0.011),C.umber,.zero,0,.cutInk)}
            let pads:[(Float,Float,Float,Float)]=[(-0.38,-0.033,0.38,0.52),(0.43,0.24,0.27,2.65),(-0.68,0.36,0.19,4.02)]
            for (j,pad) in pads.enumerated() {
                let (x,z,s,turn)=pad,y=pond.height(x,z,clearance:0.014)
                let axes=pond.frame*Self.rotation(.init(0.040+0.022*cos(t*0.71+Float(j)),turn,-0.053))
                primitive(.pad,.init(x,y,z),.init(s,0.16*s,0.83*s),C.jade*0.65+C.teal*0.52,axes,0,.leafPad)
            }
        default: break
        }
    }

    /// Broad outer tepals unfold into a saucer; the inner whorl cups an exposed
    /// receptacle. Delays are measured from contact, not from a looping animation.
    private mutating func lotus(_ root:SkyPoint,_ size:Float) {
        let axis=simd_normalize(SkyPoint(-0.16+0.035*bend,0.79,-0.66)),right=simd_normalize(simd_cross(axis,SkyPoint(0,1,0)))
        let up=simd_cross(right,axis),heart=root+axis*(0.078*size)
        func radial(_ a:Float)->SkyPoint {right*cos(a)+up*sin(a)}
        for j in 0..<5 {
            let a=Float(j)*2 * .pi/5+0.23,ray=radial(a)
            vane(root-axis*size*0.087,root+size*(0.37*ray-0.18*axis),size*0.127,axis,C.moss*0.64+C.rose*0.28,.lotusTepal,.foliage)
        }
        for ring in 0..<3 {
            let reach:[Float]=[1.07,0.88,0.61],rise:[Float]=[-0.015,0.145,0.314],width:[Float]=[0.327,0.260,0.184]
            let count=[8,9,7][ring],age=motion.age(t),delay=0.10*Float(ring)
            let turn=max(0,min(1,(age-delay)/0.32)),open=lift*turn*turn*(3-2*turn)
            for j in 0..<count {
                let n=Self.noise(47+19*ring+j),a=2*Float.pi*(Float(j)+Float(ring)*0.41+0.075*(n-0.5))/Float(count)+0.17
                let ray=radial(a),back=sin(a),sway=radial(a + .pi/2)*(0.047*(n-0.46))
                let from=root+size*(ray*(0.075+0.066*Float(ring))+axis*(0.066*Float(ring)))
                let span=(reach[ring]+open*(ring==0 ? 0.23 : 0.19))*(0.91+0.13*n+0.054*back)
                let height=rise[ring]+0.066*(n-0.5)+0.061*back-open*(0.22+Float(ring)*0.042)
                let tip=from+size*(ray*span+axis*height+sway)
                let tone=0.21+0.17*Float(ring)+0.22*n
                let dye=simd_mix(C.moonSilk,C.blush,SkyPoint(repeating:tone))
                vane(from,tip,size*width[ring]*(0.90+0.17*n),axis-ray*0.22,dye,.lotusTepal,.lotusSilk)
            }
        }
        // The flat top and the sockets share a tangent frame, so none of the
        // seeds hover when the bloom tips in response to a brush.
        let rot=simd_float3x3(columns:(right,axis,up)),top=heart+axis*(size*0.225)
        primitive(.bead,heart+axis*size*0.106,.init(0.132,0.155,0.125)*size,C.bud,rot,0,.matte)
        primitive(.bead,top,.init(0.173,0.050,0.158)*size,C.gold*0.83+C.bud*0.12,rot,0,.matte)
        for j in 0..<8 {
            let r=0.125*sqrt((Float(j)+0.33)/8),q=top+size*(radial(Float(j)*2.39996)*r+axis*0.042)
            primitive(.bead,q,.init(0.013,0.006,0.011)*size,C.hay*0.64+C.bud*0.20,rot,0,.cutInk)
        }
        for j in 0..<27 {
            let n=Self.noise(j+93),a=Float(j)*2.39996,ray=radial(a)
            let from=heart+ray*(0.119*size),tip=heart+size*(ray*(0.210+0.081*n+0.065*lift)+axis*(0.123+0.12*n))
            rod(from,tip,0.008*size,C.ivory,0,.matte)
            taper(tip,tip+(axis*0.053+ray*0.025)*size,size*0.016,size*0.014,C.gold,.matte)
        }
    }

}
