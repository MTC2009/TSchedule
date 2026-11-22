import Foundation
import simd

/// Geometry contracts that a still PNG cannot prove. Sample the actual assembled
/// meshes in their final frame, not the input constants of the authoring recipe.
enum SeasonalImpressionProbe {
    private static func point(_ v:SIMD4<Float>)->SkyPoint {.init(v.x,v.y,v.z)}
    private static func scene(_ f:Festival,_ aspect:Float,_ t:Float,_ m:SeasonalMotion) throws ->SeasonalScene {
        guard let s=SkyDetails.scene(f,aspect:aspect,time:t,motion:m) else {throw SeasonalProbe.Failure("Missing plate: "+f.id)}
        return s
    }
    static func check(aspect:Float) throws {
        let m=SeasonalMotion(seed:51951)
        // Validate chassis contact and both ends of a stroke for *each* blade;
        // comparing two entire images would also pass a paddle waving in the air.
        var wet=Set<Int>(),dry=Set<Int>(),bladeCount=0
        for frame in 0..<42 {
            let s=try scene(.dragonBoat,aspect,0.25+Float(frame)*0.051,m)
            guard let plane=s.waterPlane,let hull=s.instances[SeasonalShape.raceHull.rawValue].first else {
                throw SeasonalProbe.Failure("No hull/water plane")
            }
            let unit=simd_length(point(hull.x))
            func distance(_ p:SkyPoint)->Float {simd_dot(plane,.init(p,1))/unit}
            func onHull(_ local:SkyPoint)->SkyPoint {
                point(hull.center)+point(hull.x)*local.x+point(hull.y)*local.y+point(hull.z)*local.z
            }
            for f:Float in [0.24,0.53,0.74] {
                let section=SeasonalRegatta.section(f)
                guard distance(onHull(section.station(0,0))) < -0.03,
                      distance(onHull(section.station(1,-1))) > 0.035,
                      distance(onHull(section.station(1,1))) > 0.035 else {throw SeasonalProbe.Failure("Hull separated from or flooded by its mirror plane")}
            }
            let blades=s.instances[SeasonalShape.paddleBlade.rawValue];bladeCount=blades.count
            for (j,b) in blades.enumerated() {
                let tip=distance(point(b.center)+point(b.y)),root=distance(point(b.center)-point(b.y))
                if tip < -0.043 && root>tip+0.06 {wet.insert(j)}
                if tip > 0.071 {dry.insert(j)}
            }
        }
        guard bladeCount>=8,wet.count==bladeCount,dry==wet else {throw SeasonalProbe.Failure("Not every paddle enters / leaves the water")}

        let a=try scene(.qixi,aspect,1.0,m),b=try scene(.qixi,aspect,3.0,m)
        let flock=a.instances[SeasonalShape.magpieCut.rawValue],next=b.instances[SeasonalShape.magpieCut.rawValue]
        let dx=zip(flock,next).map{$1.center.x-$0.center.x}
        guard dx.contains(where:{$0>0.36}),dx.contains(where:{$0 < -0.36}),
              a.instances[SeasonalShape.weaverCut.rawValue].count==1,a.instances[SeasonalShape.herdsmanCut.rawValue].count==1
        else {throw SeasonalProbe.Failure("Flock pinned to span or duplicated figures")}

        // Centre the window differently or make it unusually wide: a wrapped
        // bird must never teleport across visible sky, nor a prow leave a narrow print.
        func screenX(_ p:SkyPoint,_ ratio:Float)->Float {
            0.5+(p.x/p.z-SeasonalScene.yaw(ratio))/(SeasonalScene.span*ratio)
        }
        for ratio:Float in [0.62,0.75] {
            for t:Float in [0,12.2,36.5] {
                let boat=try scene(.dragonBoat,ratio,t,m)
                guard let prow=boat.instances[SeasonalShape.prowCut.rawValue].first,
                      let hull=boat.instances[SeasonalShape.raceHull.rawValue].first else {throw SeasonalProbe.Failure("No narrow-frame boat")}
                let nose=point(prow.center)+point(prow.x)*1.06+point(prow.y)*0.34
                let stern=point(hull.center)-point(hull.x)*1.66+point(hull.y)*0.47
                guard screenX(nose,ratio)<0.985,screenX(stern,ratio)>0.015 else {throw SeasonalProbe.Failure("Clipped regatta in compact viewport")}
            }
        }
        let wide:Float=2.2
        var previous:[Float]=[],wraps=0
        for f in 0..<80 {
            let flock=try scene(.qixi,wide,Float(f)*0.44,m).instances[SeasonalShape.magpieCut.rawValue]
            let now=flock.map{screenX(point($0.center),wide)}
            for (old,new) in zip(previous,now) where abs(old-new)>0.72 {
                wraps+=1
                guard (old<0 || old>1) && (new<0 || new>1) else {throw SeasonalProbe.Failure("Flock wrapped in view")}
            }
            previous=now
        }
        guard wraps>0 else {throw SeasonalProbe.Failure("Wide window wrap not sampled")}
        let time:Float=1.60,rest=try scene(.coldDew,aspect,time,m)
        let dew=rest.refractors[SeasonalShape.bead.rawValue,default:[]]
        guard dew.count>=8 else {throw SeasonalProbe.Failure("Missing web condensate")}
        func after(_ hit:SkyPoint)throws ->SeasonalScene {
            var touch=m
            guard touch.touch(.subject,scene:.coldDew,time:time-0.21,point:hit,chance:1) else {throw SeasonalProbe.Failure("Web input")}
            return try scene(.coldDew,aspect,time,touch)
        }
        let sorted=dew.sorted{$0.center.x<$1.center.x},left=try after(point(sorted[2].center)),right=try after(point(sorted[sorted.count-3].center))
        let ld=left.refractors[SeasonalShape.bead.rawValue,default:[]],rd=right.refractors[SeasonalShape.bead.rawValue,default:[]]
        guard ld.count==dew.count,rd.count==dew.count,
              zip(ld,rd).contains(where:{simd_distance(point($0.center),point($1.center))>0.026})
        else {throw SeasonalProbe.Failure("Moving the contact has no spatial effect on the web")}
        func woodenMembers(_ s:SeasonalScene)->[SIMD4<Float>] {
            s.instances.flatMap{$0}.filter{UInt32($0.extras.y)==SeasonalFinish.bark.rawValue && $0.extras.x==Float(SeasonalTarget.none.rawValue)}
                .flatMap{[$0.center,$0.x,$0.y,$0.z,$0.curve]}
        }
        guard !woodenMembers(rest).isEmpty,woodenMembers(rest)==woodenMembers(left) else {throw SeasonalProbe.Failure("Fixed fork follows silk")}

        let blossom=try scene(.greaterHeat,aspect,time,m)
        func axes(_ s:SeasonalScene) -> [SkyPoint] {
            let parts=s.instances[SeasonalShape.lotusTepal.rawValue]
            guard let sepal=parts.first(where:{UInt32($0.extras.y)==SeasonalFinish.foliage.rawValue}) else {return []}
            // Remove the rigid cant of the supporting stalk; it starts moving
            // before the inner whorl unfolds and is not petal articulation.
            let frame=simd_float3x3(columns:(simd_normalize(point(sepal.x)),simd_normalize(point(sepal.y)),simd_normalize(point(sepal.z))))
            return parts.filter{UInt32($0.extras.y)==SeasonalFinish.lotusSilk.rawValue}.map{frame.transpose*point($0.y)}
        }
        let petals=axes(blossom)
        guard let first=blossom.instances[SeasonalShape.lotusTepal.rawValue].first else {throw SeasonalProbe.Failure("No corolla")}
        var touch=m
        guard touch.touch(.subject,scene:.greaterHeat,time:time,point:point(first.center),chance:1) else {throw SeasonalProbe.Failure("Lotus input")}
        let early=axes(try scene(.greaterHeat,aspect,time+0.081,touch)),late=axes(try scene(.greaterHeat,aspect,time+0.53,touch))
        func distance(_ before:[SkyPoint],_ after:[SkyPoint])->[Float] {zip(before,after).map{simd_distance($0,$1)}}
        let opening=distance(petals,early),open=distance(petals,late)
        guard petals.count>=12,opening.contains(where:{$0>0.003}),opening.contains(where:{$0<0.0001}),
              open.allSatisfy({$0>0.026}),axes(try scene(.greaterHeat,aspect,time+5,touch))==petals
        else {throw SeasonalProbe.Failure("Corolla timing: early min/max \(opening.min() ?? -1)/\(opening.max() ?? -1), full minimum \(open.min() ?? -1)")}
        print("PASS: hull straddles the mirror; all \(bladeCount) paddles catch and recover; free flights cross both ways; local silk tension / static fork; staggered corolla")
    }

    /// Deliverable frames, separate from fixed clocks used for invariants. For
    /// the two responsive plates take a real visible pick when the contact begins.
    static func reel(draw:(Festival,Float,SeasonalMotion,Weather,Int)throws->SeasonalProbe.Frame,
                     save:(SeasonalProbe.Frame,String)throws->Void)throws {
        for f:Festival in [.dragonBoat,.qixi,.greaterHeat,.coldDew] {
            let light=SeasonalFestivalProbe.printLight(f)
            var motion=SeasonalMotion(seed:51951)
            for i in 0..<96 {
                let t=Float(i)/18
                if [.greaterHeat,.coldDew].contains(f) && i==20 {
                    let before=try draw(f,t,motion,light.weather,light.minute)
                    let aim:SIMD2<Float>=f == .greaterHeat ? .init(0.74,0.72) : .init(0.72,0.64)
                    guard let hit=before.nearest(.subject,to:aim),
                          motion.touch(.subject,scene:f,time:t,point:hit.world,chance:1) else {throw SeasonalProbe.Failure("Missed visible "+f.id)}
                }
                try save(draw(f,t,motion,light.weather,light.minute),f.id+"-"+String(format:"%03d",i))
            }
        }
    }
}
