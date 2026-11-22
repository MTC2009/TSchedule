import Foundation
import Metal

/// Compare the final *overcast* town with its own opaque incoming radiance.
/// A simple difference between cloudy and clear tests cloud lighting as well as
/// visibility, so cannot detect scattering drawn over a perfectly solid wall.
enum SeasonalFestivalProbe {
    /// Examples of existing environment-panel settings, never a forecast or an
    /// override in the App. The regression catalog keeps its uniform lighting.
    static func printLight(_ f:Festival)->(weather:Weather,minute:Int) {
        switch f {
        case .newyear: (.cloudy,425)
        case .lunarEve: (.sunny,1170)
        case .spring,.halloween: (.sunny,1328)
        case .lantern: (.sunny,1155)
        case .dragonBoat: (.cloudy,865)
        case .qixi,.midautumn,.christmas,.christmasEve: (.sunny,1260)
        case .doubleNinth: (.sunny,1005)
        case .thanksgiving: (.sunny,1045)
        case .yearEve: (.sunny,1425)
        case .springBegins,.grainRain: (.cloudy,465)
        case .springRain: (.lightRain,572)
        case .awakening: (.overcast,725)
        case .springEquinox,.grainInEar: (.cloudy,830)
        case .qingming: (.lightRain,615)
        case .summerBegins,.greaterHeat: (.cloudy,690)
        case .grainBuds,.endOfHeat: (.sunny,995)
        case .summerSolstice: (.sunny,735)
        case .lesserHeat: (.sunny,1190)
        case .autumnBegins,.frostDescent: (.sunny,974)
        case .whiteDew: (.cloudy,435)
        case .autumnEquinox: (.sunny,1015)
        case .coldDew: (.cloudy,1065)
        case .winterBegins: (.cloudy,1064)
        case .lightSnow,.heavySnow: (.lightSnow,717)
        case .winterSolstice: (.sunny,973)
        case .lesserCold: (.cloudy,552)
        case .greaterCold: (.cloudy,937)
        case .none: (.sunny,760)
        }
    }
    /// Record the real response at a *visible* hit. This presents the same gesture as
    /// the fixture; no glyph or touch marker is burned into the Metal frames.
    static func contactReels(aspect:Float,draw:(Festival,Float,SeasonalMotion,Weather,Int)throws->SeasonalProbe.Frame,
                             save:(SeasonalProbe.Frame,String)throws->Void) throws {
        let plates=Festival.solarTerms+[.midautumn,.christmasEve,.christmas]
        for f in plates {
            let brush=[Festival.qingming,.grainBuds,.autumnBegins,.endOfHeat].contains(f)
            let light=printLight(f),target:SeasonalTarget=f == .midautumn ? .rabbit : ([.christmasEve,.christmas].contains(f) ? .sleigh : .subject)
            var m=SeasonalMotion(seed:51951)
            for i in 0..<64 {
                let t=Float(i)/16
                if i==13 {
                    let before=try draw(f,t,m,light.weather,light.minute)
                    guard let hit=before.hit(target) else {throw SeasonalProbe.Failure("No visible hit for "+f.id)}
                    let bag=target == .sleigh ? SkyDetails.scene(f,aspect:aspect,time:t,motion:m)?.parcelOrigin : nil
                    guard m.touch(target,scene:f,time:t,point:bag ?? hit.1,chance:0.10,holding:brush) else {
                        throw SeasonalProbe.Failure("Rejected visible contact "+f.id)
                    }
                }
                if brush && (14...26).contains(i) {m.pull(Float(i-13)/13*0.84)}
                if brush && i==27 {m.release(at:t)}
                if f == .springRain && i==39 {
                    let pond=try draw(f,t,m,light.weather,light.minute)
                    guard let wet=pond.nearest(.water,to:.init(0.60,0.90)),
                          m.touch(.water,scene:f,time:t,point:wet.world,chance:1) else {throw SeasonalProbe.Failure("Water contact")}
                }
                try save(draw(f,t,m,light.weather,light.minute),f.id+"-"+String(format:"%03d",i))
            }
        }
        print("Recorded all 24 solar-term contacts and the three flying scenes.")
    }

    static func wallInteriors(_ frame:SeasonalProbe.Frame,renderer:VolumetricSky,targets:SeasonalTargets,height h:Int)throws {
        let w=frame.width,source=targets.opaque(fineEdges:true).color,scale=source.width/w
        let row=(source.width*8+255)/256*256
        guard let buffer=renderer.device.makeBuffer(length:row*source.height,options:.storageModeShared),
              let cmd=renderer.queue.makeCommandBuffer(),let blit=cmd.makeBlitCommandEncoder() else {throw SeasonalProbe.Failure("Opaque read")}
        blit.copy(from:source,sourceSlice:0,sourceLevel:0,sourceOrigin:.init(),
            sourceSize:.init(width:source.width,height:source.height,depth:1),to:buffer,destinationOffset:0,
            destinationBytesPerRow:row,destinationBytesPerImage:row*source.height)
        blit.endEncoding();cmd.commit();cmd.waitUntilCompleted()
        guard cmd.status == .completed else {throw SeasonalProbe.Failure("Town readback")}
        let data=buffer.contents().assumingMemoryBound(to:UInt16.self)
        func q(_ x:Int,_ y:Int)->SIMD4<Float> {
            let i=y*scale*row/2+x*scale*4
            return .init(Float(Float16(bitPattern:data[i])),Float(Float16(bitPattern:data[i+1])),
                Float(Float16(bitPattern:data[i+2])),Float(Float16(bitPattern:data[i+3])))
        }
        func srgb(_ v:Float)->Int {
            Int((255*min(1,max(0,v<=0.0031308 ? 12.92*v : 1.055*pow(v,1/2.4)-0.055))).rounded())
        }
        var checked=0,matched=0
        for y in stride(from:h*5/9,to:h*9/10,by:2) {for x in stride(from:3,to:w-3,by:2) {
            let c=q(x,y)
            guard c.w>1,c.w<16 else {continue}
            // Only compare uniform, solid interiors, not apertures, the river surface
            // or the antialiased outer rim. Front and back elevations both qualify.
            guard [q(x-2,y),q(x+2,y),q(x,y-2),q(x,y+2)].allSatisfy({
                abs($0.w-c.w)<0.07 && max(abs($0.x-c.x),max(abs($0.y-c.y),abs($0.z-c.z)))<0.006
            }) else {continue}
            let div=1+0.68*max(0,max(c.x,max(c.y,c.z))-0.78),i=(y*w+x)*4
            let error=max(abs(Int(frame.bytes[i+2])-srgb(c.x/div)),max(abs(Int(frame.bytes[i+1])-srgb(c.y/div)),abs(Int(frame.bytes[i])-srgb(c.z/div))))
            checked+=1;if error<=5 {matched+=1}
        }}
        guard checked>w*h/650,matched*100>checked*96 else {throw SeasonalProbe.Failure("Clouds over opaque town: \(matched)/\(checked)")}
        print("PASS: \(matched)/\(checked) opaque facade samples retain their own radiance under an overcast deck")
    }

    static func lanternDepths(aspect:Float,visit:SeasonalMotion)throws {
        var sawRemoteBurst=false
        for i in 0..<23 {
            guard let scene=SkyDetails.scene(.lantern,aspect:aspect,time:Float(i)*0.38,motion:visit) else {
                throw SeasonalProbe.Failure("No lantern field")
            }
            let lamps=scene.instances[SeasonalShape.lantern.rawValue]
            guard lamps.contains(where:{$0.center.z<scene.foregroundReach}),
                  lamps.contains(where:{$0.center.z>scene.foregroundReach}) else {throw SeasonalProbe.Failure("No near/far paper lights")}
            let sparkTrails=scene.instances[SeasonalShape.stem.rawValue].filter {
                $0.center.z>scene.foregroundReach && UInt32($0.extras.y)==SeasonalFinish.ember.rawValue
            }
            if sparkTrails.count>26 {sawRemoteBurst=true;break}
        }
        guard sawRemoteBurst else {throw SeasonalProbe.Failure("No actual firework behind the Lantern Festival paper lights")}
    }
}
