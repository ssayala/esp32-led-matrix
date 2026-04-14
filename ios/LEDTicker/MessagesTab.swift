import SwiftUI

struct MessagesTab: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var app: AppState
    @State private var newMessage = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(app.messages, id: \.self) { m in
                        Text(m)
                    }
                    .onDelete { app.messages.remove(atOffsets: $0) }
                    .onMove   { app.messages.move(fromOffsets: $0, toOffset: $1) }

                    HStack {
                        TextField("New message", text: $newMessage)
                            .onSubmit(addMessage)
                        if !trimmedNew.isEmpty {
                            Button("Add", action: addMessage)
                                .disabled(app.messages.count >= Payloads.messagesMaxCount)
                        }
                    }
                } header: {
                    Text("Messages")
                } footer: {
                    HStack {
                        Text("\(app.messages.count) of \(Payloads.messagesMaxCount)")
                        Spacer()
                        Text("\(payloadBytes) / \(Payloads.messagesMaxBytes) bytes")
                            .foregroundStyle(overLimit ? .red : .secondary)
                    }
                }

                Section {
                    Button("Show on Display") {
                        app.send(via: ble, kind: .mode, data: Payloads.mode(.messages), label: "Show Messages")
                    }
                    .disabled(!canWrite)
                }
            }
            .navigationTitle("Messages")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save", action: saveMessages)
                        .fontWeight(.semibold)
                        .disabled(!canWrite || app.messages.isEmpty || overLimit)
                }
            }
        }
    }

    // MARK: - Actions

    private var canWrite: Bool { ble.state == .ready }
    private var trimmedNew: String { newMessage.trimmingCharacters(in: .whitespaces) }

    private var payloadBytes: Int {
        app.messages
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "|")
            .utf8.count
    }

    private var overLimit: Bool { payloadBytes > Payloads.messagesMaxBytes }

    private func addMessage() {
        let m = trimmedNew
        guard !m.isEmpty, app.messages.count < Payloads.messagesMaxCount else {
            newMessage = ""
            return
        }
        app.messages.append(m)
        newMessage = ""
    }

    private func saveMessages() {
        do {
            let data = try Payloads.messages(app.messages)
            app.send(via: ble, kind: .messages, data: data, label: "Messages")
        } catch {
            app.show("Messages: \(error)", isError: true)
        }
    }
}
