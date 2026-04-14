import Foundation
import Combine

struct Toast: Equatable {
    let id = UUID()
    let text: String
    let isError: Bool
}

/// Shared observable state for all tabs.
///
/// Form fields are persisted to `UserDefaults` so the app can show
/// *something* before the device is reachable. Once connected, we read
/// the current configuration from the device and overwrite these fields
/// so the UI reflects actual device state. The WiFi password is never
/// exposed over BLE, so after a refresh it stays empty until the user
/// retypes it.
final class AppState: ObservableObject {
    @Published var ssid: String {
        didSet { UserDefaults.standard.set(ssid, forKey: Keys.ssid) }
    }
    @Published var password: String {
        didSet { UserDefaults.standard.set(password, forKey: Keys.password) }
    }
    @Published var apikey: String {
        didSet { UserDefaults.standard.set(apikey, forKey: Keys.apikey) }
    }
    @Published var tickers: [String] {
        didSet { UserDefaults.standard.set(tickers, forKey: Keys.tickers) }
    }
    @Published var messages: [String] {
        didSet { UserDefaults.standard.set(messages, forKey: Keys.messages) }
    }

    @Published var toast: Toast?

    // Baselines for dirty tracking. Set from device reads and after
    // successful writes. DeviceTab uses these to decide whether to
    // enable its Save button.
    @Published var baselineSsid: String = ""
    @Published var baselinePassword: String = ""
    @Published var baselineApiKey: String = ""

    private enum Keys {
        static let ssid     = "state.ssid"
        static let password = "state.password"
        static let apikey   = "state.apikey"
        static let tickers  = "state.tickers"
        static let messages = "state.messages"
    }

    init() {
        let d = UserDefaults.standard
        self.ssid     = d.string(forKey: Keys.ssid) ?? ""
        self.password = d.string(forKey: Keys.password) ?? ""
        self.apikey   = d.string(forKey: Keys.apikey) ?? ""
        self.tickers  = (d.array(forKey: Keys.tickers) as? [String])
            ?? ["AAPL", "MSFT", "GOOGL", "AMZN"]
        self.messages = (d.array(forKey: Keys.messages) as? [String])
            ?? ["Take a break!", "Drink water!", "Stand up!"]
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
    /// fields. Baselines are reset so the Save button reflects
    /// divergence from the device, not from the last send.
    func refreshFromDevice(via ble: BLEManager) {
        ble.readAll([.wifi, .apikey, .tickers, .messages]) { [weak self] results in
            guard let self else { return }
            if let d = results[.wifi] {
                let s = Payloads.parseString(d)
                self.ssid = s
                self.password = ""
                self.baselineSsid = s
                self.baselinePassword = ""
            }
            if let d = results[.apikey] {
                let k = Payloads.parseString(d)
                self.apikey = k
                self.baselineApiKey = k
            }
            if let d = results[.tickers] {
                let list = Payloads.parseTickers(d)
                if !list.isEmpty { self.tickers = list }
            }
            if let d = results[.messages] {
                let list = Payloads.parseMessages(d)
                if !list.isEmpty { self.messages = list }
            }
            self.show("Loaded from device")
        }
    }
}
