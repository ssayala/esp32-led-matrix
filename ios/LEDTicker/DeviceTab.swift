import SwiftUI

struct DeviceTab: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var app: AppState
    @State private var showResetConfirm = false
    @State private var baselinesLoaded = false

    var body: some View {
        NavigationStack {
            Form {
                statusSection
                wifiSection
                apiKeySection
                resetSection
            }
            .navigationTitle("Device")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save", action: saveDirty)
                        .fontWeight(.semibold)
                        .disabled(!canWrite || !anyDirty)
                }
            }
            .onAppear(perform: loadBaselinesIfNeeded)
            .confirmationDialog(
                "Reset everything on the device?",
                isPresented: $showResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Reset", role: .destructive) {
                    app.send(via: ble, kind: .command, data: Payloads.command("reset"), label: "Reset")
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Wipes WiFi, API key, tickers, messages, and cached stocks from the device.")
            }
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(statusTint.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: statusSymbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(statusTint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(ble.peripheralName ?? "LED-Ticker").font(.body)
                    Text(connectionLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isTransitioning {
                    ProgressView()
                }
            }
            .padding(.vertical, 4)

            Button(action: toggleConnection) {
                Text(connectButtonLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(connectTextColor)
            .disabled(!connectButtonEnabled)
        }
    }

    private var isTransitioning: Bool {
        switch ble.state {
        case .scanning, .connecting, .discovering: return true
        default: return false
        }
    }

    private var connectButtonLabel: String {
        switch ble.state {
        case .ready:        return "Disconnect"
        case .scanning:     return "Scanning…"
        case .connecting:   return "Connecting…"
        case .discovering:  return "Discovering…"
        default:            return "Connect"
        }
    }

    private var connectButtonEnabled: Bool {
        switch ble.state {
        case .poweredOff, .unauthorized:             return false
        case .scanning, .connecting, .discovering:   return false
        default:                                     return true
        }
    }

    private var wifiSection: some View {
        Section {
            TextField("SSID", text: $app.ssid)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: $app.password)
        } header: {
            Text("WiFi")
        }
    }

    private var apiKeySection: some View {
        Section {
            SecureField("API Key", text: $app.apikey)
        } header: {
            Text("Finnhub API Key")
        } footer: {
            Text("Get a free API key at finnhub.io")
        }
    }

    private var resetSection: some View {
        Section {
            Button("Reset Device", role: .destructive) {
                showResetConfirm = true
            }
            .disabled(!canWrite)
        }
    }

    // MARK: - Dirty tracking

    private var wifiDirty: Bool {
        app.ssid != app.baselineSsid || app.password != app.baselinePassword
    }

    private var apiKeyDirty: Bool {
        app.apikey != app.baselineApiKey
    }

    private var anyDirty: Bool { wifiDirty || apiKeyDirty }

    private func loadBaselinesIfNeeded() {
        guard !baselinesLoaded else { return }
        app.baselineSsid     = app.ssid
        app.baselinePassword = app.password
        app.baselineApiKey   = app.apikey
        baselinesLoaded      = true
    }

    // MARK: - Actions

    private var canWrite: Bool { ble.state == .ready }

    private func toggleConnection() {
        if ble.state == .ready {
            ble.disconnect()
        } else {
            ble.startScan()
        }
    }

    private func saveDirty() {
        if wifiDirty {
            do {
                let data = try Payloads.wifi(ssid: app.ssid, password: app.password)
                app.send(via: ble, kind: .wifi, data: data, label: "WiFi")
                app.baselineSsid = app.ssid
                app.baselinePassword = app.password
            } catch {
                app.show("WiFi: \(error)", isError: true)
                return
            }
        }
        if apiKeyDirty {
            do {
                let data = try Payloads.apiKey(app.apikey)
                app.send(via: ble, kind: .apikey, data: data, label: "API Key")
                app.baselineApiKey = app.apikey
            } catch {
                app.show("API Key: \(error)", isError: true)
                return
            }
        }
    }

    // MARK: - Status decoration

    private var statusSymbol: String {
        switch ble.state {
        case .ready:
            return "antenna.radiowaves.left.and.right"
        case .scanning, .connecting, .discovering:
            return "antenna.radiowaves.left.and.right"
        case .poweredOff:
            return "wifi.slash"
        case .unauthorized, .failed:
            return "exclamationmark.triangle.fill"
        case .idle:
            return "antenna.radiowaves.left.and.right.slash"
        }
    }

    private var statusTint: Color {
        switch ble.state {
        case .ready:                                return .green
        case .scanning, .connecting, .discovering:  return .orange
        case .poweredOff, .unauthorized, .failed:   return .red
        case .idle:                                 return .gray
        }
    }

    private var connectTextColor: Color {
        switch ble.state {
        case .ready:                     return .red
        case .poweredOff, .unauthorized: return .gray
        default:                         return .accentColor
        }
    }

    private var connectionLabel: String {
        switch ble.state {
        case .idle:            return "Not connected"
        case .poweredOff:      return "Bluetooth off"
        case .unauthorized:    return "Bluetooth permission denied"
        case .scanning:        return "Scanning…"
        case .connecting:      return "Connecting…"
        case .discovering:     return "Discovering…"
        case .ready:           return "Connected"
        case .failed(let m):   return "Failed: \(m)"
        }
    }
}
