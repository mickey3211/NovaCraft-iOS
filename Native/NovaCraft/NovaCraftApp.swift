import SwiftUI
import UIKit

// iOS calls this after relaunching NovaCraft for a completed download.
// Keeping the same session identifier reconnects tasks owned by the system.
final class NovaCraftAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        NovaBackgroundDownloads.shared.acceptBackgroundEvents(
            identifier: identifier, completionHandler: completionHandler)
    }
}

@main
struct NovaCraftApp: App {
    @UIApplicationDelegateAdaptor(NovaCraftAppDelegate.self) private var appDelegate
    @StateObject private var state = LauncherState()
    @StateObject private var background = NovaBackgroundDownloads.shared

    var body: some Scene {
        WindowGroup {
            LauncherView()
                .environmentObject(state)
                .environmentObject(background)
                .preferredColorScheme(.dark)
        }
    }
}
