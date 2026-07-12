import SwiftUI
import FirebaseCore
import FirebaseAnalytics

@main
struct coo_cooApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        FirebaseApp.configure()
        CooAnalytics.logAppLaunch()
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
