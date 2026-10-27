import SwiftUI
import MetalKit
import simd

// Copyright (c) 2026 mickey3211 — NovaCraft.
// Original NovaEngine renderer. No Amethyst or PojavLauncher source is used.
// This draws NovaCraft's own voxel scene; it is NOT a Minecraft OpenGL bridge.

private struct NovaVoxelVertex {
    var position: SIMD4<Float>
    var color: SIMD4<Float>
}

private struct NovaSceneUniforms {
    var viewProjection: simd_float4x4
}

private enum NovaVoxelWorld {
    /// Reproducible procedural height field; does not read Minecraft world data.
    static func height(_ x: Int, _ z: Int, side: Int, seed: Int) -> Int {
        let dx = Float(x) - Float(side - 1) * 0.5
        let dz = Float(z) - Float(side - 1) * 0.5
        let distance = sqrt(dx * dx + dz * dz)
        let phase = Float(seed % 10_000) / 101
        let waves = sin(Float(x) * 0.32 + phase) * 2.4
                  + cos(Float(z) * 0.37 - phase * 0.8) * 1.7
                  + cos(Float(x + z) * 0.19 + phase * 1.1) * 1.2
        let plateau = max(0, 5.9 - distance * 0.18)
        return max(1, min(15, Int((plateau + waves + 2.8).rounded())))
    }

    static func generate(side rawSide: Int, seed: Int, palette: String) -> [NovaVoxelVertex] {
        let side = max(24, min(48, rawSide))
        var vertices: [NovaVoxelVertex] = []
        vertices.reserveCapacity(side * side * 24)
        let half = Float(side) / 2

        // Surface-only greedy-style visibility: draw top faces and only exposed
        // wall sections, not the invisible interiors of each voxel.
        func emit(_ corners: [SIMD3<Float>], color: SIMD4<Float>) {
            let indices = [0, 1, 2, 0, 2, 3]
            for index in indices {
                let p = corners[index]
                vertices.append(NovaVoxelVertex(
                    position: SIMD4<Float>(p.x, p.y, p.z, 1),
                    color: color))
            }
        }
        func h(_ x: Int, _ z: Int) -> Int {
            guard (0..<side).contains(x), (0..<side).contains(z) else { return 0 }
            return height(x, z, side: side, seed: seed)
        }
        for z in 0..<side {
            for x in 0..<side {
                let top = h(x, z)
                let left = Float(x) - half
                let front = Float(z) - half
                let right = left + 1
                let back = front + 1
                let summit = Float(top) * 0.62
                let variation = Float((x * 13 + z * 7 + abs(seed % 100)) % 10) / 120
                let topTint: SIMD4<Float>
                let sideTint: SIMD4<Float>
                let shadeTint: SIMD4<Float>
                switch palette {
                case "forest":
                    topTint = SIMD4<Float>(0.13 + variation, 0.62 + variation, 0.28, 1)
                    sideTint = SIMD4<Float>(0.26, 0.37 + variation, 0.19, 1)
                    shadeTint = SIMD4<Float>(0.13, 0.26 + variation, 0.15, 1)
                case "lava":
                    topTint = SIMD4<Float>(0.90, 0.39 + variation, 0.08, 1)
                    sideTint = SIMD4<Float>(0.43 + variation, 0.14, 0.19, 1)
                    shadeTint = SIMD4<Float>(0.26, 0.09 + variation, 0.15, 1)
                default:
                    topTint = SIMD4<Float>(0.13 + variation, 0.73 + variation, 0.73, 1)
                    sideTint = SIMD4<Float>(0.04 + variation, 0.36, 0.53, 1)
                    shadeTint = SIMD4<Float>(0.04, 0.22 + variation, 0.40, 1)
                }

                // One top quad per column.
                emit([
                    SIMD3<Float>(left, summit, front),
                    SIMD3<Float>(left, summit, back),
                    SIMD3<Float>(right, summit, back),
                    SIMD3<Float>(right, summit, front)
                ], color: topTint)

                let east = Float(h(x + 1, z)) * 0.62
                if east < summit {
                    emit([
                        SIMD3<Float>(right, east, front),
                        SIMD3<Float>(right, summit, front),
                        SIMD3<Float>(right, summit, back),
                        SIMD3<Float>(right, east, back)
                    ], color: sideTint)
                }
                let west = Float(h(x - 1, z)) * 0.62
                if west < summit {
                    emit([
                        SIMD3<Float>(left, west, back),
                        SIMD3<Float>(left, summit, back),
                        SIMD3<Float>(left, summit, front),
                        SIMD3<Float>(left, west, front)
                    ], color: shadeTint)
                }
                let south = Float(h(x, z + 1)) * 0.62
                if south < summit {
                    emit([
                        SIMD3<Float>(right, south, back),
                        SIMD3<Float>(right, summit, back),
                        SIMD3<Float>(left, summit, back),
                        SIMD3<Float>(left, south, back)
                    ], color: sideTint)
                }
                let north = Float(h(x, z - 1)) * 0.62
                if north < summit {
                    emit([
                        SIMD3<Float>(left, north, front),
                        SIMD3<Float>(left, summit, front),
                        SIMD3<Float>(right, summit, front),
                        SIMD3<Float>(right, north, front)
                    ], color: shadeTint)
                }
            }
        }
        return vertices
    }
}

final class NovaVoxelRenderer: NSObject, MTKViewDelegate {
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let mesh: MTLBuffer
    private let vertexCount: Int
    private var yaw: Float = 0.65
    private var pitch: Float = 0.67
    private var zoom: Float = 37
    private var autoRotate = true
    private var previousFrameTime = CACurrentMediaTime()

    init?(view: MTKView, worldSide: Int, seed: Int, palette: String) {
        guard let device = view.device,
              let queue = device.makeCommandQueue() else { return nil }

        // The shader is written for NovaCraft and compiled at runtime by
        // Metal. It does not implement Minecraft's OpenGL or GLFW APIs.
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        struct VoxelVertex { float4 position; float4 color; };
        struct SceneUniforms { float4x4 viewProjection; };
        struct VoxelOut { float4 position [[position]]; float4 color; };
        vertex VoxelOut nova_voxel_vertex(const device VoxelVertex *vertices [[buffer(0)]],
                                          constant SceneUniforms& uniforms [[buffer(1)]],
                                          uint id [[vertex_id]]) {
            VoxelOut out;
            out.position = uniforms.viewProjection * vertices[id].position;
            out.color = vertices[id].color;
            return out;
        }
        fragment float4 nova_voxel_fragment(VoxelOut value [[stage_in]]) {
            return value.color;
        }
        """
        guard let library = try? device.makeLibrary(source: source, options: nil),
              let vertex = library.makeFunction(name: "nova_voxel_vertex"),
              let fragment = library.makeFunction(name: "nova_voxel_fragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        descriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }

        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .less
        depth.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: depth) else { return nil }

        let vertices = NovaVoxelWorld.generate(side: worldSide, seed: seed, palette: palette)
        let generatedMesh = vertices.withUnsafeBufferPointer { buffer -> MTLBuffer? in
            guard let data = buffer.baseAddress else { return nil }
            return device.makeBuffer(bytes: data,
                                     length: buffer.count * MemoryLayout<NovaVoxelVertex>.stride,
                                     options: .storageModeShared)
        }
        guard let mesh = generatedMesh else { return nil }
        mesh.label = "NovaEngine visible voxel terrain"
        self.queue = queue
        self.pipeline = pipeline
        self.depthState = depthState
        self.mesh = mesh
        self.vertexCount = vertices.count
        super.init()
    }

    func pan(dx: CGFloat, dy: CGFloat) {
        yaw += Float(dx) * 0.008
        pitch = min(1.33, max(0.12, pitch + Float(dy) * 0.008))
        autoRotate = false
    }

    func magnify(scale: CGFloat) {
        zoom = max(18, min(85, zoom / Float(scale)))
    }

    func toggleOrbit() { autoRotate.toggle() }

    func resetCamera() {
        yaw = 0.65
        pitch = 0.67
        zoom = 37
        autoRotate = true
    }

    private static func projection(aspect: Float) -> simd_float4x4 {
        let near: Float = 0.1
        let far: Float = 200
        let f = 1 / tan(Float.pi / 6)
        let a = max(0.1, aspect)
        return simd_float4x4(
            SIMD4<Float>(f / a, 0, 0, 0),
            SIMD4<Float>(0, f, 0, 0),
            SIMD4<Float>(0, 0, far / (near - far), -1),
            SIMD4<Float>(0, 0, (near * far) / (near - far), 0)
        )
    }

    private static func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>) -> simd_float4x4 {
        let forward = simd_normalize(eye - target)
        let right = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), forward))
        let up = simd_cross(forward, right)
        return simd_float4x4(
            SIMD4<Float>(right.x, up.x, forward.x, 0),
            SIMD4<Float>(right.y, up.y, forward.y, 0),
            SIMD4<Float>(right.z, up.z, forward.z, 0),
            SIMD4<Float>(-simd_dot(right, eye),
                         -simd_dot(up, eye),
                         -simd_dot(forward, eye), 1)
        )
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard view.drawableSize.width > 0, view.drawableSize.height > 0,
              let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let command = queue.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }

        let now = CACurrentMediaTime()
        let dt = Float(min(0.06, max(0, now - previousFrameTime)))
        previousFrameTime = now
        if autoRotate { yaw += dt * 0.16 }

        let eye = SIMD3<Float>(
            zoom * cos(pitch) * sin(yaw),
            3.2 + zoom * sin(pitch),
            zoom * cos(pitch) * cos(yaw)
        )
        let aspect = Float(view.drawableSize.width / view.drawableSize.height)
        var uniforms = NovaSceneUniforms(
            viewProjection: Self.projection(aspect: aspect)
                * Self.lookAt(eye: eye, target: SIMD3<Float>(0, 1.9, 0))
        )
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setVertexBuffer(mesh, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<NovaSceneUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
        encoder.endEncoding()
        command.present(drawable)
        command.commit()
    }
}

struct NovaVoxelView: UIViewRepresentable {
    let fps: Int
    let worldSide: Int
    let worldSeed: Int
    let palette: String

    final class Coordinator: NSObject {
        var renderer: NovaVoxelRenderer?
        var panPrevious: CGPoint = .zero
        var pinchPrevious: CGFloat = 1

        @objc func onPan(_ gesture: UIPanGestureRecognizer) {
            guard let renderer else { return }
            let delta = gesture.translation(in: gesture.view)
            renderer.pan(dx: delta.x - panPrevious.x, dy: delta.y - panPrevious.y)
            panPrevious = gesture.state == .ended || gesture.state == .cancelled
                ? .zero : delta
        }
        @objc func onPinch(_ gesture: UIPinchGestureRecognizer) {
            guard let renderer else { return }
            let scale = gesture.scale / pinchPrevious
            if scale.isFinite && scale > 0 { renderer.magnify(scale: scale) }
            pinchPrevious = gesture.state == .ended || gesture.state == .cancelled
                ? 1 : gesture.scale
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.clearDepth = 1
        view.clearColor = MTLClearColor(red: 0.015, green: 0.035, blue: 0.085, alpha: 1)
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = max(20, min(fps, 60))
        if let renderer = NovaVoxelRenderer(view: view, worldSide: worldSide,
                                             seed: worldSeed, palette: palette) {
            context.coordinator.renderer = renderer
            view.delegate = renderer
        }
        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.onPan(_:)))
        let pinch = UIPinchGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.onPinch(_:)))
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        view.preferredFramesPerSecond = max(20, min(fps, 60))
    }
}

struct NovaVoxelEngineScreen: View {
    @AppStorage("nova-metal-fps") private var fps = 60
    @AppStorage("nova-world-side") private var worldSide = 24
    @AppStorage("nova-world-seed") private var seed = 2026
    @AppStorage("nova-world-palette") private var palette = "aurora"
    @State private var refreshID = 0

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label("NovaEngine 3D", systemImage: "cube.transparent.fill")
                    .font(.headline.bold())
                Spacer()
                Text("\(worldSide)×\(worldSide) · \(fps) FPS")
                    .font(.caption.monospaced())
                    .foregroundStyle(.cyan)
            }
            NovaVoxelView(fps: fps, worldSide: worldSide, worldSeed: seed, palette: palette)
                .id("\(worldSide)-\(seed)-\(palette)-\(refreshID)")
                .frame(maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            HStack(spacing: 12) {
                Label("Przeciągnij: obrót", systemImage: "hand.draw")
                Spacer()
                Label("Uszczypnij: zoom", systemImage: "plus.magnifyingglass")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Picker("Biom", selection: $palette) {
                Text("Neon").tag("aurora")
                Text("Las").tag("forest")
                Text("Lawa").tag("lava")
            }
            .pickerStyle(.segmented)
            HStack(spacing: 8) {
                Text("Seed: \(seed)").font(.caption.monospaced())
                Spacer()
                Button {
                    seed = Int.random(in: 1...999_999)
                } label: {
                    Label("Nowy teren", systemImage: "dice")
                }
                .buttonStyle(.bordered)
                Button {
                    refreshID += 1
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Resetuj kamerę")
            }
            Text("Autorski renderer Metal: procedurally generowany teren, 3 biomy, wybór ziarna, ukrywanie niewidocznych ścian, bufor głębi i gesty kamery. Nie jest to Minecraft Java ani most OpenGL/GLFW.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("NovaEngine 3D")
    }
}
