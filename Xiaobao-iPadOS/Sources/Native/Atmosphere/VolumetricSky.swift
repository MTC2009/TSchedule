import Foundation
import Metal

/// The single GPU pipeline used by the app and the headless appearance probe.
/// The textures are immutable after setup; each draw is encoded independently on a Metal queue.
final class VolumetricSky: @unchecked Sendable {
    enum SetupError: Error { case shader, texture, command, buildFailed }
    static let pixelFormat: MTLPixelFormat = .bgra8Unorm_srgb

    let device: MTLDevice
    let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let seasonal: SeasonalRenderer?
    private let field: MTLTexture
    private let noise: MTLTexture

    init(device: MTLDevice, library: MTLLibrary) throws {
        guard let vertex = library.makeFunction(name: "skyVertex"),
              let fragment = library.makeFunction(name: "skyFragment"),
              let fieldBuilder = library.makeFunction(name: "buildSkyField"),
              let noiseBuilder = library.makeFunction(name: "buildSkyNoise")
        else { throw SetupError.shader }
        guard let queue = device.makeCommandQueue() else { throw SetupError.command }
        self.device = device
        self.queue = queue
        queue.label = "Procedural Sky"

        let config = MTLRenderPipelineDescriptor()
        config.label = "Volumetric Sky"
        config.vertexFunction = vertex
        config.fragmentFunction = fragment
        config.colorAttachments[0].pixelFormat = Self.pixelFormat
        pipeline = try device.makeRenderPipelineState(descriptor: config)
        seasonal = Festival.decorationsEnabled ? (try? SeasonalRenderer(device:device, library:library)) : nil
        field = try Self.volume(on: device, label: "Growth cell field", format: .r16Float, size: .init(width: 128, height: 64, depth: 128))
        noise = try Self.volume(on: device, label: "Procedural cloud noise", format: .rgba8Unorm, size: .init(width: 96, height: 96, depth: 96))
        guard let buffer = queue.makeCommandBuffer(), let compute = buffer.makeComputeCommandEncoder()
        else { throw SetupError.command }
        try Self.build(field, with: fieldBuilder, device: device, encoder: compute)
        try Self.build(noise, with: noiseBuilder, device: device, encoder: compute)
        compute.endEncoding()
        buffer.commit()
        // Only the detached startup task or the headless probe constructs the pipeline.
        buffer.waitUntilCompleted()
        guard buffer.status == .completed else { throw buffer.error ?? SetupError.buildFailed }
    }

    func encode(_ uniforms: SkyUniforms, in buffer: MTLCommandBuffer, to pass: MTLRenderPassDescriptor,
                scene: SeasonalScene? = nil, targets: SeasonalTargets? = nil) -> Bool {
        var data = uniforms
        var visibleSurfaces:SeasonalTargets.Surfaces?
        if let scene, let targets, let seasonal {
            data.camera.w = scene.foregroundReach
            data.pointLight = scene.light
            data.pointColor = .init(scene.glowColor,scene.smoke)
            if let g = scene.motion.gesture, g.target == .water {
                data.waveContact = .init(g.point,scene.motion.age(scene.t))
            } else if let impulse=scene.waterImpulse { data.waveContact=impulse }
            let surfaces=targets.opaque(fineEdges:uniforms.viewport.y>=80,requiresBackdrop:!scene.refractors.isEmpty)
            guard seasonal.draw(scene,data,in:buffer,to:targets,surfaces:surfaces,cloudField:field,noise:noise) else { return false }
            visibleSurfaces=surfaces
        }
        // Do not mutate the MTKView's cached pass or attach seasonal buffers on ordinary dates.
        let output: MTLRenderPassDescriptor
        if visibleSurfaces != nil, let targets {
            guard let copy = pass.copy() as? MTLRenderPassDescriptor else { return false }
            copy.colorAttachments[1].texture = targets.picks
            copy.colorAttachments[1].loadAction = .dontCare; copy.colorAttachments[1].storeAction = .store
            output = copy
        } else { output = pass }
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor:output) else { return false }
        encoder.label = "Integrate sky and clouds"
        if let visibleSurfaces, let seasonal {
            encoder.setRenderPipelineState(seasonal.composite)
            var lens=SIMD2<Float>(max(0.15,(scene?.focusZ ?? 6.8)-data.camera.z),data.pointLight.w>0 ? 1 : 0)
            encoder.setFragmentBytes(&lens,length:MemoryLayout<SIMD2<Float>>.stride,index:1)
            encoder.setFragmentTexture(visibleSurfaces.color,index:2); encoder.setFragmentTexture(visibleSurfaces.id,index:3)
        } else {
            data.pointLight = .zero
            encoder.setRenderPipelineState(pipeline)
        }
        encoder.setFragmentTexture(field, index: 0)
        encoder.setFragmentTexture(noise, index: 1)
        encoder.setFragmentBytes(&data, length: MemoryLayout<SkyUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return true
    }

    var supportsSeasonalScenes: Bool { seasonal != nil }
    func prepareSparrow()->Bool {seasonal?.prepareSparrow() != nil}

    private static func volume(on device: MTLDevice, label: String, format: MTLPixelFormat, size: MTLSize) throws -> MTLTexture {
        let d = MTLTextureDescriptor()
        d.textureType = .type3D
        d.pixelFormat = format
        d.width = size.width
        d.height = size.height
        d.depth = size.depth
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .private
        guard let texture = device.makeTexture(descriptor: d) else { throw SetupError.texture }
        texture.label = label
        return texture
    }

    private static func build(_ volume: MTLTexture, with function: MTLFunction, device: MTLDevice, encoder: MTLComputeCommandEncoder) throws {
        let compute = try device.makeComputePipelineState(function: function)
        encoder.setComputePipelineState(compute)
        encoder.setTexture(volume, index: 0)
        encoder.dispatchThreads(.init(width: volume.width, height: volume.height, depth: volume.depth),
                                threadsPerThreadgroup: .init(width: 8, height: 4, depth: 4))
    }
}
