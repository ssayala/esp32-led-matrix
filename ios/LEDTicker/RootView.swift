import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var ble: BLEManager

    var body: some View {
        TabView {
            DeviceTab()
                .tabItem { Label("Device", systemImage: "antenna.radiowaves.left.and.right") }
            StocksTab()
                .tabItem { Label("Stocks", systemImage: "chart.line.uptrend.xyaxis") }
            WeatherTab()
                .tabItem { Label("Weather", systemImage: "cloud.sun.fill") }
            MessagesTab()
                .tabItem { Label("Messages", systemImage: "text.bubble") }
        }
        .toastOverlay($appState.toast)
        .onChange(of: ble.state) { newState in
            if case .ready = newState {
                appState.refreshFromDevice(via: ble)
            } else {
                // Any non-ready transition (disconnect, failure, scanning
                // again) wipes device-sourced fields so the UI never
                // displays stale data while we're not connected.
                appState.clearDeviceState()
            }
        }
    }
}

#Preview {
    RootView()
        .environmentObject(BLEManager())
        .environmentObject(AppState())
}
