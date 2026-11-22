import simd

extension SeasonalScene {
    /// Each study has a distance and an entry edge, rather than the same object
    /// standing on the same strip of earth. X is expressed in viewport fractions:
    /// a narrow iPad column retains both its subject and breathing room for text.
    mutating func frameStudy(_ f:Festival) {
        let shot:(Float,Float,Float,Float,Float)
        switch f {
        case .springBegins: shot=(0.70,0.80,6.1,0.233,-0.21)
        case .springRain: shot=(0.59,0.78,7.0,0.250,-0.055)
        case .awakening: shot=(0.69,0.75,5.5,0.251,-0.19)
        case .springEquinox: shot=(0.53,0.64,9.4,0.246,0.08)
        case .qingming: shot=(0.76,0.64,7.6,0.245,-0.08)
        case .grainRain: shot=(0.65,0.77,6.6,0.213,0.18)
        case .summerBegins: shot=(0.64,0.80,6.2,0.223,-0.15)
        case .grainBuds: shot=(0.56,0.84,7.9,0.208,-0.22)
        case .grainInEar: shot=(0.57,0.83,8.1,0.257,0.10)
        case .summerSolstice: shot=(0.66,0.83,7.6,0.228,-0.18)
        case .lesserHeat: shot=(0.54,0.80,7.0,0.229,0.13)
        case .greaterHeat: shot=(0.72-0.042*min(1,max(0,(1.0-aspect)/0.33)),0.79,6.2,0.265,0.07)
        case .autumnBegins: shot=(0.66,0.69,6.3,0.229,0.19)
        case .endOfHeat: shot=(0.67,0.83,7.8,0.215,-0.27)
        case .whiteDew: shot=(0.69,0.76,5.4,0.261,-0.22)
        case .autumnEquinox: shot=(0.61,0.82,7.7,0.229,0.04)
        case .coldDew: shot=(0.69,0.68,5.9,0.231,0.13)
        case .frostDescent: shot=(0.73,0.83,6.2,0.241,-0.12)
        case .winterBegins: shot=(0.70,0.84,8.2,0.225,-0.29)
        case .lightSnow: shot=(0.61,0.80,7.9,0.224,0.17)
        case .heavySnow: shot=(0.59,0.84,7.3,0.212,-0.15)
        case .winterSolstice: shot=(0.49,0.83,8.6,0.201,0.19)
        case .lesserCold: shot=(0.76,0.765,6.8,0.275,-0.14)
        case .greaterCold: shot=(0.73,0.75,6.4,0.222,0.22)
        default: shot=(0.69,0.79,7,0.20,0)
        }
        place(shot.0,shot.1,shot.2,shot.3,shot.4);focusZ=shot.2
    }

    /// Background forms are intentionally few. A narrow rice terrace, a ridge of
    /// warm stubble and a snow bank have different horizons and scales. They never
    /// claim a gesture or occlude large portions of the existing cloud sky.
    mutating func setting(_ f:Festival) {
        target = .none
        func hills(_ s:inout SeasonalScene,_ v:Float,_ h:Float,_ key:Int,_ color:SkyPoint) {
            for j in 0..<2 {
                let n=Self.noise(key*17+j*31),d=Float(j);s.place(0.36+0.28*n,v+0.037*d,19-4*d,0.216,0)
                let tint=simd_mix(color,C.riverMist,SkyPoint(repeating:j==0 ? 0.55 : 0.21))
                s.part(.ridgeCut,.init((n-0.5)*1.37,0.02,0),.init(4.92,h*(1-0.15*d),1.6),tint,.init(0,n*0.14,0.02*(n-0.5)),0,.cutInk)
            }
        }
        func spray(_ s:inout SeasonalScene,_ u:Float,_ v:Float,_ length:Float,_ direction:Float,_ pigment:SkyPoint,_ key:Int) {
            s.place(u,v,11,0.149)
            for j in 0..<7 {
                let n=Self.noise(key*71+j),b=Self.noise(key+j*23),x=Float(j)*0.117
                let a=SkyPoint(x-0.29,-0.36-0.18*b,0.22*n)
                let e=a+SkyPoint(direction*(0.19+0.26*n),length*(0.44+0.55*b),0.09*n)
                s.vane(a,e,0.013+0.013*n,.init(0,0.3,-1),pigment*(0.77+0.22*n),.blade,.cutInk)
            }
        }
        func furrows(_ s:inout SeasonalScene,_ v:Float,_ color:SkyPoint,_ count:Int,_ steep:Float) {
            s.place(0.52,v,14,0.185,0.03)
            for j in 0..<count {
                let d=Float(j)/Float(count),x = -1.94+d*1.7
                let a=SkyPoint(x-1.04,-0.29-0.26*d,0),b=SkyPoint(x+1.22,0.11+steep*d,0.21)
                s.arc(a,(a+b)*0.5+SkyPoint(-0.36,0.18+0.12*d,0.11),b,0.010+0.014*(1-d),color*(0.73+0.19*d),8,0,.cutInk)
            }
        }
        switch f {
        case .springBegins:
            hills(&self,0.985,0.43,2,C.celadon)
            place(0.13,0.995,10,0.11);arc(.init(-1,-0.5,0),.init(-0.20,0.21,0),.init(0.24,0.37,0.07),0.019,C.umber)
            for i in 0..<4 {let a=SkyPoint(-0.29+0.14*Float(i),0.22+0.034*Float(i),0);taper(a,a-SkyPoint(0.018,0.13+0.028*Float(i%2),0),0.029,0.02,C.hay,.awn,.glume)}
        case .springRain:
            hills(&self,0.923,0.263,8,C.farIndigo);spray(&self,0.11,0.949,0.52,-1,C.celadon,3)
        case .awakening:
            place(0.64,1.025,8.9,0.174)
            for j in 0..<12 {let n=Self.noise(77+j),b=Self.noise(j*23);part(.rock,.init(-3.4+0.35*Float(j),-0.11+0.10*b,n*0.3),.init(0.11+0.15*n,0.055+0.068*b,0.07),C.umber*0.62+C.moss*0.24,.init(0,n,0),0,.soil)}
        case .springEquinox:
            hills(&self,0.851,0.45,7,C.farIndigo);furrows(&self,0.943,C.riverMist,3,0.16)
        case .qingming:
            hills(&self,0.906,0.48,11,C.teal)
            place(0.24,0.87,12,0.097);arc(.init(-0.62,-0.11,0),.init(0,0.32,0),.init(0.64,-0.09,0),0.035,C.slate,9,0,.cutInk)
            for x:Float in [-0.49,0.49] {rod(.init(x,-0.20,0),.init(x,0.018,0),0.042,C.slate,0,.cutInk)}
        case .grainRain:
            hills(&self,0.948,0.85,18,C.celadon);furrows(&self,0.969,C.teal,5,0.44)
        case .summerBegins:
            place(0.25,0.93,10.2,0.108)
            for j in 0..<3 {let q=Float(j);part(.pad,.init(-0.42+q*0.39,0.04*cos(q*3),0.16*q),.init(0.205+0.11*q,0.17,0.13+q*0.045),C.celadon,.init(-0.44,1.8*q,0),0,.leafPad)}
        case .grainBuds:
            hills(&self,0.931,0.32,21,C.hay);furrows(&self,0.965,C.hay*0.71,4,0.14);spray(&self,0.19,0.99,0.93,1,C.hay,8)
        case .grainInEar:
            hills(&self,0.924,0.42,25,C.celadon);furrows(&self,0.857,C.teal*0.73,5,0.31)
        case .summerSolstice:
            hills(&self,0.97,0.30,29,C.moss);spray(&self,0.22,1.004,0.57,-1,C.pine,19)
        case .lesserHeat:
            hills(&self,0.921,0.30,31,C.teal);spray(&self,0.90,0.95,1.12,-1,C.pine,23)
        case .greaterHeat:
            hills(&self,0.936,0.24,38,C.celadon);place(0.32,0.925,10.6,0.122)
            arc(.init(-0.19,-0.34,0),.init(-0.07,0.11,0),.init(-0.14,0.34,0),0.012,C.jade)
            taper(.init(-0.14,0.31,0),.init(-0.17,0.51,0),0.056,0.049,C.blush,.petal)
        case .autumnBegins:
            hills(&self,0.977,0.42,40,C.hay)
            place(0.22,0.89,10,0.115);part(.waveCut,.init(0,0,0),.init(0.46,0.28,0.67),C.hay*0.86,.init(0,0,-0.16),0,.cutInk)
        case .endOfHeat:
            hills(&self,0.96,0.37,44,C.hay);spray(&self,0.25,0.965,0.88,-1,C.hay,28)
        case .whiteDew:
            spray(&self,0.30,0.99,1.04,1,C.celadon,33)
        case .autumnEquinox:
            hills(&self,0.928,0.59,47,C.hay);furrows(&self,1.015,C.copper,3,0.37)
        case .coldDew:
            place(0.25,1.035,13,0.13);sprig(.init(-0.26,-0.32,0),0.51,0.24,4,C.farIndigo*0.61,blade:0.22)
        case .frostDescent:
            hills(&self,0.985,0.63,54,C.slate);spray(&self,0.26,1,0.53,1,C.ivory,49)
        case .winterBegins:
            hills(&self,0.973,0.59,56,C.umber);place(0.32,0.989,11,0.106)
            for j in 0..<6 {let n=Float(j);rod(.init(-0.3,0.10*(n/3).rounded(.down),n*0.03),.init(0.20+0.06*cos(n),0.10*(n/3).rounded(.down)+0.018,n*0.03),0.049,C.twig,0,.timber)}
        case .lightSnow:
            hills(&self,0.953,0.58,61,C.silver);spray(&self,0.19,0.975,0.79,1,C.silver,52)
        case .heavySnow:
            hills(&self,0.925,0.72,62,C.silver)
            place(0.25,0.998,10,0.166);part(.ridgeCut,.zero,.init(2.21,0.21,1),C.pearl,.zero,0,.cutInk)
        case .winterSolstice:
            hills(&self,0.935,0.27,65,C.slate);place(0.79,0.945,11,0.13)
            for j in 0..<5 {let f=Float(j);rod(.init(-0.68+0.25*f,-0.19,0),.init(-0.68+0.25*f,0.17-0.014*f,0),0.016,C.umber,0,.cutInk)}
            rod(.init(-0.82,0.097,0),.init(0.45,0.043,0),0.014,C.umber,0,.cutInk)
        case .lesserCold: break // The near branch is the only support in this portrait.
        case .greaterCold:
            hills(&self,0.977,0.44,70,C.farIndigo);place(0.23,0.986,12,0.12)
            arc(.init(-1.2,0.14,0),.init(-0.4,0.23,0),.init(0.21,-0.05,0),0.018,C.umber,6,0,.cutInk)
        default: break
        }
    }
}
