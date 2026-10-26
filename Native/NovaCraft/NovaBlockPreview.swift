import SwiftUI
import MetalKit

/// Standalone native 3D block renderer, independent of Minecraft's LWJGL API.
/// A genuine GPU draw test with perspective, rotation, and a depth buffer.
struct NovaBlockPreview: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColor(red: 0.04, green: 0.08, blue: 0.14, alpha: 1)
        view.preferredFramesPerSecond = 30
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        if let renderer = NovaBlockRenderer(view: view) {
            context.coordinator.renderer = renderer
            view.delegate = renderer
        }
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}

    final class Coordinator {
        var renderer: NovaBlockRenderer?
    }
}

final class NovaBlockRenderer: NSObject, MTKViewDelegate {
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let start = CACurrentMediaTime()

    init?(view: MTKView) {
        guard let device = view.device, let queue = device.makeCommandQueue() else { return nil }
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        struct Out { float4 position [[position]]; float3 color; };
        struct Params { float time; float aspect; };
        vertex Out block_vertex(uint id [[vertex_id]], constant Params &p [[buffer(0)]]) {
            const float3 corners[8] = {
                float3(-1,-1,-1), float3(1,-1,-1), float3(1,1,-1), float3(-1,1,-1),
                float3(-1,-1,1), float3(1,-1,1), float3(1,1,1), float3(-1,1,1)
            };
            const uint indices[36] = {
                4,5,6, 4,6,7, 1,0,3, 1,3,2,
                0,4,7, 0,7,3, 5,1,2, 5,2,6,
                3,7,6, 3,6,2, 0,1,5, 0,5,4
            };
            const float3 colors[6] = {
                float3(0.12,0.85,0.95), float3(0.08,0.4,0.7),
                float3(0.2,0.75,0.45), float3(0.1,0.55,0.3),
                float3(0.45,0.95,0.65), float3(0.08,0.4,0.5)
            };
            float3 v = corners[indices[id]];
            float a = p.time * 0.65;
            float b = 0.40 + sin(p.time * 0.4) * 0.25;
            float3 rotatedY = float3(v.x*cos(a) + v.z*sin(a), v.y,
                                      -v.x*sin(a) + v.z*cos(a));
            float3 rotated = float3(rotatedY.x,
                                    rotatedY.y*cos(b) - rotatedY.z*sin(b),
                                    rotatedY.y*sin(b) + rotatedY.z*cos(b));
            float depth = rotated.z + 4.5;
            float nearPlane = 0.1;
            float farPlane = 100.0;
            Out out;
            out.position = float4(rotated.x / max(p.aspect,0.01),
                                  rotated.y, (depth * farPlane / (farPlane-nearPlane) -
                                  nearPlane * farPlane / (farPlane-nearPlane)),
                                  depth);
            out.color = colors[id / 6];
            return out;
        }
        fragment float4 block_fragment(Out in [[stage_in]]) {
            return float4(in.color, 1.0);
        }
        """
        guard let library = try? device.makeLibrary(source: source, options: nil),
              let vertex = library.makeFunction(name: "block_vertex"),
              let fragment = library.makeFunction(name: "block_fragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        descriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: depthDescriptor) else { return nil }
        self.queue = queue
        self.pipeline = pipeline
        self.depthState = depthState
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        var params = SIMD2<Float>(Float(CACurrentMediaTime() - start),
                                  Float(view.drawableSize.width / max(view.drawableSize.height, 1)))
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setVertexBytes(&params, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

struct NovaBlockTestScreen: View {
    var body: some View {
        VStack(spacing: 14) {
            Text("NovaEngine • blok 3D").font(.title2.bold())
            NovaBlockPreview()
                .frame(height: 350)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            Text("Obracający się blok 3D renderowany przez Metal na GPU iPhone'a. Test perspektywy i głębi — nie jest to jeszcze silnik graficzny Minecraft Java ani LWJGL.")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .navigationTitle("Test 3D Metal")
    }
}
