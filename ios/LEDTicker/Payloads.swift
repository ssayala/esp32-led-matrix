import Foundation

enum Mode: String, CaseIterable {
    case stocks, messages
}

enum PayloadError: Error, Equatable, CustomStringConvertible {
    case empty(field: String)
    case tooLong(field: String, limit: Int, actual: Int)
    case invalidSSID

    var description: String {
        switch self {
        case .empty(let f):
            return "\(f) cannot be empty"
        case .tooLong(let f, let limit, let actual):
            return "\(f) too long: \(actual) > \(limit) bytes"
        case .invalidSSID:
            return "SSID is empty, too long, or contains '|'"
        }
    }
}

/// Pure payload-formatting layer that mirrors `tools/led.py`.
/// Kept free of CoreBluetooth so it can be unit tested on any platform.
enum Payloads {
    static let messagesMaxBytes = 511
    static let wifiSsidMaxBytes = 63
    static let apiKeyMaxBytes = 63
    static let tickerMaxCount = 10
    static let tickerMaxLen = 15
    static let messagesMaxCount = 20

    static func wifi(ssid: String, password: String) throws -> Data {
        let s = ssid.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, !s.contains("|"), s.utf8.count <= wifiSsidMaxBytes else {
            throw PayloadError.invalidSSID
        }
        return Data("\(s)|\(password)".utf8)
    }

    static func apiKey(_ key: String) throws -> Data {
        let k = key.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { throw PayloadError.empty(field: "API key") }
        guard k.utf8.count <= apiKeyMaxBytes else {
            throw PayloadError.tooLong(field: "API key", limit: apiKeyMaxBytes, actual: k.utf8.count)
        }
        return Data(k.utf8)
    }

    /// Parses a comma-separated ticker string, uppercases, trims, dedupes order-preserving.
    static func tickers(fromCSV csv: String) throws -> Data {
        let list = csv.split(separator: ",").map { String($0) }
        return try tickers(list)
    }

    static func tickers(_ list: [String]) throws -> Data {
        var seen = Set<String>()
        var cleaned: [String] = []
        for raw in list {
            let t = raw.trimmingCharacters(in: .whitespaces).uppercased()
            guard !t.isEmpty, t.utf8.count <= tickerMaxLen, seen.insert(t).inserted else { continue }
            cleaned.append(t)
            if cleaned.count == tickerMaxCount { break }
        }
        guard !cleaned.isEmpty else { throw PayloadError.empty(field: "Tickers") }
        return Data(cleaned.joined(separator: ",").utf8)
    }

    /// Parses a pipe-separated message string.
    static func messages(fromJoined joined: String) throws -> Data {
        let list = joined.split(separator: "|", omittingEmptySubsequences: false).map { String($0) }
        return try messages(list)
    }

    static func messages(_ list: [String]) throws -> Data {
        let cleaned = list
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(messagesMaxCount)
        guard !cleaned.isEmpty else { throw PayloadError.empty(field: "Messages") }
        let joined = cleaned.joined(separator: "|")
        let bytes = joined.utf8.count
        guard bytes <= messagesMaxBytes else {
            throw PayloadError.tooLong(field: "Messages", limit: messagesMaxBytes, actual: bytes)
        }
        return Data(joined.utf8)
    }

    static func mode(_ m: Mode) -> Data {
        Data(m.rawValue.utf8)
    }

    static func command(_ cmd: String) -> Data {
        Data(cmd.utf8)
    }

    // MARK: - Parsers for values read back from the device

    /// Decode a characteristic value as UTF-8, trimming any trailing NULs
    /// the firmware may have left from its fixed-size buffers.
    static func parseString(_ data: Data) -> String {
        let trimmed = data.prefix { $0 != 0 }
        return String(data: Data(trimmed), encoding: .utf8) ?? ""
    }

    /// Parse a comma-separated ticker list as written by the firmware.
    static func parseTickers(_ data: Data) -> [String] {
        let raw = parseString(data)
        guard !raw.isEmpty else { return [] }
        return raw
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty }
    }

    /// Parse a pipe-separated message list as written by the firmware.
    static func parseMessages(_ data: Data) -> [String] {
        let raw = parseString(data)
        guard !raw.isEmpty else { return [] }
        return raw
            .split(separator: "|", omittingEmptySubsequences: true)
            .map(String.init)
    }

    static func parseMode(_ data: Data) -> Mode? {
        Mode(rawValue: parseString(data))
    }
}
