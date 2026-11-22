import Metal
import simd
import Foundation
import CryptoKit

/// Mac-only evidence from the actual GPU programs. Paired draws hold both scene time and sky time;
/// pixel differences cannot be attributed to drifting clouds or ambient animation.
enum SeasonalProbe {
    struct Failure:Error,CustomStringConvertible { let description:String; init(_ s:String){description=s} }
    struct Frame {
        let bytes:Data, picks:[UInt16], width:Int
        func hit(_ id:SeasonalTarget) -> (Int,SkyPoint)? {
            let height = picks.count/2/width
            var candidates:[Int] = []
            for j in stride(from:0,to:picks.count,by:2) where Float16(bitPattern:picks[j])==Float16(id.rawValue) {
                candidates.append(j/2)
            }
            guard !candidates.isEmpty else { return nil }
            let index = candidates[candidates.count/2]
            let uv = SIMD2((Float(index%width)+0.5)/Float(width),(Float(index/width)+0.5)/Float(height))
            return (candidates.count,simd_normalize(SeasonalScene.slope(uv,aspect:Float(width)/Float(height)))
                    * Float(Float16(bitPattern:picks[index*2+1])))
        }
        func nearest(_ target:SeasonalTarget,to wanted:SIMD2<Float>) -> (world:SkyPoint, pixel:SIMD2<Int>)? {
            let height=picks.count/(2*width)
            var best=Float.greatestFiniteMagnitude, result:(SkyPoint,SIMD2<Int>)?
            for i in stride(from:0,to:picks.count,by:2) where picks[i]==Float16(target.rawValue).bitPattern {
                let pixel=SIMD2(i/2%width,i/2/width)
                let uv=(SIMD2<Float>(Float(pixel.x),Float(pixel.y))+0.5)/SIMD2(Float(width),Float(height))
                let d=simd_length_squared(uv-wanted)
                if d<best {
                    best=d
                    result=(simd_normalize(SeasonalScene.slope(uv,aspect:Float(width)/Float(height)))
                            * Float(Float16(bitPattern:picks[i+1])),pixel)
                }
            }
            return result
        }
        func changed(_ other:Frame, near pixel:SIMD2<Int>? = nil, radius:Int = 0) -> Int {
            bytes.withUnsafeBytes { (a:UnsafeRawBufferPointer) in other.bytes.withUnsafeBytes { (b:UnsafeRawBufferPointer) in
                var n=0
                for i in stride(from:0,to:a.count,by:4) {
                    if let pixel,abs(i/4%width-pixel.x)>radius || abs(i/4/width-pixel.y)>radius { continue }
                    if abs(Int(a[i])-Int(b[i]))+abs(Int(a[i+1])-Int(b[i+1]))+abs(Int(a[i+2])-Int(b[i+2]))>12 {n+=1}
                }
                return n
            } }
        }
    }
    static func run(renderer:VolumetricSky,target:MTLTexture,pass:MTLRenderPassDescriptor,output:URL,mode:String) throws {
        let w=target.width,h=target.height,row=((w*4+255)/256)*256
        guard renderer.supportsSeasonalScenes,
              let targets=SeasonalTargets(device:renderer.device,width:w,height:h),
              let read=renderer.device.makeBuffer(length:row*h,options:.storageModeShared) else { throw Failure("No seasonal GPU pipeline") }
        // A portrait is a 1:1 sensor crop of a newly rasterized large frame, not a
        // digital enlargement or a close wide-angle lens that distorts the skull.
        var portrait:(texture:MTLTexture,pass:MTLRenderPassDescriptor,targets:SeasonalTargets)?
        if mode == "sparrow" {
            let scale=min(3.03,min(4200/Double(w),3000/Double(h)))
            let sw=Int(Double(w)*scale),sh=Int(Double(h)*scale)
            let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:target.pixelFormat,width:sw,height:sh,mipmapped:false)
            d.usage = .renderTarget; d.storageMode = .shared
            guard let image=renderer.device.makeTexture(descriptor:d),
                  let attachments=SeasonalTargets(device:renderer.device,width:sw,height:sh) else {throw Failure("Portrait sensor")}
            let p=MTLRenderPassDescriptor(); p.colorAttachments[0].texture=image
            p.colorAttachments[0].loadAction = .dontCare; p.colorAttachments[0].storeAction = .store
            portrait=(image,p,attachments)
        }
        func draw(_ f:Festival,_ t:Float = 2.35,_ motion:SeasonalMotion = .init(),offset:SkyPoint = .zero,
                  weather:Weather = .sunny, minute:Int? = nil, bare:Bool = false, turn:Float = 0,
                  cropped:Bool = false, skyClock:Double? = nil) throws -> Frame {
            let sensor=cropped ? portrait : nil
            let final=sensor?.texture ?? target, attachments=sensor?.targets ?? targets, renderPass=sensor?.pass ?? pass
            let ox=sensor == nil ? 0 : min(final.width-w,Int(Float(final.width)*0.778)-w/2)
            let oy=sensor == nil ? 0 : min(final.height-h,Int(Float(final.height)*0.725)-h/2)
            let day = Festival.solarTerms.contains(f) || [.newyear,.doubleNinth,.dragonBoat].contains(f)
            let s=VolumetricSkyState(time:.init(minute:minute ?? (day ? 760 : 1260)),style:weather.style,festival:f)
            var u=s.uniforms(width:final.width,height:final.height,steps:88,elapsed:skyClock ?? 1.5,moving:skyClock != nil)
            u.camera = .init(offset,0)
            var scene = bare ? nil : SkyDetails.scene(f,aspect:u.viewport.x,time:t,motion:motion,moon:u.moon)
            if turn != 0 {
                // A test turntable, not a second model: retain the original habitat and optical path.
                var turned=SeasonalScene(aspect:u.viewport.x,t:t,motion:motion)
                turned.foregroundReach = .greatestFiniteMagnitude;turned.setting(f);turned.frameStudy(f);turned.basis=turned.basis*SeasonalScene.rotation(.init(0,turn,0))
                turned.winterStudy(f); scene=turned
            }
            guard let cmd=renderer.queue.makeCommandBuffer(),renderer.encode(u,in:cmd,to:renderPass,scene:scene,targets:attachments)
            else { throw Failure("encode: "+f.id) }
            if !bare {
                guard let blit=cmd.makeBlitCommandEncoder() else { throw Failure("Readback") }
                blit.copy(from:attachments.picks,sourceSlice:0,sourceLevel:0,sourceOrigin:.init(x:ox,y:oy,z:0),
                          sourceSize:.init(width:w,height:h,depth:1),to:read,destinationOffset:0,
                          destinationBytesPerRow:row,destinationBytesPerImage:row*h)
                blit.endEncoding()
            }
            cmd.commit(); cmd.waitUntilCompleted()
            guard cmd.status == .completed else { throw cmd.error ?? Failure("GPU: "+f.id) }
            var pixels=Data(count:w*h*4)
            pixels.withUnsafeMutableBytes { final.getBytes($0.baseAddress!,bytesPerRow:w*4,
                                                           from:MTLRegionMake2D(ox,oy,w,h),mipmapLevel:0) }
            var picks:[UInt16]=[]
            if !bare {
                let ptr=read.contents().assumingMemoryBound(to:UInt16.self)
                picks.reserveCapacity(w*h*2)
                for y in 0..<h { picks.append(contentsOf:UnsafeBufferPointer(start:ptr+y*row/2,count:w*2)) }
            }
            return Frame(bytes:pixels,picks:picks,width:w)
        }
        func save(_ frame:Frame,_ name:String) throws {
            try RenderSky.write(frame.bytes,width:w,height:h,to:output.appendingPathComponent(name+".png"))
        }
        if mode == "impression-reel" {
            try SeasonalImpressionProbe.reel(draw:{ f,t,m,weather,minute in
                try draw(f,t,m,weather:weather,minute:minute,skyClock:1.5+Double(t))
            },save:save)
            return
        }
        if mode == "contact-reel" {
            try SeasonalFestivalProbe.contactReels(aspect:Float(w)/Float(h),draw:{ f,t,m,weather,minute in
                try draw(f,t,m,weather:weather,minute:minute,skyClock:1.5+Double(t))
            },save:save)
            return
        }
        if mode == "prints" {
            for f in Festival.allCases where f != .none {
                let light=SeasonalFestivalProbe.printLight(f), motion=SeasonalMotion(seed:51951)
                // Use the App camera, not the optional near-camera study. Render
                // the same native pixels as a visitor choosing this weather/clock.
                let plate=try draw(f,2.35,motion,weather:light.weather,minute:light.minute)
                try save(plate,f.id)
            }
            print("Rendered the complete almanac at native framing.")
            return
        }
        if mode=="festive" || mode=="reel" {
            var haunting=SeasonalMotion()
            let start:Float=0.8
            guard haunting.touch(.subject,scene:.halloween,time:start,point:.zero,chance:1) else {throw Failure("Ignition")}
            let a=SeasonalMotion(seed:18231),b=SeasonalMotion(seed:51951)
            if mode=="reel" {
                // Fresh production draws with both clocks running; 128 real frames
                // per scene. Nothing from this developer recorder enters the App.
                for i in 0..<128 {
                    let t=Float(i)/16,clock=Double(t)+1.5,number=String(format:"%03d",i)
                    for (f,m) in [(Festival.spring,a),(.lantern,b),(.halloween,t>=start ? haunting : .init()),(.dragonBoat,a),(.qixi,a)] {
                        try save(draw(f,t,m,skyClock:clock),f.id+"-"+number)
                    }
                }
                return
            }
            for f:Festival in [.spring,.lantern] {
                let first=try draw(f,1.7,a)
                guard try draw(f,1.7,a).bytes==first.bytes, try draw(f,1.7,b).changed(first)>120,
                      try draw(f,2.30,a).changed(first)>50 else {throw Failure("Seed / replay / timeline "+f.id)}
                try save(first,f.id+"-seed-a");try save(draw(f,1.7,b),f.id+"-seed-b")
            }
            try SeasonalFestivalProbe.lanternDepths(aspect:Float(w)/Float(h),visit:b)
            let inert=try draw(.halloween,1.04),lit=try draw(.halloween,1.04,haunting)
            func green(_ f:Frame)->Int {
                var n=0
                for i in 0..<w*h where f.picks[2*i]==Float16(SeasonalTarget.subject.rawValue).bitPattern {
                    if Int(f.bytes[4*i+1])>Int(f.bytes[4*i+2])+32 && f.bytes[4*i+1]>115 {n+=1}
                }
                return n
            }
            guard inert.hit(.subject) != nil,green(lit)>green(inert)+w*h/5000 else {throw Failure("No green fire in the lantern openings")}
            try save(inert,"lantern-amber");try save(lit,"lantern-green");try save(draw(.halloween,2.53,haunting),"lantern-turn")
            let rb=try draw(.midautumn,2.35),sky=try draw(.midautumn,2.35,bare:true)
            let moon=VolumetricSkyState.moon(at:1260,autumn:true),ap=Float(w)/Float(h)
            let mx=Int((0.5+(moon.x/moon.z-SeasonalScene.yaw(ap))/(0.86*ap))*Float(w))
            let my=Int((1-(moon.y/moon.z-0.102)/0.86)*Float(h))
            var lo=w,hi = -1, moonPixels=0
            for i in 0..<w*h where rb.picks[2*i]==Float16(SeasonalTarget.rabbit.rawValue).bitPattern {
                lo=min(lo,i%w);hi=max(hi,i%w)
            }
            if (0..<h).contains(my) {
                for x in max(0,mx-h/9)..<min(w,mx+h/9) {
                    let j=4*(my*w+x)
                    if sky.bytes[j+2]>164 && sky.bytes[j+1]>144 && Int(sky.bytes[j+2])-Int(sky.bytes[j])>22 {moonPixels+=1}
                }
            }
            let ratio=Float(hi-lo+1)/Float(max(1,moonPixels))
            guard (0.74...0.87).contains(ratio) else {throw Failure("Rabbit/moon optical size: "+String(ratio))}
            let cloudTown=try draw(.newyear,weather:.overcast)
            try SeasonalFestivalProbe.wallInteriors(cloudTown,renderer:renderer,targets:targets,height:h)
            try save(cloudTown,"town-overcast")
            print("PASS: visit seeds/replay, advancing events, green openings (\(green(lit)) pixels); hare \(hi-lo+1) px / moon \(moonPixels) px = \(ratio)")
            return
        }
        if mode == "sparrow" {
            let composition=try draw(.lesserCold), side=try draw(.lesserCold,cropped:true)
            let oblique=try draw(.lesserCold,turn:0.88,cropped:true)
            let opposite=try draw(.lesserCold,turn:2.55,cropped:true)
            guard let hit=composition.hit(.subject),let profile=side.hit(.subject), profile.0>w*h/26, oblique.changed(side)>w*h/30,
                  opposite.hit(.subject) != nil, try draw(.lesserCold,cropped:true).bytes==side.bytes
            else {throw Failure("Sparrow coverage, second flank or deterministic replay")}
            var motion=SeasonalMotion()
            guard motion.touch(.subject,scene:.lesserCold,time:2.05,point:hit.1,chance:1) else {throw Failure("Subject touch")}
            try SeasonalSparrowProbe.check(aspect:Float(w)/Float(h),motion:motion)
            let response=try draw(.lesserCold,2.35,motion,cropped:true)
            guard response.changed(side)>w*h/200 else {throw Failure("No visible feather response")}
            try save(composition,"composition"); try save(side,"profile"); try save(oblique,"three-quarter")
            try save(opposite,"opposite"); try save(response,"ruffled")
            try save(draw(.lesserCold,weather:.cloudy,minute:548,cropped:true),"morning")
            print("PASS: sparrow portrait, two turned views, repeat, contact; \(profile.0) visible subject pixels")
            return
        }
        if mode == "study" {
            // Actual displaced camera, not an enlarged screenshot. Use one whole frame
            // and a near camera for every recipe, including small props in the flight scenes.
            let ap=Float(w)/Float(h), time:Float=2.35
            for f in Festival.allCases where f != .none {
                var focus=SIMD3<Float>(0.76,0.74,6.8), ratio:Float=0.66
                if let actor=SeasonalMotion.flight(f,time:time,landing:nil) {
                    focus=actor; ratio = f == .midautumn ? 0.37 : 0.53
                } else {
                    switch f {
                    case .lantern: focus = .init(0.84,0.29,5.9); ratio=0.59
                    case .spring: focus = .init(0.64,0.34,13); ratio=0.70
                    case .qixi: focus = .init(0.53,0.37,10);ratio=0.60
                    case .newyear,.lunarEve: focus = .init(0.62,0.90,12);ratio=0.74
                    case .halloween: focus = .init(0.77,0.72,6.8);ratio=0.50
                    case .doubleNinth: focus = .init(0.70,0.80,13)
                    case .thanksgiving: focus = .init(0.74,0.65,6.9)
                    case .dragonBoat: focus = .init(0.72,0.79,6.9)
                    case .yearEve: focus = .init(0.53,0.84,8)
                    default:break
                    }
                }
                let at=SeasonalScene.slope(.init(focus.x,focus.y),aspect:ap)*focus.z
                let offset=at-SeasonalScene.slope(.init(0.51,0.55),aspect:ap)*focus.z*ratio
                try save(draw(f,time),f.id)
                try save(draw(f,time,offset:offset),f.id+"-detail")
                // Same app controls, real cloud field and close camera; not a graded render.
                let light:[Festival:(Weather,Int)]=[.heavySnow:(.lightSnow,650),.greaterCold:(.cloudy,565),
                    .whiteDew:(.cloudy,523),.greaterHeat:(.cloudy,899),.spring:(.cloudy,1230),
                    .lantern:(.cloudy,1190),.christmas:(.cloudy,1220),.midautumn:(.cloudy,1280),
                    .awakening:(.cloudy,879),.thanksgiving:(.sunny,1040),.endOfHeat:(.sunny,1020)]
                if let condition=light[f] {
                    try save(draw(f,time,offset:offset,weather:condition.0,minute:condition.1),f.id+"-sky")
                }
            }
            return
        }
        try SeasonalImpressionProbe.check(aspect:Float(w)/Float(h))
        var fingerprints=Set<Data>()
        for f in Festival.allCases where f != .none {
            let base=try draw(f), bare=try draw(f,bare:true)
            let visible=base.changed(bare)
            guard visible>35 else {throw Failure("No visible geometry: "+f.id+" pixels="+String(visible))}
            guard fingerprints.insert(Data(SHA256.hash(data:base.bytes))).inserted else {throw Failure("Duplicate scene: "+f.id)}
            try save(base,f.id)
            var result="\(f.id): \(visible) art pixels"
            if Festival.solarTerms.contains(f) {
                guard let hit=base.hit(.subject) else {throw Failure("No touchable subject: "+f.id)}
                var motion=SeasonalMotion()
                guard motion.touch(.subject,scene:f,time:2.05,point:hit.1,chance:1) else {throw Failure("Rejected "+f.id)}
                let response=try draw(f,2.35,motion), count=base.changed(response)
                guard count>5 else {throw Failure("No response: "+f.id+" pixels="+String(count))}
                if f == .awakening {
                    let tucked=response.hit(.subject)?.0 ?? 0
                    guard tucked<hit.0/2 else {throw Failure("Retreating beetle is still exposed")}
                }
                if [.awakening,.greaterCold,.whiteDew,.heavySnow].contains(f) {try save(response,f.id+"-touch")}
                result += ", \(hit.0) pickable pixels, \(count) changed on touch"
            }
            print(result)
        }
        let pool=try draw(.springRain)
        guard let left=pool.nearest(.water,to:.init(0.23,0.89)),let right=pool.nearest(.water,to:.init(0.79,0.89)),
              right.pixel.x-left.pixel.x > w/3 else { throw Failure("No separated visible water targets") }
        for (n,contact,remote) in [(0,left,right),(1,right,left)] {
            var wave=SeasonalMotion()
            _=wave.touch(.water,scene:.springRain,time:1.88,point:contact.world,chance:0)
            let wet=try draw(.springRain,2.35,wave), radius=h/7
            let local=wet.changed(pool,near:contact.pixel,radius:radius),far=wet.changed(pool,near:remote.pixel,radius:radius)
            guard local>max(12,far*3) else {throw Failure("Wave is not local to touch \(n): \(local)/\(far)")}
            if n==1 {try save(wet,"water-contact")}
        }
        for (f,id) in [(Festival.midautumn,SeasonalTarget.rabbit),(.christmas,.sleigh)] {
            let before=try draw(f,0)
            guard let hit=before.hit(id) else {throw Failure("No pickable actor: "+f.id)}
            var motion=SeasonalMotion()
            let scene = SkyDetails.scene(f,aspect:Float(w)/Float(h),time:0,motion:motion)
            if id == .sleigh && scene?.parcelOrigin == nil { throw Failure("No gift bag on sleigh") }
            _=motion.touch(id,scene:f,time:0,point:scene?.parcelOrigin ?? hit.1,chance:0.1)
            let with=try draw(f,0.80,motion),without=try draw(f,0.80)
            guard with.changed(without)>6 else {throw Failure("Actor did not respond: "+f.id)}
            if id == .sleigh {
                // Gift geometry is separate, so the *pixel coordinates* of the flying actor stay the same.
                let a = with.picks.enumerated().filter{$0.offset%2==0 && Float16(bitPattern:$0.element)==4}.map(\.offset)
                let b = without.picks.enumerated().filter{$0.offset%2==0 && Float16(bitPattern:$0.element)==4}.map(\.offset)
                let sa=Set(a),sb=Set(b)
                // A parcel can temporarily occlude the rider at release; it cannot create a sleigh pixel elsewhere.
                guard !sa.isEmpty,sa.isSubset(of:sb),Float(sa.count)/Float(sb.count)>0.8 else {throw Failure("Gift displaced sleigh: \(sa.count)/\(sb.count), new pixels \(sa.subtracting(sb).count)")}
            }
            try save(with,f.id+"-touch")
        }
        let normal=try draw(.lantern), side=try draw(.lantern,offset:.init(0.72,0.13,0.11))
        guard side.changed(normal)>w*h/80, try draw(.lantern).bytes==normal.bytes else { throw Failure("View or freeze invariant") }
        try save(side,"lantern-second-camera")
        let cloudy=try draw(.midautumn,0,offset:.zero,weather:.overcast), clear=try draw(.midautumn,0)
        // The same actor and projection have fewer pickable fragments behind the volumetric deck.
        let ca=cloudy.hit(.rabbit)?.0 ?? 0,cb=clear.hit(.rabbit)?.0 ?? 0
        guard ca<cb else {throw Failure("Cloud occlusion did not change coverage: \(ca)/\(cb)")}
        try save(cloudy,"rabbit-clouds")
        print("PASS: all dated scenes, all 24 geometric touch responses, hit-local water, two flights, gift invariance, second camera, freeze and cloud occlusion (\(ca)/\(cb))")
    }
}
