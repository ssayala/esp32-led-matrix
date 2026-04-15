import Foundation
import CoreBluetooth

enum CharKind: String, CaseIterable {
    case tickers   = "BEB5483E-36E1-4688-B7F5-EA07361B26A8"
    case mode      = "BEB5483E-36E1-4688-B7F5-EA07361B26A9"
    case messages  = "BEB5483E-36E1-4688-B7F5-EA07361B26AA"
    case command   = "BEB5483E-36E1-4688-B7F5-EA07361B26AB"
    case wifi      = "BEB5483E-36E1-4688-B7F5-EA07361B26AC"
    case apikey    = "BEB5483E-36E1-4688-B7F5-EA07361B26AD"
    case locations = "BEB5483E-36E1-4688-B7F5-EA07361B26AE"

    var uuid: CBUUID { CBUUID(string: rawValue) }
}

enum ConnectionState: Equatable {
    case idle
    case poweredOff
    case unauthorized
    case scanning
    case connecting
    case discovering
    case ready
    case failed(String)
}

/// Thin wrapper around CoreBluetooth for the LED-Ticker peripheral.
///
/// The firmware exposes seven characteristics on a single service: six
/// are read/write (tickers, mode, messages, wifi SSID, apikey, locations)
/// and one is write-only (command). We scan by service UUID, auto-connect
/// to the first match (or a remembered identifier), discover
/// characteristics, and serialize both reads and writes through simple
/// queues so each one completes before the next is issued.
final class BLEManager: NSObject, ObservableObject {
    static let serviceUUID = CBUUID(string: "4FAFC201-1FB5-459E-8FCC-C5C9C331914B")
    private static let peripheralIdKey = "LEDTicker.peripheral.id"

    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var peripheralName: String?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var characteristics: [CharKind: CBCharacteristic] = [:]
    private var scanTimeoutWork: DispatchWorkItem?
    private static let scanTimeout: TimeInterval = 15

    private struct PendingWrite {
        let kind: CharKind
        let data: Data
        let completion: (Error?) -> Void
    }
    private var writeQueue: [PendingWrite] = []
    private var writing = false

    private struct PendingRead {
        let kind: CharKind
        let completion: (Result<Data, Error>) -> Void
    }
    private var readQueue: [PendingRead] = []
    private var reading = false

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan() {
        guard central.state == .poweredOn else { return }
        if case .ready = state { return }
        characteristics.removeAll()
        state = .scanning
        armScanTimeout()

        if let idStr = UserDefaults.standard.string(forKey: Self.peripheralIdKey),
           let uuid = UUID(uuidString: idStr),
           let known = central.retrievePeripherals(withIdentifiers: [uuid]).first {
            connect(known)
            return
        }
        central.scanForPeripherals(withServices: [Self.serviceUUID])
    }

    func disconnect() {
        cancelScanTimeout()
        central.stopScan()
        if let p = peripheral {
            central.cancelPeripheralConnection(p)
        }
        peripheral = nil
        peripheralName = nil
        characteristics.removeAll()
        writeQueue.removeAll()
        writing = false
        readQueue.removeAll()
        reading = false
        state = .idle
    }

    private func armScanTimeout() {
        cancelScanTimeout()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Only fire if we never progressed past scanning.
            guard case .scanning = self.state else { return }
            self.central.stopScan()
            self.state = .failed("Device not found")
        }
        scanTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.scanTimeout, execute: work)
    }

    private func cancelScanTimeout() {
        scanTimeoutWork?.cancel()
        scanTimeoutWork = nil
    }

    func write(_ kind: CharKind, _ data: Data, completion: @escaping (Error?) -> Void = { _ in }) {
        guard case .ready = state else {
            completion(NSError(domain: "LEDTicker", code: -1,
                               userInfo: [NSLocalizedDescriptionKey: "not connected"]))
            return
        }
        writeQueue.append(PendingWrite(kind: kind, data: data, completion: completion))
        pumpWriteQueue()
    }

    func read(_ kind: CharKind, completion: @escaping (Result<Data, Error>) -> Void) {
        guard case .ready = state else {
            completion(.failure(NSError(domain: "LEDTicker", code: -1,
                                        userInfo: [NSLocalizedDescriptionKey: "not connected"])))
            return
        }
        readQueue.append(PendingRead(kind: kind, completion: completion))
        pumpReadQueue()
    }

    /// Reads a set of characteristics in order and invokes `completion`
    /// once with a dictionary of successful results. Failed reads are
    /// omitted — the caller decides what to do about missing keys.
    func readAll(_ kinds: [CharKind],
                 completion: @escaping ([CharKind: Data]) -> Void) {
        var results: [CharKind: Data] = [:]
        var remaining = kinds
        func step() {
            guard !remaining.isEmpty else {
                completion(results)
                return
            }
            let k = remaining.removeFirst()
            read(k) { result in
                if case .success(let data) = result { results[k] = data }
                step()
            }
        }
        step()
    }

    private func connect(_ p: CBPeripheral) {
        cancelScanTimeout()
        central.stopScan()
        peripheral = p
        p.delegate = self
        state = .connecting
        central.connect(p)
    }

    private func pumpWriteQueue() {
        guard !writing, let p = peripheral, let next = writeQueue.first else { return }
        guard let ch = characteristics[next.kind] else {
            writeQueue.removeFirst()
            next.completion(NSError(domain: "LEDTicker", code: -2,
                                    userInfo: [NSLocalizedDescriptionKey: "characteristic \(next.kind) not ready"]))
            pumpWriteQueue()
            return
        }
        writing = true
        p.writeValue(next.data, for: ch, type: .withResponse)
    }

    private func pumpReadQueue() {
        guard !reading, let p = peripheral, let next = readQueue.first else { return }
        guard let ch = characteristics[next.kind] else {
            readQueue.removeFirst()
            next.completion(.failure(NSError(domain: "LEDTicker", code: -2,
                                             userInfo: [NSLocalizedDescriptionKey: "characteristic \(next.kind) not ready"])))
            pumpReadQueue()
            return
        }
        reading = true
        p.readValue(for: ch)
    }
}

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn:    state = .idle
        case .poweredOff:   state = .poweredOff
        case .unauthorized: state = .unauthorized
        case .unsupported:  state = .failed("Bluetooth LE unsupported")
        default:            state = .idle
        }
    }

    func centralManager(_ c: CBCentralManager,
                        didDiscover p: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi: NSNumber) {
        connect(p)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        UserDefaults.standard.set(p.identifier.uuidString, forKey: Self.peripheralIdKey)
        peripheralName = p.name
        state = .discovering
        p.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        state = .failed(error?.localizedDescription ?? "connect failed")
    }

    func centralManager(_ c: CBCentralManager,
                        didDisconnectPeripheral p: CBPeripheral,
                        error: Error?) {
        characteristics.removeAll()
        peripheral = nil
        peripheralName = nil
        writeQueue.removeAll()
        writing = false
        readQueue.removeAll()
        reading = false
        if let err = error {
            state = .failed(err.localizedDescription)
        } else {
            state = .idle
        }
    }
}

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let svc = p.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            state = .failed("service not found")
            return
        }
        p.discoverCharacteristics(CharKind.allCases.map(\.uuid), for: svc)
    }

    func peripheral(_ p: CBPeripheral,
                    didDiscoverCharacteristicsFor svc: CBService,
                    error: Error?) {
        for ch in svc.characteristics ?? [] {
            if let kind = CharKind.allCases.first(where: { $0.uuid == ch.uuid }) {
                characteristics[kind] = ch
            }
        }
        if characteristics.count == CharKind.allCases.count {
            state = .ready
        } else {
            state = .failed("missing characteristics (\(characteristics.count)/\(CharKind.allCases.count))")
        }
    }

    func peripheral(_ p: CBPeripheral,
                    didWriteValueFor ch: CBCharacteristic,
                    error: Error?) {
        writing = false
        if !writeQueue.isEmpty {
            let done = writeQueue.removeFirst()
            done.completion(error)
        }
        pumpWriteQueue()
    }

    func peripheral(_ p: CBPeripheral,
                    didUpdateValueFor ch: CBCharacteristic,
                    error: Error?) {
        reading = false
        if !readQueue.isEmpty {
            let done = readQueue.removeFirst()
            if let err = error {
                done.completion(.failure(err))
            } else {
                done.completion(.success(ch.value ?? Data()))
            }
        }
        pumpReadQueue()
    }
}
