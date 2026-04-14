import SwiftUI

@main
struct LEDTickerApp: App {
    @StateObject private var ble = BLEManager()
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(ble)
                .environmentObject(appState)
        }
    }
}
