import Foundation
import Metal

/// Per-surface render targets, never shared by the main sky, a pushed detail or an environment sheet.
final class SeasonalTargets {
    typealias Surfaces=(color:MTLTexture,id:MTLTexture,depth:MTLTexture)
    let color, depth, ids, picks, shadow: MTLTexture
    private var edgeSamples:Surfaces?
    private var triedEdgeSamples=false
    private var reflection:(color:MTLTexture,id:MTLTexture,depth:MTLTexture)?
    private var backdrop:MTLTexture?
    private var upload: MTLBuffer?
    init?(device:MTLDevice, width:Int, height:Int) {
        func make(_ format:MTLPixelFormat, _ usage:MTLTextureUsage, _ label:String, _ edge:Int? = nil) -> MTLTexture? {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:format,width:edge ?? width,height:edge ?? height,mipmapped:false)
            d.usage = usage; d.storageMode = .private
            guard let tex = device.makeTexture(descriptor:d) else { return nil }
            tex.label = label; return tex
        }
        guard let a = make(.rgba16Float,[.renderTarget,.shaderRead],"Seasonal radiance and world distance"),
              let b = make(.depth32Float,.renderTarget,"Seasonal opaque depth"),
              let c = make(.r8Uint,[.renderTarget,.shaderRead],"Seasonal geometry IDs"),
              let d = make(.rg16Float,.renderTarget,"Visible seasonal IDs and range"),
              let e = make(.depth32Float,[.renderTarget,.shaderRead],"Seasonal sun or moon depth",SeasonalShadow.resolution) else { return nil }
        color = a; depth = b; ids = c; picks = d; shadow = e
    }
    /// Four geometric samples preserve ink edges, rigging and hair-thin strokes.
    /// The sky marches once per output pixel. Allocation failure keeps the 1x path.
    func opaque(fineEdges:Bool,requiresBackdrop:Bool = false)->Surfaces {
        let standard=(color,ids,depth)
        guard fineEdges else {
            if let behind=backdrop,behind.width != color.width {backdrop=nil}
            edgeSamples=nil;triedEdgeSamples=false;return standard
        }
        if let samples=edgeSamples {
            if !requiresBackdrop || opticalBackdrop(for:samples.color) != nil {return samples}
            // Do not keep requesting the larger optical bank on a memory-limited surface.
            edgeSamples=nil;return standard
        }
        guard !triedEdgeSamples else {return standard}
        triedEdgeSamples=true
        let w=color.width*2,h=color.height*2
        #if os(macOS)
        let limit=32_000_000 // QA sensor crop; the iPad drawable has a much smaller cap.
        #else
        let limit=4_200_000
        #endif
        guard w<=8192,h<=8192,w*h<=limit else {return standard}
        func make(_ format:MTLPixelFormat,_ usage:MTLTextureUsage)->MTLTexture? {
            let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:format,width:w,height:h,mipmapped:false)
            d.storageMode = .private;d.usage=usage
            return color.device.makeTexture(descriptor:d)
        }
        guard let c=make(.rgba16Float,[.renderTarget,.shaderRead]),let i=make(.r8Uint,[.renderTarget,.shaderRead]),
              let z=make(.depth32Float,.renderTarget) else {return standard}
        if requiresBackdrop && opticalBackdrop(for:c)==nil {return standard}
        c.label="Almanac radiance at four sample locations"
        let samples=(c,i,z);edgeSamples=samples;return samples
    }
    /// Half-resolution is appropriate for a rough surface; the original silhouette,
    /// perspective and occlusion are rendered from the real mirrored camera.
    func waterReflection()->(color:MTLTexture,id:MTLTexture,depth:MTLTexture)? {
        if let reflection {return reflection}
        func make(_ format:MTLPixelFormat,_ read:Bool)->MTLTexture? {
            let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:format,width:max(1,color.width/2),height:max(1,color.height/2),mipmapped:false)
            d.usage=read ? [.renderTarget,.shaderRead] : .renderTarget;d.storageMode = .private
            return color.device.makeTexture(descriptor:d)
        }
        guard let c=make(.rgba16Float,true),let i=make(.r8Uint,false),let z=make(.depth32Float,false) else {return nil}
        c.label="Radiance reflected at the seasonal water plane";reflection=(c,i,z);return (c,i,z)
    }
    /// Only water, clear wings and drops need an opaque-background snapshot. It contains
    /// HDR world radiance and range, never school UI. Reused until the drawable resizes.
    func opticalBackdrop(for surface:MTLTexture) -> MTLTexture? {
        if let backdrop,backdrop.width==surface.width,backdrop.height==surface.height {return backdrop}
        let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Float,width:surface.width,height:surface.height,mipmapped:false)
        d.usage = .shaderRead; d.storageMode = .private
        backdrop=color.device.makeTexture(descriptor:d); backdrop?.label="Opaque world behind optical surfaces"
        return backdrop
    }
    // One command in flight per SkySurface; main/detail/preview never share mutable uploads.
    // Both light and view cameras index the same retained frame buffer.
    func upload(_ scene:SeasonalScene)->(MTLBuffer,[Range<Int>])? {
        let stride=MemoryLayout<SeasonalInstance>.stride
        let bytes=max(1,scene.instances.reduce(0){ $0+$1.count }+scene.refractors.values.reduce(0){$0+$1.count})*stride
        if (upload?.length ?? 0)<bytes {
            upload=color.device.makeBuffer(length:(bytes+16383)/16384*16384,options:.storageModeShared)
            upload?.label="Seasonal frame instances"
        }
        guard let upload else {return nil}
        var offset=0, ranges:[Range<Int>]=[]
        func append(_ group:[SeasonalInstance]) {
            ranges.append(offset..<(offset+group.count))
            group.withUnsafeBytes { b in if let p=b.baseAddress,!b.isEmpty {
                upload.contents().advanced(by:offset*stride).copyMemory(from:p,byteCount:b.count)
            }}
            offset+=group.count
        }
        for group in scene.instances {append(group)}
        if !scene.refractors.isEmpty {
            for shape in SeasonalShape.allCases {append(scene.refractors[shape.rawValue] ?? [])}
        }
        return (upload,ranges)
    }
}

final class SeasonalRenderer {
    private let sparrowLock=NSLock()
    private var sparrowBank:SeasonalMeshAtlas?
    private var triedSparrow=false
    /// Only the first winter-bird request builds these meshes. The renderer can be
    /// shared by several surfaces, so publish both immutable buffers atomically.
    func prepareSparrow()->SeasonalMeshAtlas? {
        sparrowLock.lock(); defer {sparrowLock.unlock()}
        if !triedSparrow {
            sparrowBank=try? SeasonalMeshAtlas(device:atlas.vertices.device,sparrow:true)
            triedSparrow=true
        }
        return sparrowBank
    }
    private let emptyBackdrop:MTLTexture
    let atlas:SeasonalMeshAtlas
    let geometry, composite, shadowPipeline:MTLRenderPipelineState
    let depth:MTLDepthStencilState

    init(device:MTLDevice,library:MTLLibrary) throws {
        let empty=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Float,width:1,height:1,mipmapped:false)
        empty.usage = .shaderRead
        guard let placeholder=device.makeTexture(descriptor:empty) else {throw VolumetricSky.SetupError.texture}
        emptyBackdrop=placeholder
        atlas = try SeasonalMeshAtlas(device:device)
        func pipeline(_ name:String,_ vs:String,_ fs:String,_ a:MTLPixelFormat,_ b:MTLPixelFormat,
                      _ z:MTLPixelFormat) throws -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.label = name; d.vertexFunction = library.makeFunction(name:vs); d.fragmentFunction = library.makeFunction(name:fs)
            d.colorAttachments[0].pixelFormat = a; d.colorAttachments[1].pixelFormat = b; d.depthAttachmentPixelFormat = z
            return try device.makeRenderPipelineState(descriptor:d)
        }
        geometry = try pipeline("Seasonal solid geometry","seasonalVertex","seasonalMaterial",.rgba16Float,.r8Uint,.depth32Float)
        composite = try pipeline("Seasonal cloud occlusion","skyVertex","seasonalSkyFragment",VolumetricSky.pixelFormat,.rg16Float,.invalid)
        let shadowConfig=MTLRenderPipelineDescriptor()
        shadowConfig.label="Seasonal solar depth"; shadowConfig.depthAttachmentPixelFormat = .depth32Float
        shadowConfig.vertexFunction=library.makeFunction(name:"seasonalShadowVertex")
        shadowConfig.fragmentFunction=library.makeFunction(name:"seasonalShadowCutout")
        shadowPipeline = try device.makeRenderPipelineState(descriptor:shadowConfig)
        let ds = MTLDepthStencilDescriptor(); ds.depthCompareFunction = .less; ds.isDepthWriteEnabled = true
        guard let state = device.makeDepthStencilState(descriptor:ds) else { throw VolumetricSky.SetupError.shader }
        depth = state
    }

    func draw(_ scene:SeasonalScene,_ u:SkyUniforms,in cmd:MTLCommandBuffer,to target:SeasonalTargets,surfaces:SeasonalTargets.Surfaces,
              cloudField:MTLTexture, noise:MTLTexture) -> Bool {
        guard let (stream,batches)=target.upload(scene) else { return false }
        let bird = !scene.instances[SeasonalShape.sparrowSkin.rawValue].isEmpty
        let featherBank=bird ? prepareSparrow() : nil
        if bird && featherBank == nil {return false}
        let reflection=scene.waterPlane.flatMap {_ in target.waterReflection()}
        var sunlight=SeasonalShadow(scene,u), uniforms=u
        func submit(_ enc:MTLRenderCommandEncoder, shadowOnly:Bool, glass:Bool = false) {
            enc.setDepthStencilState(depth)
            enc.setVertexBuffer(atlas.vertices,offset:0,index:1)
            var boundSparrow=false
            enc.setVertexBuffer(stream,offset:0,index:2)
            enc.setVertexBytes(&uniforms,length:MemoryLayout<SkyUniforms>.stride,index:0)
            enc.setVertexBytes(&sunlight,length:MemoryLayout<SeasonalShadow>.stride,index:3)
            for shape in SeasonalShape.allCases {
                // Water receives light but cannot cast an opaque silhouette on the shore.
                if shadowOnly && (shape == .lake || shape == .bank || shape == .hillside || shape == .floor) { continue }
                let batch=batches[shape.rawValue+(glass ? SeasonalShape.allCases.count : 0)]
                guard !batch.isEmpty else {continue}
                let bank=shape.belongsToSparrow ? featherBank : atlas
                guard let bank else {continue}
                if shape.belongsToSparrow != boundSparrow {
                    enc.setVertexBuffer(bank.vertices,offset:0,index:1)
                    boundSparrow=shape.belongsToSparrow
                }
                let range=bank.ranges[shape.rawValue]
                enc.setVertexBufferOffset(batch.lowerBound*MemoryLayout<SeasonalInstance>.stride,index:2)
                enc.drawIndexedPrimitives(type:.triangle,indexCount:range.count,indexType:.uint32,
                    indexBuffer:bank.indices,indexBufferOffset:range.lowerBound*4,instanceCount:batch.count)
            }
            enc.endEncoding()
        }
        let lightPass=MTLRenderPassDescriptor()
        lightPass.depthAttachment.texture=target.shadow; lightPass.depthAttachment.loadAction = .clear
        lightPass.depthAttachment.storeAction = .store; lightPass.depthAttachment.clearDepth=1
        guard let le=cmd.makeRenderCommandEncoder(descriptor:lightPass) else {return false}
        le.label="Seasonal geometry from current light"; le.setRenderPipelineState(shadowPipeline)
        le.setDepthBias(0.0001,slopeScale:1.1,clamp:0.0025)
        submit(le,shadowOnly:true)
        let optical = !scene.refractors.isEmpty
        let p = MTLRenderPassDescriptor()
        for (i,texture) in [surfaces.color,surfaces.id].enumerated() {
            p.colorAttachments[i].texture = texture; p.colorAttachments[i].loadAction = .clear
            p.colorAttachments[i].storeAction = .store; p.colorAttachments[i].clearColor = .init()
        }
        p.depthAttachment.texture = surfaces.depth; p.depthAttachment.loadAction = .clear
        p.depthAttachment.storeAction = optical ? .store : .dontCare; p.depthAttachment.clearDepth = 1
        func render(_ pass:MTLRenderPassDescriptor,glass:Bool,behind:MTLTexture,mirror:SIMD4<Float> = .zero) -> Bool {
            var mirror=mirror
            guard let enc=cmd.makeRenderCommandEncoder(descriptor:pass) else {return false}
            enc.label=glass ? "Transmitted scene radiance" : "Opaque depth, material and picking"
            enc.setRenderPipelineState(geometry)
            enc.setFragmentTexture(target.shadow,index:0); enc.setFragmentTexture(cloudField,index:1)
            enc.setFragmentTexture(noise,index:2); enc.setFragmentTexture(behind,index:3)
            enc.setFragmentTexture(glass ? (reflection?.color ?? emptyBackdrop) : emptyBackdrop,index:4)
            enc.setVertexBytes(&mirror,length:MemoryLayout<SIMD4<Float>>.stride,index:4)
            enc.setFragmentBytes(&mirror,length:MemoryLayout<SIMD4<Float>>.stride,index:2)
            enc.setFragmentBytes(&uniforms,length:MemoryLayout<SkyUniforms>.stride,index:0)
            enc.setFragmentBytes(&sunlight,length:MemoryLayout<SeasonalShadow>.stride,index:1)
            submit(enc,shadowOnly:false,glass:glass); return true
        }
        if let reflection,let plane=scene.waterPlane {
            let r=MTLRenderPassDescriptor()
            r.colorAttachments[0].texture=reflection.color;r.colorAttachments[0].loadAction = .clear;r.colorAttachments[0].storeAction = .store
            r.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,0)
            r.colorAttachments[1].texture=reflection.id;r.colorAttachments[1].loadAction = .dontCare;r.colorAttachments[1].storeAction = .dontCare
            r.depthAttachment.texture=reflection.depth;r.depthAttachment.loadAction = .clear;r.depthAttachment.clearDepth=1;r.depthAttachment.storeAction = .dontCare
            guard render(r,glass:false,behind:emptyBackdrop,mirror:plane) else {return false}
        }
        guard render(p,glass:false,behind:emptyBackdrop) else {return false}
        if optical {
            guard let backdrop=target.opticalBackdrop(for:surfaces.color),let blit=cmd.makeBlitCommandEncoder() else {return false}
            blit.copy(from:surfaces.color,sourceSlice:0,sourceLevel:0,sourceOrigin:.init(),
                sourceSize:.init(width:surfaces.color.width,height:surfaces.color.height,depth:1),
                to:backdrop,destinationSlice:0,destinationLevel:0,destinationOrigin:.init())
            blit.endEncoding()
            for i in 0...1 {p.colorAttachments[i].loadAction = .load}
            p.depthAttachment.loadAction = .load; p.depthAttachment.storeAction = .dontCare
            guard render(p,glass:true,behind:backdrop) else {return false}
        }
        return true
    }
}
