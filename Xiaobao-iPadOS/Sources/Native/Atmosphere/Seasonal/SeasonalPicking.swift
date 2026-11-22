import Metal
import simd

struct SeasonalHit: Sendable {
    let target:SeasonalTarget
    let world:SkyPoint
}

/// Read a tiny patch of the *composited* ID/range attachment on demand. A fully cloud-hidden
/// actor has no ID. No framebuffer screenshot, school view pixels or text are ever read.
enum SeasonalPicking {
    static func read(uv:SIMD2<Float>,radius:Int,texture:MTLTexture,queue:MTLCommandQueue,
                     completion:@escaping @Sendable (SeasonalHit?) -> Void) {
        guard uv.x>=0, uv.x<1, uv.y>=0, uv.y<1 else { completion(nil); return }
        let width = texture.width, height = texture.height, r = min(24,max(0,radius))
        let x = Int(uv.x*Float(width)), y = Int(uv.y*Float(height))
        let x0 = max(0,x-r), y0 = max(0,y-r)
        let w = min(width-1,x+r)-x0+1, h = min(height-1,y+r)-y0+1
        let row = ((w*4+255)/256)*256
        guard let buf = queue.device.makeBuffer(length:row*h,options:.storageModeShared),
              let cmd = queue.makeCommandBuffer(),let blit = cmd.makeBlitCommandEncoder() else { completion(nil); return }
        blit.copy(from:texture,sourceSlice:0,sourceLevel:0,sourceOrigin:.init(x:x0,y:y0,z:0),
                  sourceSize:.init(width:w,height:h,depth:1),to:buf,destinationOffset:0,
                  destinationBytesPerRow:row,destinationBytesPerImage:row*h)
        blit.endEncoding()
        cmd.addCompletedHandler { command in
            guard command.status == .completed else { completion(nil); return }
            let ptr = buf.contents().assumingMemoryBound(to:UInt16.self)
            var best = Int.max, hit:SeasonalHit?
            for j in 0..<h { for i in 0..<w {
                let d = (i+x0-x)*(i+x0-x)+(j+y0-y)*(j+y0-y)
                if d>=best || d>r*r { continue }
                let k = j*row/2+i*2
                let raw = Float(Float16(bitPattern:ptr[k]))
                guard raw.isFinite, let id = SeasonalTarget(rawValue:Int(raw)), id != .none else { continue }
                let range = Float(Float16(bitPattern:ptr[k+1]))
                let sample = SIMD2((Float(x0+i)+0.5)/Float(width),(Float(y0+j)+0.5)/Float(height))
                let ray = simd_normalize(SeasonalScene.slope(sample,aspect:Float(width)/Float(height)))
                best = d; hit = .init(target:id,world:ray*range)
            } }
            completion(hit)
        }
        cmd.commit()
    }
}
