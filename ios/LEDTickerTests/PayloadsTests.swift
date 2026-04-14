import XCTest
@testable import LEDTicker

final class PayloadsTests: XCTestCase {

    // MARK: - wifi

    func test_wifi_formatsSsidPipePassword() throws {
        let data = try Payloads.wifi(ssid: "MyNet", password: "pw|with|pipes")
        XCTAssertEqual(String(data: data, encoding: .utf8), "MyNet|pw|with|pipes")
    }

    func test_wifi_trimsSsidWhitespace() throws {
        let data = try Payloads.wifi(ssid: "  Home  ", password: "pw")
        XCTAssertEqual(String(data: data, encoding: .utf8), "Home|pw")
    }

    func test_wifi_rejectsEmptySsid() {
        XCTAssertThrowsError(try Payloads.wifi(ssid: "   ", password: "pw")) { err in
            XCTAssertEqual(err as? PayloadError, .invalidSSID)
        }
    }

    func test_wifi_rejectsPipeInSsid() {
        XCTAssertThrowsError(try Payloads.wifi(ssid: "bad|ssid", password: "pw")) { err in
            XCTAssertEqual(err as? PayloadError, .invalidSSID)
        }
    }

    func test_wifi_rejectsOversizedSsid() {
        let big = String(repeating: "x", count: 64)
        XCTAssertThrowsError(try Payloads.wifi(ssid: big, password: "pw")) { err in
            XCTAssertEqual(err as? PayloadError, .invalidSSID)
        }
    }

    // MARK: - apiKey

    func test_apiKey_trimsAndEncodes() throws {
        let data = try Payloads.apiKey("  abc123  ")
        XCTAssertEqual(String(data: data, encoding: .utf8), "abc123")
    }

    func test_apiKey_rejectsEmpty() {
        XCTAssertThrowsError(try Payloads.apiKey("")) { err in
            XCTAssertEqual(err as? PayloadError, .empty(field: "API key"))
        }
    }

    func test_apiKey_rejectsOversized() {
        let big = String(repeating: "k", count: 64)
        XCTAssertThrowsError(try Payloads.apiKey(big))
    }

    // MARK: - tickers

    func test_tickers_uppercasesTrimsAndJoins() throws {
        let data = try Payloads.tickers(fromCSV: " aapl, msft ,googl ")
        XCTAssertEqual(String(data: data, encoding: .utf8), "AAPL,MSFT,GOOGL")
    }

    func test_tickers_dedupesPreservingOrder() throws {
        let data = try Payloads.tickers(fromCSV: "AAPL,aapl,MSFT,MSFT,NVDA")
        XCTAssertEqual(String(data: data, encoding: .utf8), "AAPL,MSFT,NVDA")
    }

    func test_tickers_capsAtTen() throws {
        let many = (1...15).map { "SYM\($0)" }.joined(separator: ",")
        let data = try Payloads.tickers(fromCSV: many)
        let str = String(data: data, encoding: .utf8)!
        XCTAssertEqual(str.split(separator: ",").count, 10)
        XCTAssertTrue(str.hasPrefix("SYM1,SYM2"))
    }

    func test_tickers_rejectsAllEmpty() {
        XCTAssertThrowsError(try Payloads.tickers(fromCSV: " , , "))
    }

    func test_tickers_dropsOversizedSymbol() throws {
        // tickerMaxLen == 15, so 16-char symbol is dropped silently.
        let data = try Payloads.tickers(fromCSV: "AAPL,THISISWAYTOOLONGXX,MSFT")
        XCTAssertEqual(String(data: data, encoding: .utf8), "AAPL,MSFT")
    }

    // MARK: - messages

    func test_messages_joinsWithPipe() throws {
        let data = try Payloads.messages(fromJoined: "a|b|c")
        XCTAssertEqual(String(data: data, encoding: .utf8), "a|b|c")
    }

    func test_messages_trimsAndDropsEmpty() throws {
        let data = try Payloads.messages(fromJoined: "  hi  ||  there  |")
        XCTAssertEqual(String(data: data, encoding: .utf8), "hi|there")
    }

    func test_messages_rejectsAllEmpty() {
        XCTAssertThrowsError(try Payloads.messages(fromJoined: " | | "))
    }

    func test_messages_rejectsOverMaxBytes() {
        let big = String(repeating: "x", count: Payloads.messagesMaxBytes + 1)
        XCTAssertThrowsError(try Payloads.messages([big])) { err in
            guard case .tooLong(_, let limit, let actual)? = err as? PayloadError else {
                return XCTFail("wrong error: \(err)")
            }
            XCTAssertEqual(limit, Payloads.messagesMaxBytes)
            XCTAssertEqual(actual, Payloads.messagesMaxBytes + 1)
        }
    }

    func test_messages_capsAt20() throws {
        let many = (1...25).map { "m\($0)" }
        let data = try Payloads.messages(many)
        let str = String(data: data, encoding: .utf8)!
        XCTAssertEqual(str.split(separator: "|").count, 20)
    }

    // MARK: - mode / command

    func test_modeAndCommand_passthrough() {
        XCTAssertEqual(String(data: Payloads.mode(.stocks), encoding: .utf8), "stocks")
        XCTAssertEqual(String(data: Payloads.mode(.messages), encoding: .utf8), "messages")
        XCTAssertEqual(String(data: Payloads.command("reload"), encoding: .utf8), "reload")
        XCTAssertEqual(String(data: Payloads.command("reset"), encoding: .utf8), "reset")
    }

    // MARK: - parsers (values read back from device)

    func test_parseString_stripsTrailingNuls() {
        var data = Data("hello".utf8)
        data.append(contentsOf: [0, 0, 0])
        XCTAssertEqual(Payloads.parseString(data), "hello")
    }

    func test_parseString_emptyData() {
        XCTAssertEqual(Payloads.parseString(Data()), "")
    }

    func test_parseTickers_splitsAndUppercases() {
        let data = Data("aapl,Msft,GOOGL".utf8)
        XCTAssertEqual(Payloads.parseTickers(data), ["AAPL", "MSFT", "GOOGL"])
    }

    func test_parseTickers_emptyReturnsEmpty() {
        XCTAssertEqual(Payloads.parseTickers(Data()), [])
        XCTAssertEqual(Payloads.parseTickers(Data("".utf8)), [])
    }

    func test_parseTickers_roundTrip() throws {
        let original = ["AAPL", "MSFT", "NVDA"]
        let encoded = try Payloads.tickers(original)
        XCTAssertEqual(Payloads.parseTickers(encoded), original)
    }

    func test_parseMessages_splitsOnPipe() {
        let data = Data("hi|there|friend".utf8)
        XCTAssertEqual(Payloads.parseMessages(data), ["hi", "there", "friend"])
    }

    func test_parseMessages_emptyReturnsEmpty() {
        XCTAssertEqual(Payloads.parseMessages(Data()), [])
    }

    func test_parseMessages_roundTrip() throws {
        let original = ["Take a break!", "Drink water!", "Stand up!"]
        let encoded = try Payloads.messages(original)
        XCTAssertEqual(Payloads.parseMessages(encoded), original)
    }

    func test_parseMode_validValues() {
        XCTAssertEqual(Payloads.parseMode(Data("stocks".utf8)), .stocks)
        XCTAssertEqual(Payloads.parseMode(Data("messages".utf8)), .messages)
    }

    func test_parseMode_invalidReturnsNil() {
        XCTAssertNil(Payloads.parseMode(Data("wat".utf8)))
        XCTAssertNil(Payloads.parseMode(Data()))
    }
}
