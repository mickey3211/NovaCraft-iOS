import SwiftUI
import MetalKit

/// An actual Metal draw-call smoke test on iPhone.
/// This is an independent triangle test, NOT a Minecraft/LWJGL renderer.
struct NovaMetalPreview: UIViewRepresentable {
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero)
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.02, green: 0.05, blue: 0.11, alpha: 1)
        view.preferredFramesPerSecond = 30
        view.enableSetNeedsDisplay = true
        view.isPaused = true
        if let renderer = NovaTriangleRenderer(view: view) {
            context.coordinator.renderer = renderer
            view.delegate = renderer
            view.draw()
        }
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var renderer: NovaTriangleRenderer?
    }
}

private final class NovaTriangleRenderer: NSObject, MTKViewDelegate {
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    init?(view: MTKView) {
        guard let device = view.device, let queue = device.makeCommandQueue() else { return nil }
        let shader = """
        #include <metal_stdlib>
        using namespace metal;
        struct VertexOut { float4 position [[position]]; float4 color; };
        vertex VertexOut nova_vertex(uint vertexID [[vertex_id]]) {
            const float2 positions[3] = {
                float2(0.0, 0.75), float2(-0.8, -0.65), float2(0.8, -0.65)
            };
            const float4 colors[3] = {
                float4(0.1, 0.9, 1.0, 1.0),
                float4(0.3, 0.2, 0.9, 1.0),
                float4(0.0, 0.8, 0.5, 1.0)
            };
            VertexOut out;
            out.position = float4(positions[vertexID], 0.0, 1.0);
            out.color = colors[vertexID];
            return out;
        }
        fragment float4 nova_fragment(VertexOut in [[stage_in]]) {
            return in.color;
        }
        """
        guard let library = try? device.makeLibrary(source: shader, options: nil),
              let vertex = library.makeFunction(name: "nova_vertex"),
              let fragment = library.makeFunction(name: "nova_fragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.queue = queue
        self.pipeline = pipeline
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

struct NovaMetalTestScreen: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Pierwsza klatka GPU Metal").font(.title3.bold())
            NovaMetalPreview()
                .frame(height: 290)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            Text("Jeśli widzisz kolorowy trójkąt, iPhone wykonał natywne polecenia Metal. To nie jest jeszcze grafika Minecraft.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .navigationTitle("Test Metal")
    }
}
