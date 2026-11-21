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

    func encode(_ uniforms: SkyUniforms, in buffer: MTLCommandBuffer, to pass: MTLRenderPassDescriptor) -> Bool {
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return false }
        encoder.label = "Integrate sky and clouds"
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(field, index: 0)
        encoder.setFragmentTexture(noise, index: 1)
        var data = uniforms
        encoder.setFragmentBytes(&data, length: MemoryLayout<SkyUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return true
    }

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
