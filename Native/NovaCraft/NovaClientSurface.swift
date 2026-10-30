import SwiftUI
import UIKit
import Darwin

/// Owns the UIKit surface while Java owns a GLFW window. No diagnostic buttons.
@MainActor
final class NovaClientSurface: ObservableObject {
    static let shared = NovaClientSurface()
    @Published private(set) var presented = false
    private(set) var view: UIView?
    private var library: UnsafeMutableRawPointer?
    private var close: (@convention(c) () -> Void)?
    private var dispose: (@convention(c) () -> Int32)?

    func prepare() async throws {
        guard !presented else { throw failure("Okno gry jest już otwarte.") }
        let url = Bundle.main.bundleURL.appendingPathComponent("Frameworks/libglfw.dylib")
        guard let handle = dlopen(url.path, RTLD_NOW | RTLD_LOCAL) else {
            throw failure("Nie można załadować biblioteki okna GLFW.")
        }
        library = handle // Keep loaded while the JVM lives.
        guard let createSymbol = dlsym(handle, "nova_glfw_create_view"),
              let closeSymbol = dlsym(handle, "nova_glfw_request_close"),
              let disposeSymbol = dlsym(handle, "nova_glfw_dispose_surface") else {
            throw failure("Biblioteka GLFW nie zawiera adaptera NovaCraft.")
        }
        let create = unsafeBitCast(createSymbol, to: (@convention(c) () -> UnsafeMutableRawPointer?).self)
        close = unsafeBitCast(closeSymbol, to: (@convention(c) () -> Void).self)
        dispose = unsafeBitCast(disposeSymbol, to: (@convention(c) () -> Int32).self)
        guard let pointer = create() else { throw failure("Nie udało się utworzyć okna gry.") }
        view = Unmanaged<UIView>.fromOpaque(pointer).takeRetainedValue()
        presented = true
        // Wait for SwiftUI presentation and layout before Java calls glfwInit.
        for _ in 0..<250 {
            if let view, view.window != nil, view.bounds.width > 0, view.bounds.height > 0 {
                view.layoutIfNeeded()
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        finish()
        throw failure("Okno gry nie pojawiło się na ekranie.")
    }
    func requestClose() { close?() }
    func finish() {
        // Never tear a live CAMetalLayer out from beneath EGL.
        if dispose?() == 1 {
            presented = false
            view = nil
        }
    }
    private func failure(_ text: String) -> NSError {
        NSError(domain: "NovaCraft.Window", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
}

struct NovaClientSurfaceScreen: View {
    @ObservedObject var host = NovaClientSurface.shared
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
            if let view = host.view { HostedGameView(gameView: view) }
            Button("Zamknij grę") { host.requestClose() }
                .buttonStyle(.borderedProminent).padding()
        }
        .ignoresSafeArea()
        .interactiveDismissDisabled()
    }
}
private struct HostedGameView: UIViewRepresentable {
    let gameView: UIView
    func makeUIView(context: Context) -> UIView { gameView }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
