import simd

/// The planking, painted sheer and seat ends all meet the same hull section.
enum SeasonalRegatta {
    struct Section {
        let x, rim, keel, beam: Float
        func station(_ height: Float,_ breadth: Float) -> SkyPoint {
            .init(x,keel+(rim-keel)*height,beam*breadth)
        }
    }
    static func section(_ f: Float) -> Section {
        let stern=1-f, tip=abs(2*f-1)
        let rim=0.123+0.205*pow(stern,5)+0.242*pow(f,5)
        let keel = -0.194+0.42*pow(tip,3.4)+0.054*pow(f,5)
        return .init(x:-1.53+3.08*f,rim:rim,keel:keel,beam:0.008+0.206*pow(max(0,sin(.pi*f)),0.64))
    }

    /// Local water is y=0 apart from the small hull roll. Keep reach and feather
    /// continuous through catch, drive, extraction and recovery (also when paused).
    struct Stroke {
        let top, tip, bladeRoot: SkyPoint
        let phase, reach: Float
    }
    static func stroke(x: Float, side: Float, clock: Float, level:(Float,Float)->Float) -> Stroke {
        let p=clock-floor(clock), theta=2*Float.pi*p
        let reach=cos(theta), wet=sin(theta), z=side*(0.285+0.058*(1-reach*reach)+0.026*wet)
        let bx=x+0.265*reach-0.028
        let tip=SkyPoint(bx,level(bx,z)-0.115*max(0,wet)+0.194*max(0,-wet),z)
        let top=SkyPoint(x+0.071+0.094*reach,0.407+0.063*max(0,-wet),0.023*side)
        return .init(top:top,tip:tip,bladeRoot:tip+simd_normalize(top-tip)*0.145,phase:p,reach:reach)
    }
}

extension SeasonalMeshAtlas.Mesh {
    mutating func regattaHull() {
        // From the outer lip round the keel and down the inside of the well.
        // A solid extruded side profile cannot share a waterline with its reflection.
        let shell:[SIMD2<Float>] = [.init(1,-1),.init(0.75,-0.94),.init(0.40,-0.75),.init(0.12,-0.42),
            .init(0,-0.12),.init(0,0.12),.init(0.12,0.42),.init(0.40,0.75),.init(0.75,0.94),.init(1,1),
            .init(1,0.84),.init(0.69,0.71),.init(0.38,0.48),.init(0.27,0.14),.init(0.27,-0.14),
            .init(0.38,-0.48),.init(0.69,-0.71),.init(1,-0.84)]
        for i in 0..<52 {
            let l=SeasonalRegatta.section(Float(i)/52),r=SeasonalRegatta.section(Float(i+1)/52)
            for j in shell.indices {
                let a=shell[j],b=shell[(j+1)%shell.count]
                face(l.station(a.x,a.y),r.station(a.x,a.y),r.station(b.x,b.y),l.station(b.x,b.y))
                if i==0 || i==51 {
                    let end=i==0 ? l : r, mid=end.station(0.64,0)
                    let x=end.station(a.x,a.y),y=end.station(b.x,b.y)
                    if i==0 {face(mid,x,y,y)} else {face(mid,y,x,x)}
                }
            }
        }
    }
}

extension SeasonalScene {
    mutating func riverRace() {
        place(0.50,0.781,8.1,0.18);water(.init(0,-0.18,0),width:1.65,pick:false)
        // A moving-camera composition: the hull tracks near the center but its
        // buoyancy comes from the very plane sampled by the mirror and the water pass.
        // Leave room for the projecting jaws and tail in a narrow iPad pane;
        // a wide landscape keeps its established viewing distance.
        let compact=min(1,max(0,(1.05-aspect)/0.34))
        let center=0.53-0.036*compact+(0.057-0.028*compact)*sin(t*0.129)
        place(center,0.81,7.91,0.182*min(1,aspect/0.92));focusZ=origin.z
        let offset=0.013+0.008*sin(t*3.9)
        guard let bearing=waterline else {return}
        origin=world(.init(0,bearing.height(0,0,clearance:offset),0))
        basis=basis*bearing.frame*Self.rotation(.init(0.019*sin(t*3.9),-0.10,0.008*sin(t*3.9-0.85)))
        guard let floated=waterline else {return}
        func level(_ x:Float,_ z:Float)->Float {floated.height(x,z)}

        let lacquer=C.berry*0.80+C.vermilion*0.38, lip=C.brass*0.69+C.gold*0.27
        part(.raceHull,.zero,.init(repeating:1),lacquer,.zero,0,.carvedInk)
        for side:Float in [-1,1] {
            for j in 0..<19 {
                let a=Float(j)/19,b=Float(j+1)/19
                func edge(_ f:Float,_ h:Float,_ w:Float)->SkyPoint {SeasonalRegatta.section(f).station(h,side*w)}
                arc(edge(a,1,0.96),edge((a+b)*0.5,1,0.96),edge(b,1,0.96),0.012,lip,5,0,.cutInk)
                if side<0 {
                    arc(edge(a,0.78,0.98),edge((a+b)*0.5,0.78,0.98),edge(b,0.78,0.98),0.0058,C.hay,4,0,.cutInk)
                }
            }
        }
        // Carved waves sit *on* the near plank. Their spacing opens up near the prow.
        for f:Float in [0.085,0.131,0.177,0.236,0.573,0.624,0.675,0.731,0.792,0.856] {
            let a=SeasonalRegatta.section(f),b=SeasonalRegatta.section(f+0.032),c=SeasonalRegatta.section(f+0.054)
            arc(a.station(0.53,-0.89),b.station(0.74,-0.96),c.station(0.68,-0.95),0.0064,C.copper*0.91+C.vermilion*0.34,5,0,.cutInk)
        }
        raceCarving()
        let clock=t*0.71
        for row in 0..<6 {
            let x = -1.069+Float(row)*0.305, seat=SeasonalRegatta.section((x+1.53)/3.08)
            part(.cube,.init(x,seat.rim-0.046,0),.init(0.054,0.013,seat.beam*0.92),C.umber,.zero,0,.cutInk)
            for side:Float in [1,-1] {
                let j=row*2+(side<0 ? 0 : 1),noise=Self.noise(j+58)
                let seatX=x+(side>0 ? -0.066 : 0)
                let stroke=SeasonalRegatta.stroke(x:seatX,side:side,clock:clock-Float(row)*0.027+0.035*noise+0.015*side,level:level)
                racePaddler(at:seatX,side:side,stroke:stroke,noise:noise,index:j)
                if stroke.phase>0.47 && stroke.phase<0.78 {
                    let u=(stroke.phase-0.47)/0.31
                    let ex=x-0.28-0.16*u,ez=side*(0.295+0.071*u),r=0.013+0.065*u
                    func crest(_ dx:Float,_ dz:Float)->SkyPoint {.init(ex+dx,level(ex+dx,ez+dz)+0.009,ez+dz)}
                    arc(crest(-r,side*r*0.85),crest(r*0.20,side*r),crest(r,0),0.0057*(1-u),C.riverMist,5,0,.cutInk)
                    if u<0.64 {
                        let p=crest(-r*0.58,side*r*0.24)+SkyPoint(0,0.082*sin(.pi*u/0.64),0)
                        part(.bead,p,.init(0.006,0.011,0.006)*(1-0.55*u),C.moonSilk,.zero,0,.cutInk)
                    }
                }
            }
        }
        raceDrummer(clock)
        for side:Float in [-1,1] {
            let cut:Float=1.09,beam=side*0.079
            func bowFoam(_ dx:Float,_ dz:Float)->SkyPoint {.init(cut+dx,level(cut+dx,beam+dz)+0.009,beam+dz)}
            arc(bowFoam(0.052,0),bowFoam(-0.013,side*0.067),bowFoam(-0.35,side*0.142),0.006,C.farIndigo*0.94,6,0,.cutInk)
            for j in 0..<2 {
                let k=Float(j),phase=t*0.93+1.9*k
                let x = -1.30-0.095*k-0.057*sin(phase),z=side*(0.075+0.070*k)
                func wake(_ dx:Float,_ dz:Float)->SkyPoint {.init(x+dx,level(x+dx,z+dz)+0.013,z+dz)}
                arc(wake(0.15,0),wake(-0.045,side*0.002),wake(-0.27-k*0.081,side*(0.086+k*0.037)),
                    0.006+0.002*cos(phase),C.farIndigo*(0.89+0.22*cos(phase)),6,0,.cutInk)
            }
        }
    }

    private mutating func racePaddler(at x:Float,side:Float,stroke:SeasonalRegatta.Stroke,noise:Float,index:Int) {
        let hip=SkyPoint(x,0.162+0.015*noise,side*0.093),size=0.262+0.040*noise,tilt = -0.18-0.37*stroke.reach
        let frame=Self.rotation(.init(side*0.12,-0.10*side,tilt))
        let coat=side>0 ? C.farIndigo*0.52+C.teal*0.23 : (index%3==0 ? C.teal*0.86 : C.teal*0.57+C.midnight*0.35)
        primitive(.oarsmanCut,hip,.init(repeating:size),coat,frame,0,.cutInk)
        let skin=C.hay*0.94+C.rose*0.20
        let mask=hip+frame*SkyPoint(0,0,-0.10*size)
        primitive(.rowerFaceCut,mask,.init(repeating:size),skin,frame,0,.carvedInk)
        let tie=hip+frame*(SkyPoint(-0.15,0.637,-0.137)*size)
        let brow=hip+frame*(SkyPoint(0.147,0.656,-0.140)*size)
        rod(tie,brow,0.027*size,C.vermilion,0,.cutInk)
        vane(tie,tie+SkyPoint(-0.054,-0.016+0.016*stroke.reach,0),0.009,.init(0,0,-1),C.berry,.feather,.cutInk)
        let oar=stroke.top-stroke.tip
        rod(stroke.top,stroke.bladeRoot,0.0089,C.hay+C.ivory*0.12,0,.cutInk)
        let feather=sin(.pi*max(0,(stroke.phase-0.50)*2))
        vane(stroke.bladeRoot,stroke.tip,0.036,.init(0.25+0.71*feather,0.19,-1+0.68*feather),C.copper*0.72,.paddleBlade,.cutInk)
        for hand in 0..<2 {
            let far=hand==0,grip=stroke.tip+oar*(far ? 0.98 : 0.57)
            let shoulder=hip+frame*(SkyPoint(far ? -0.095 : 0.036,0.31,(far ? 0.09 : -0.14))*size)
            let elbow=shoulder*0.54+grip*0.46+SkyPoint(far ? -0.037 : -0.019,far ? 0.031 : -0.036,0.032*side)
            rod(shoulder,elbow,far ? 0.015 : 0.020,coat,0,.cutInk)
            rod(elbow,grip,0.011,skin,0,.cutInk)
            part(.bead,grip,.init(repeating:0.014),skin,.zero,0,.cutInk)
        }
    }

    private mutating func raceDrummer(_ clock:Float) {
        let drum=SkyPoint(0.99,0.235,-0.018),beat=0.5-0.5*cos(clock*2 * .pi)
        part(.stem,drum,.init(0.146,0.082,0.132),C.berry,.zero,0,.cutInk)
        for sign:Float in [-1,1] {
            part(.stem,drum+SkyPoint(0,0.078*sign,0),.init(0.151,0.010,0.138),sign>0 ? C.ivory : C.hay,.zero,0,.cutInk)
        }
        for j in 0..<12 {
            let a=Float(j)*Float.pi/6,b=a+0.24
            rod(drum+SkyPoint(0.147*cos(a),0.067,0.133*sin(a)),drum+SkyPoint(0.146*cos(b),-0.066,0.132*sin(b)),0.0047,C.hay,0,.cutInk)
        }
        let p=SkyPoint(0.717,0.279,0.016),frame=Self.rotation(.init(0,0,-0.10))
        primitive(.oarsmanCut,p,.init(repeating:0.31),C.vermilion,frame,0,.cutInk)
        primitive(.rowerFaceCut,p+frame*SkyPoint(0,0,-0.032),.init(repeating:0.31),C.hay+C.rose*0.18,frame,0,.carvedInk)
        rod(p+frame*SkyPoint(-0.051,0.211,-0.047),p+frame*SkyPoint(0.046,0.206,-0.048),0.008,C.berry,0,.cutInk)
        for side:Float in [-1,1] {
            let f=side<0 ? beat : 1-beat,grip=drum+SkyPoint(-0.123,0.13+0.072*f,side*0.067)
            let elbow=grip+SkyPoint(-0.076,-0.028,side*0.019),end=drum+SkyPoint(0.025-0.058*f,0.096+0.22*f,side*0.052)
            rod(p+SkyPoint(-0.006,0.098,side*0.042),elbow,0.019,C.berry,0,.cutInk)
            rod(elbow,grip,0.014,C.hay,0,.cutInk);rod(grip,end,0.007,C.brass,0,.cutInk)
            part(.bead,end,.init(repeating:0.017),C.vermilion,.zero,0,.cutInk)
        }
    }

    private mutating func raceCarving() {
        let head=SkyPoint(1.419,0.382,-0.012),s:Float=0.51
        func h(_ x:Float,_ y:Float,_ z:Float)->SkyPoint {head+SkyPoint(x,y,z)*s}
        part(.prowCut,head,.init(s,s,1.36),C.berry+C.copper*0.82,.zero,0,.carvedInk)
        part(.scrollCut,h(-0.12,0.077,-0.11),.init(0.121,0.121,0.28),C.brass,.init(0,0,-0.35),0,.cutInk)
        arc(h(0.06,0.362,-0.117),h(0.19,0.454,-0.119),h(0.32,0.338,-0.118),0.011,C.gold,6,0,.cutInk)
        let eye=h(0.145,0.292,-0.125)
        part(.bead,eye,.init(0.033,0.012,0.0065),C.ivory,.init(0,0,-0.23),0,.cutInk)
        part(.bead,eye+SkyPoint(0.006,0,-0.006),.init(0.009,0.009,0.004),C.midnight,.zero,0,.cutInk)
        arc(h(0.48,0.275,-0.112),h(0.60,0.252,-0.112),h(0.70,0.312,-0.112),0.007,C.brass,5,0,.cutInk)
        arc(h(0.23,0.096,-0.105),h(0.47,-0.026,-0.105),h(0.666,0.051,-0.108),0.006,C.hay,5,0,.cutInk)
        for k in 0..<2 {
            let x=0.43+0.206*Float(k)
            part(.cone,h(x,0.11,-0.087),.init(0.011,0.021-0.007*Float(k),0.008),C.ivory,.init(0,0,.pi),0,.carvedInk)
        }
        for side:Float in [-1,1] {
            arc(h(-0.09,0.40,side*0.052),h(-0.26,0.68,side*0.20),h(-0.55,0.70,side*0.33),0.012,C.brass,6,0,.cutInk)
            rod(h(-0.27,0.61,side*0.17),h(-0.32,0.81,side*0.25),0.008,C.gold,0,.cutInk)
            arc(h(0.64,0.275,side*0.094),h(0.92,0.052,side*0.23),h(1.04,0.35,side*0.28),0.008,C.brass,7,0,.cutInk)
        }
        for k in 0..<3 {
            let f=Float(k),p=h(-0.28+0.03*f,0.11+0.08*f,-0.12)
            vane(p,p+SkyPoint(-0.22-0.035*f,0.041+0.075*f,0),0.027,.init(0,0,-1),k==1 ? C.vermilion : C.brass,.feather,.cutInk)
            let tail=SkyPoint(-1.43+0.016*f,0.271+0.016*f,0.01)
            vane(tail,tail+SkyPoint(-0.22+0.071*f,0.175+0.074*f,0),0.036,.init(0,0,-1),k==1 ? C.gold : C.vermilion,.feather,.cutInk)
        }
    }
}
