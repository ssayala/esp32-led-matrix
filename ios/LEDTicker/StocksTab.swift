import SwiftUI

struct StocksTab: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var app: AppState
    @State private var newTicker = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(app.tickers, id: \.self) { t in
                        Text(t).font(.body.monospaced())
                    }
                    .onDelete { app.tickers.remove(atOffsets: $0) }
                    .onMove   { app.tickers.move(fromOffsets: $0, toOffset: $1) }

                    HStack {
                        TextField("Add symbol (e.g. NVDA)", text: $newTicker)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .focused($inputFocused)
                            .onSubmit(addTicker)
                        if !trimmedNew.isEmpty {
                            Button("Add", action: addTicker)
                                .disabled(app.tickers.count >= Payloads.tickerMaxCount)
                        }
                    }
                } header: {
                    Text("Tickers")
                } footer: {
                    Text("\(app.tickers.count) of \(Payloads.tickerMaxCount). Pull down to refresh quotes.")
                }

                Section {
                    Button("Show on Display") {
                        app.send(via: ble, kind: .mode, data: Payloads.mode(.stocks), label: "Show Stocks")
                    }
                    .disabled(!canWrite)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await reloadQuotes() }
            .navigationTitle("Stocks")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save", action: saveTickers)
                        .fontWeight(.semibold)
                        .disabled(!canWrite || app.tickers.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { inputFocused = false }
                }
            }
        }
    }

    // MARK: - Actions

    private var canWrite: Bool { ble.state == .ready }
    private var trimmedNew: String { newTicker.trimmingCharacters(in: .whitespaces) }

    private func addTicker() {
        let t = trimmedNew.uppercased()
        newTicker = ""
        inputFocused = false
        guard !t.isEmpty,
              t.utf8.count <= Payloads.tickerMaxLen,
              !app.tickers.contains(t),
              app.tickers.count < Payloads.tickerMaxCount
        else {
            return
        }
        app.tickers.append(t)
    }

    private func saveTickers() {
        do {
            let data = try Payloads.tickers(app.tickers)
            app.send(via: ble, kind: .tickers, data: data, label: "Tickers")
        } catch {
            app.show("Tickers: \(error)", isError: true)
        }
    }

    /// Pull-to-refresh: tell the device to force-fetch new quotes from Finnhub.
    /// We don't get a response from the device, so we hold the spinner briefly
    /// so it feels connected to the action rather than snapping back instantly.
    private func reloadQuotes() async {
        guard canWrite else { return }
        app.send(via: ble, kind: .command, data: Payloads.command("reload"), label: "Reload")
        try? await Task.sleep(nanoseconds: 1_200_000_000)
    }
}
