import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

/// Exercising the production shader directly makes it possible to hold the sky clock
/// constant and change only the clouds' elapsed time, independently of the iPad's UI clock.
@main struct RenderSky {
    enum ProbeError: Error { case arguments, unavailable, render, write }

    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 5,
              let width = Int(args[2]), let height = Int(args[3]),
              (320...1800).contains(width), (320...1800).contains(height),
              ["pair", "catalog"].contains(args[4])
        else { throw ProbeError.arguments }
        let directory = URL(fileURLWithPath: args[1], isDirectory: true)
        guard let gpu = MTLCreateSystemDefaultDevice() else { throw ProbeError.unavailable }
        let library = try gpu.makeLibrary(URL: directory.appendingPathComponent("Sky.metallib"))
        let renderer = try VolumetricSky(device: gpu, library: library)
        guard MemoryLayout<SkyUniforms>.stride == 176 else { throw ProbeError.render }
        let options = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: VolumetricSky.pixelFormat, width: width, height: height, mipmapped: false
        )
        options.usage = [.renderTarget]
        options.storageMode = .shared
        guard let target = gpu.makeTexture(descriptor: options) else { throw ProbeError.unavailable }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store

        let samples: [(String, Weather, Int, Double)]
        if args[4] == "catalog" {
            samples = Weather.allCases.map { ($0.id, $0, 740, 0) }
        } else {
            samples = [("day-clouds", .cloudy, 715, 0), ("night-00", .cloudy, 1285, 0),
                       ("night-06", .cloudy, 1285, 6), ("night-12", .cloudy, 1285, 12),
                       ("night-repeat", .cloudy, 1285, 0)]
        }
        print("Metal device: \(gpu.name)")
        var nightReference: Data?
        for (name, weather, minute, elapsed) in samples {
            let state = VolumetricSkyState(time: SkyTime(minute: minute), style: weather.style, festival: .none)
            let uniforms = state.uniforms(width: width, height: height, steps: 112, elapsed: elapsed, moving: false)
            guard let buffer = renderer.queue.makeCommandBuffer(), renderer.encode(uniforms, in: buffer, to: pass)
            else { throw ProbeError.render }
            buffer.commit()
            buffer.waitUntilCompleted()
            guard buffer.status == .completed else { throw buffer.error ?? ProbeError.render }
            let row = 4 * width
            var pixels = Data(count: row * height)
            pixels.withUnsafeMutableBytes {
                if let start = $0.baseAddress {
                    target.getBytes(start, bytesPerRow: row, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
                }
            }
            if name == "night-00" { nightReference = pixels }
            if name == "night-06" || name == "night-12" {
                // The sky and lights are unchanged; the animated field must produce different pixels.
                guard pixels != nightReference else { throw ProbeError.render }
            } else if name == "night-repeat" {
                guard pixels == nightReference else { throw ProbeError.render }
            }
            try write(pixels, width: width, height: height, to: directory.appendingPathComponent("\(name).png"))
            let milliseconds = (buffer.gpuEndTime - buffer.gpuStartTime) * 1000
            print("\(name): \(String(format: "%.2f", milliseconds)) ms GPU")
        }
    }

    private static func write(_ pixels: Data, width: Int, height: Int, to url: URL) throws {
        let bitmap = CGBitmapInfo.byteOrder32Little.union(.init(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: 4 * width, space: space, bitmapInfo: bitmap, provider: provider,
                                  decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let writer = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw ProbeError.write }
        CGImageDestinationAddImage(writer, image, nil)
        guard CGImageDestinationFinalize(writer) else { throw ProbeError.write }
    }
}
