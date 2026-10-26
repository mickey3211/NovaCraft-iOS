import Foundation
import Metal

enum NovaHardwareDiagnostics {
    static func metalStatus() -> String {
        guard let device = MTLCreateSystemDefaultDevice() else { return "Metal GPU unavailable" }
        guard device.makeCommandQueue() != nil else { return "Metal command queue unavailable" }
        return "Metal GPU: \(device.name); command queue ready; Minecraft renderer not implemented"
    }

    static func javaStatus() -> String {
        guard Bundle.main.url(forResource: "libjvm", withExtension: "dylib") != nil else {
            return "Java 21 runtime not bundled; Minecraft cannot start"
        }
        return "JVM library detected; startup not yet verified"
    }
}