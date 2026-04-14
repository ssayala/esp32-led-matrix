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
            MessagesTab()
                .tabItem { Label("Messages", systemImage: "text.bubble") }
        }
        .toastOverlay($appState.toast)
        .onChange(of: ble.state) { newState in
            if case .ready = newState {
                appState.refreshFromDevice(via: ble)
            }
        }
    }
}

#Preview {
    RootView()
        .environmentObject(BLEManager())
        .environmentObject(AppState())
}
