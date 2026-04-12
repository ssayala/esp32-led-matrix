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

Single-file ESP32-S3 firmware (`src/main.cpp`) that drives a DIYables 4-in-1 MAX7219 LED matrix via SPI. It scrolls two types of content:

- **Messages** — fetched from a remote JSON endpoint, with hardcoded fallbacks when offline
- **Stock quotes** — fetched from Finnhub API, cached to NVS flash, market-hours aware

A capacitive touch input on GPIO 14 toggles between stocks and messages at runtime.

## Hardware

- **Board:** Freenove ESP32-S3 (espressif32 @ 6.5.0, Arduino framework)
- **Display:** 4-in-1 MAX7219 8x8 LED matrix, hardware SPI with explicit pin mapping
- **SPI pins:** DIN=GPIO11, CLK=GPIO12, CS=GPIO10 (must call `SPI.begin(CLK, -1, DIN, CS)` before display init — default ESP32-S3 SPI pins don't match)
- **Touch:** GPIO 14, threshold 30000 (ESP32-S3 touch values are in the low thousands; resting ~2400, touched ~3000+)

## Secrets

`src/secrets.h` is gitignored. Copy `src/secrets.h.example` to `src/secrets.h` and fill in WiFi credentials, Finnhub API key, messages URL, and stock ticker list. The build will fail with a descriptive `#error` if `secrets.h` is missing.

## Architecture Notes

- **Display control** uses MD_Parola zones and `displayScroll()` for horizontal scrolling text
- **Stock cache** uses ESP32 Preferences (NVS) — survives reboots, loaded on boot before WiFi connects so the display is never blank
- **Market hours** check uses NTP with Eastern Time timezone; fetches are skipped outside NYSE hours (Mon-Fri 9:30-16:00 ET) unless the cache is empty
- **Fetch interval** is 5 minutes; the loop skips fetching entirely if WiFi is disconnected to avoid blocking the display
- **Touch polling** is throttled to every 50ms with a 2-second debounce between toggles
- Comment/uncomment `fetchMessages()` and `fetchStocks()` in `setup()` to control which content sources are active
