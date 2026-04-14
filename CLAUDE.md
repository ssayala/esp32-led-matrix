# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Upload

```bash
pio run -t upload       # build and flash to ESP32-S3
pio device monitor      # serial monitor (115200 baud, /dev/ttyACM0)
pio run                 # build only, no upload
```

After flashing, press the physical reset button on the board to ensure new firmware runs.

## Project Overview

Single-file ESP32-S3 firmware (`src/main.cpp`) that drives a DIYables 4-in-1 MAX7219 LED matrix via SPI. It scrolls two content types:

- **Messages** — pushed over BLE and persisted to NVS, with hardcoded fallbacks from `src/config.h` until set
- **Stock quotes** — fetched from Finnhub API, cached to NVS flash, market-hours aware

A capacitive touch input on GPIO 14 toggles between stocks and messages at runtime. BLE writes can also toggle mode.

## Hardware

- **Board:** Freenove ESP32-S3 (espressif32 @ 6.5.0, Arduino framework)
- **Display:** 4-in-1 MAX7219 8x8 LED matrix, hardware SPI with explicit pin mapping
- **SPI pins:** DIN=GPIO11, CLK=GPIO12, CS=GPIO10 (must call `SPI.begin(CLK, -1, DIN, CS)` before display init — default ESP32-S3 SPI pins don't match)
- **Touch:** GPIO 14, threshold 30000; polled every 50ms with a 2s debounce

## Configuration Model

There are **no build-time secrets**. `src/secrets.h` does not exist and is not needed.

- **`src/config.h`** — compile-time *defaults* only: seed `stockTickers[]` and `fallbackMessages[]`. Used to seed NVS on first boot, and as fallback text on the display.
- **NVS (ESP32 `Preferences`)** — runtime config and cache, set over BLE, survives reboots. Namespaces used: `wifi`, `apikey`, `tickers`, `msgs`, `stocks`.
- **BLE (`LED-Ticker`)** — primary control plane for WiFi creds, Finnhub key, tickers, messages, mode, and commands. On first boot, the display prompts the user to configure WiFi and the API key via BLE before anything else happens.

The companion CLI is `tools/led.py`, invoked as `uv run tools/led.py <cmd>`:
`wifi <SSID...> <password>`, `apikey <key>`, `tickers AAPL,MSFT,...`, `messages "a" "b" ...`, `mode stocks|messages`, `reload`, `reset`.

## Architecture Notes

- **Boot sequence matters** (`setup()`): `initDisplay()` → load all NVS (`wifi`, `apikey`, `msgs`, `tickers`, `stocks` cache) → `showNext()` so the display is live before networking → `connectWifi()` → `initTime()` → `initBLE()` → `fetchStocks()`. This is why the display is never blank even with no network.
- **BLE write → deferred apply pattern**: each characteristic callback copies the payload into a `pending*` buffer and sets a `*UpdatePending` volatile flag. `loop()` consumes these by calling `applyPending*()` handlers, keeping work out of the BLE callback context. Don't do heavy work (network, display) inside callbacks.
- **Fetch cooldown**: writes that trigger network activity (ticker update, `reload`, `reset`) share a 10s `BLE_FETCH_COOLDOWN_MS` gate to prevent hammering Finnhub if the client retries.
- **Reset semantics**: `cmd=reset` clears *all* NVS namespaces (including `wifi` and `apikey`) and re-seeds tickers from `config.h`. After a reset the device needs WiFi and API key reconfigured over BLE.
- **Display gating** (`showNext()`): stocks are shown only when both WiFi and API key are configured *and* `showStocks` is true *and* the cache is non-empty; otherwise falls through to `getMessage()`, which itself returns a setup-prompt string if WiFi or key is missing.
- **Stock cache** loaded on boot before WiFi so the display has content immediately; `isMarketOpen()` skips fetches outside NYSE hours (Mon-Fri 9:30-16:00 ET) unless the cache is empty or the fetch is forced.
- **Main loop** is cooperative: apply pending BLE updates → poll touch → advance display animation → fetch stocks every `FETCH_INTERVAL_MS` (5 min) if WiFi is up. No `delay()` inside `loop()`.

## BLE Service

Device name `LED-Ticker`, service UUID `4fafc201-1fb5-459e-8fcc-c5c9c331914b`. All characteristics are write-only; payload formats and UUIDs are documented in `README.md`. WiFi payload is `SSID|password` split on the first `|` (passwords may contain `|`; SSIDs may not).
