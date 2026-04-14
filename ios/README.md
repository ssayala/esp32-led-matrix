# LED Ticker iOS App

SwiftUI + CoreBluetooth app that mirrors `tools/led.py` — configure the
ESP32 LED Ticker over BLE from your iPhone or iPad.

## Requirements

- Xcode 15 or newer
- iOS 16+ device (the iOS simulator has no Bluetooth radio)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Build

```bash
cd ios
xcodegen generate
open LEDTicker.xcodeproj
```

Then in Xcode:

1. Select the **LEDTicker** scheme.
2. Pick your physical iPhone/iPad as the run destination.
3. Build & run (⌘R). iOS will prompt for Bluetooth permission on first
   launch.

## Signing

The Xcode project is generated from `project.yml` and the pbxproj is
gitignored, so **do not edit signing in Xcode's Signing & Capabilities
pane** — UI edits get wiped the next time `xcodegen generate` runs.

Signing is driven by two xcconfig files in this directory:

| File                    | Checked in? | Purpose                                    |
|-------------------------|-------------|--------------------------------------------|
| `Signing.xcconfig`      | Yes         | Safe defaults (style, identity). No team.  |
| `Signing.local.xcconfig`| **No**      | Your personal `DEVELOPMENT_TEAM` override. |

Simulator builds work out of the box with no local override.

For **device builds**, create `ios/Signing.local.xcconfig` with a single
line:

```
DEVELOPMENT_TEAM = YOURTEAMID
```

You can find your Team ID at
<https://developer.apple.com/account> → Membership. Then run
`xcodegen generate` and build to your device as usual. The `.local`
file is gitignored so your team ID never lands in the public repo.

## Run tests

```bash
cd ios
xcodegen generate
xcodebuild test \
    -project LEDTicker.xcodeproj \
    -scheme LEDTicker \
    -destination 'platform=iOS Simulator,name=iPhone 15'
```

The test target only exercises `Payloads.swift` (pure formatting logic).
`BLEManager` needs a real device and is not unit-tested.

## Layout

```
ios/
├── project.yml            XcodeGen config — regenerate the .xcodeproj from here
├── LEDTicker/
│   ├── LEDTickerApp.swift The @main entry point
│   ├── BLEManager.swift   CoreBluetooth wrapper: scan, connect, queued writes
│   ├── Payloads.swift     Pure payload formatters (mirrors tools/led.py)
│   ├── ContentView.swift  Single-screen SwiftUI form
│   └── Info.plist         Contains NSBluetoothAlwaysUsageDescription
└── LEDTickerTests/
    └── PayloadsTests.swift
```

## Design notes

- **Single-screen form** with sections for WiFi, API key, tickers,
  messages, mode, and reload/reset actions.
- **Last-sent values** are persisted to `UserDefaults` via `@AppStorage`.
  There is no readback from the device (all characteristics are
  write-only), so the app only knows what *it* last sent — if you
  configure the same device from `led.py`, the two will drift.
- **Writes are queued**: every write uses `.withResponse` and the next
  one is only issued after `didWriteValueFor` fires. This matters because
  the firmware has a 10 s cooldown on ticker/reload/reset writes.
- **Auto-reconnect**: on first successful connect the peripheral UUID is
  saved to `UserDefaults`. Subsequent launches call
  `retrievePeripherals(withIdentifiers:)` to reconnect without scanning.
- **No WiFi auto-fill**: iOS does not expose the phone's SSID or
  password to apps without the Access WiFi Information entitlement
  (paid developer account + extra permissions), and never the password.
  The user must type both in.

## Protocol reference

See `../README.md` and `../CLAUDE.md` for the authoritative description
of the BLE service and its characteristics. Payload formats:

| Char      | UUID suffix | Payload                              |
|-----------|-------------|--------------------------------------|
| tickers   | `...A8`     | `AAPL,MSFT,...` (comma-separated)    |
| mode      | `...A9`     | `stocks` or `messages`               |
| messages  | `...AA`     | `m1|m2|...` (≤ 511 bytes)            |
| command   | `...AB`     | `reload` or `reset`                  |
| wifi      | `...AC`     | `SSID|password` (split on first `|`) |
| apikey    | `...AD`     | plain string                         |
