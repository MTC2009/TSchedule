import Foundation
import Metal

/// Read production attachments, not test-only shader flags. Never uses a clear comparison
/// as evidence of artistic realism. The small optical bench isolates one physical effect.
enum SeasonalLightProbe {
    static func run(_ renderer:VolumetricSky,_ output:MTLTexture,_ pass:MTLRenderPassDescriptor) throws {
        typealias Failure = SeasonalProbe.Failure
        let w=output.width,h=output.height,ratio=Float(w)/Float(h),device=renderer.device
        guard let targets=SeasonalTargets(device:device,width:w,height:h) else {throw Failure("No lighting targets")}
        func uniforms(_ f:Festival,_ minute:Int)->SkyUniforms {
            VolumetricSkyState(time:.init(minute:minute),style:Weather.sunny.style,festival:f)
                .uniforms(width:w,height:h,steps:88,elapsed:1.5,moving:false)
        }
        func draw(_ scene:SeasonalScene?,_ u:SkyUniforms)throws->Double {
            guard let cmd=renderer.queue.makeCommandBuffer(), renderer.encode(u,in:cmd,to:pass,scene:scene,targets:targets) else {throw Failure("Light encode")}
            cmd.commit();cmd.waitUntilCompleted()
            guard cmd.status == .completed else {throw cmd.error ?? Failure("Light command")}
            return (cmd.gpuEndTime-cmd.gpuStartTime)*1000
        }
        func shadow() throws -> [Float] {
            let edge=targets.shadow.width,row=(edge*4+255)/256*256
            guard let memory=device.makeBuffer(length:row*edge,options:.storageModeShared),
                  let cmd=renderer.queue.makeCommandBuffer(),let blit=cmd.makeBlitCommandEncoder() else {throw Failure("Shadow read")}
            blit.copy(from:targets.shadow,sourceSlice:0,sourceLevel:0,sourceOrigin:.init(),sourceSize:.init(width:edge,height:edge,depth:1),
                to:memory,destinationOffset:0,destinationBytesPerRow:row,destinationBytesPerImage:row*edge)
            blit.endEncoding();cmd.commit();cmd.waitUntilCompleted()
            guard cmd.status == .completed else {throw Failure("Shadow resolve")}
            let values=memory.contents().assumingMemoryBound(to:Float.self)
            return (0..<edge).flatMap { Array(UnsafeBufferPointer(start:values+$0*row/4,count:edge)) }
        }
        guard let subject=SkyDetails.scene(.summerSolstice,aspect:ratio,time:1.8,motion:.init()) else {throw Failure("Missing tree")}
        _=try draw(subject,uniforms(.summerSolstice,550));let early=try shadow()
        _=try draw(subject,uniforms(.summerSolstice,990));let late=try shadow()
        let coverage=early.filter { $0.isFinite && $0>0 && $0<0.999 }.count
        let moved=zip(early,late).filter {abs($0-$1)>0.018}.count
        guard coverage>500,coverage<early.count*9/10,moved>coverage/8 else {throw Failure("No light-space depth response: \(coverage)/\(moved)")}

        func optical(_ color:SkyPoint)throws->[UInt8] {
            var scene=SeasonalScene(aspect:ratio,t:0,motion:.init())
            scene.place(0.50,0.52,7,0.15);scene.focusZ=7
            scene.part(.cube,.init(0,0,0.84),.init(1.7,1.6,0.05),color,.zero,0.29,.cloth)
            scene.part(.globe,.zero,.init(repeating:0.55),SeasonalInk.silver,.zero,0,.dew)
            _=try draw(scene,uniforms(.whiteDew,760))
            let side=9,row=side*4
            var pixels=[UInt8](repeating:0,count:row*side)
            pixels.withUnsafeMutableBytes { output.getBytes($0.baseAddress!,bytesPerRow:row,
                from:MTLRegionMake2D(w/2-side/2,Int(Float(h)*0.52)-side/2,side,side),mipmapLevel:0) }
            return pixels
        }
        let red=try optical(SeasonalInk.vermilion),green=try optical(SeasonalInk.jade)
        let greenShift=stride(from:0,to:red.count,by:4).reduce(0) {result,i in
            result+Int(green[i+1])-Int(red[i+1])+Int(red[i+2])-Int(green[i+2])
        }
        guard greenShift>40*81 else {throw Failure("Drop did not transmit the backing's pigment: \(greenShift)")}
        func mirror(_ dye:SkyPoint)throws->[UInt8] {
            var scene=SeasonalScene(aspect:ratio,t:0,motion:.init())
            scene.place(0.50,0.63,6.8,0.27)
            scene.water(.init(0,-0.15,0))
            scene.part(.cube,.init(-0.15,0.23,0),.init(0.22,0.23,0.11),dye,.zero,0.36,.cloth)
            _=try draw(scene,uniforms(.dragonBoat,760))
            var bytes=[UInt8](repeating:0,count:w*h*4)
            bytes.withUnsafeMutableBytes {output.getBytes($0.baseAddress!,bytesPerRow:w*4,from:MTLRegionMake2D(0,0,w,h),mipmapLevel:0)}
            return bytes
        }
        let copper=try mirror(SeasonalInk.vermilion),jade=try mirror(SeasonalInk.jade)
        let row=(w*4+255)/256*256
        guard let mem=device.makeBuffer(length:row*h,options:.storageModeShared),let cmd=renderer.queue.makeCommandBuffer(),
              let copy=cmd.makeBlitCommandEncoder() else {throw Failure("Reflection read")}
        copy.copy(from:targets.picks,sourceSlice:0,sourceLevel:0,sourceOrigin:.init(),sourceSize:.init(width:w,height:h,depth:1),
                  to:mem,destinationOffset:0,destinationBytesPerRow:row,destinationBytesPerImage:row*h)
        copy.endEncoding();cmd.commit();cmd.waitUntilCompleted()
        guard cmd.status == .completed else {throw Failure("Reflection command")}
        let ids=mem.contents().assumingMemoryBound(to:UInt16.self),waterID=Float16(SeasonalTarget.water.rawValue).bitPattern
        var coloredWater=0
        for y in 0..<h { for x in 0..<w where ids[y*row/2+x*2]==waterID {
            let i=(y*w+x)*4
            if Int(jade[i+1])-Int(copper[i+1])+Int(copper[i+2])-Int(jade[i+2])>35 {coloredWater+=1}
        }}
        guard coloredWater>80 else {throw Failure("Mirrored object missing on visible water: "+String(coloredWater))}
        print("PASS: changing the bank object's pigment changed "+String(coloredWater)+" water-ID pixels")
        print("PASS: light-space caster coverage \(coverage), moved depth texels \(moved); colored backing visible through optical surface")
        print("Device \(device.name), \(w)x\(h), 88 steps. Median of five warm GPU frames, no readbacks; not an iPad power/FPS test.")
        for f:Festival in [.none,.lantern,.heavySnow,.summerBegins,.summerSolstice,.christmas,.coldDew,.lesserCold] {
            var times:[Double]=[]
            for i in 0..<7 {
                let scene=SkyDetails.scene(f,aspect:ratio,time:2.35+Float(i)/24,motion:.init())
                let ms=try draw(scene,uniforms(f,[.christmas,.lantern].contains(f) ? 1260 : 760))
                if i>=2 {times.append(ms)}
            }
            print("\(f.rawValue): \(String(format:"%.2f",times.sorted()[2])) ms GPU")
        }
    }
}
