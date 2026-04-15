import Foundation
import Combine

struct Toast: Equatable {
    let id = UUID()
    let text: String
    let isError: Bool
}

/// Shared observable state for all tabs.
///
/// The device is the source of truth for tickers, messages, and
/// locations: these start empty on launch and are populated only after
/// a successful connect + read, so the UI never shows stale or
/// fabricated defaults when disconnected. WiFi SSID and API key are
/// persisted to `UserDefaults` so the user doesn't have to retype them
/// on every launch; the WiFi password is intentionally never persisted
/// and is never exposed over BLE.
final class AppState: ObservableObject {
    @Published var ssid: String {
        didSet { UserDefaults.standard.set(ssid, forKey: Keys.ssid) }
    }
    @Published var password: String = ""
    @Published var apikey: String {
        didSet { UserDefaults.standard.set(apikey, forKey: Keys.apikey) }
    }
    @Published var tickers: [String] = []
    @Published var messages: [String] = []
    @Published var locations: [String] = []

    @Published var toast: Toast?

    // Baselines for dirty tracking. Set from device reads and after
    // successful writes. DeviceTab uses these to decide whether to
    // enable its Save button.
    @Published var baselineSsid: String = ""
    @Published var baselinePassword: String = ""
    @Published var baselineApiKey: String = ""

    private enum Keys {
        static let ssid   = "state.ssid"
        static let apikey = "state.apikey"
    }

    init() {
        let d = UserDefaults.standard
        self.ssid   = d.string(forKey: Keys.ssid) ?? ""
        self.apikey = d.string(forKey: Keys.apikey) ?? ""
    }

    /// Wipe all fields that come from the device. Called when the BLE
    /// connection is dropped so stale data never lingers on screen.
    func clearDeviceState() {
        tickers = []
        messages = []
        locations = []
    }

    func show(_ text: String, isError: Bool = false) {
        toast = Toast(text: text, isError: isError)
    }

    /// Fire a write and update the toast with the outcome.
    func send(via ble: BLEManager, kind: CharKind, data: Data, label: String) {
        show("Sending \(label)…")
        ble.write(kind, data) { [weak self] err in
            guard let self else { return }
            if let err {
                self.show("\(label) failed: \(err.localizedDescription)", isError: true)
            } else {
                self.show("\(label) sent")
            }
        }
    }

    /// Read current configuration from the device and overwrite local
    /// fields unconditionally — an empty result means the device has
    /// nothing configured, which the UI should reflect honestly rather
    /// than silently keeping the previous values. Baselines are reset
    /// so the Save button reflects divergence from the device.
    func refreshFromDevice(via ble: BLEManager) {
        ble.readAll([.wifi, .apikey, .tickers, .messages, .locations]) { [weak self] results in
            guard let self else { return }
            let ssidStr   = results[.wifi].map(Payloads.parseString)   ?? ""
            let apiKeyStr = results[.apikey].map(Payloads.parseString) ?? ""
            self.ssid = ssidStr
            self.password = ""
            self.baselineSsid = ssidStr
            self.baselinePassword = ""
            self.apikey = apiKeyStr
            self.baselineApiKey = apiKeyStr
            self.tickers   = results[.tickers].map(Payloads.parseTickers)     ?? []
            self.messages  = results[.messages].map(Payloads.parseMessages)   ?? []
            self.locations = results[.locations].map(Payloads.parseLocations) ?? []
            self.show("Loaded from device")
        }
    }
}
