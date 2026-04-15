import SwiftUI

struct WeatherTab: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var app: AppState
    @State private var newLocation = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(app.locations, id: \.self) { loc in
                        Text(loc)
                    }
                    .onDelete { app.locations.remove(atOffsets: $0) }
                    .onMove   { app.locations.move(fromOffsets: $0, toOffset: $1) }

                    HStack {
                        TextField("City, State or ZIP", text: $newLocation)
                            .autocorrectionDisabled()
                            .focused($inputFocused)
                            .onSubmit(addLocation)
                        if !trimmedNew.isEmpty {
                            Button("Add", action: addLocation)
                                .disabled(app.locations.count >= Payloads.locationMaxCount)
                        }
                    }
                } header: {
                    Text("Locations")
                } footer: {
                    Text("\(app.locations.count) of \(Payloads.locationMaxCount). Enter a ZIP code or \"City, State\" — the device geocodes each via Open-Meteo.")
                }

                Section {
                    Button("Show on Display") {
                        app.send(via: ble, kind: .mode, data: Payloads.mode(.weather), label: "Show Weather")
                    }
                    .disabled(!canWrite)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Weather")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save", action: saveLocations)
                        .fontWeight(.semibold)
                        .disabled(!canWrite || app.locations.isEmpty)
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
    private var trimmedNew: String { newLocation.trimmingCharacters(in: .whitespaces) }

    private func addLocation() {
        let loc = trimmedNew
        newLocation = ""
        inputFocused = false
        guard !loc.isEmpty,
              !loc.contains("|"),
              loc.utf8.count <= Payloads.locationMaxLen,
              !app.locations.contains(loc),
              app.locations.count < Payloads.locationMaxCount
        else {
            return
        }
        app.locations.append(loc)
    }

    private func saveLocations() {
        do {
            let data = try Payloads.locations(app.locations)
            app.send(via: ble, kind: .locations, data: data, label: "Locations")
        } catch {
            app.show("Locations: \(error)", isError: true)
        }
    }
}
