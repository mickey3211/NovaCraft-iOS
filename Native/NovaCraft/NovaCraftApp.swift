import SwiftUI

@main
struct NovaCraftApp: App {
    @StateObject private var state = LauncherState()

    var body: some Scene {
        WindowGroup {
            LauncherView()
                .environmentObject(state)
                .preferredColorScheme(.dark)
        }
    }
}
