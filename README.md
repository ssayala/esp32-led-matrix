# LED Matrix Ticker

Scrolling message board and stock ticker using a Freenove ESP32-S3 and a DIYables 4-in-1 MAX7219 LED matrix.

## Features

- Scrolling text display on a 32x8 LED matrix
- Live stock quotes from Finnhub API
- Touch-to-toggle between stocks and messages (capacitive touch on GPIO 14)
- Remote messages fetched from a configurable URL (JSON array of strings)
- Fallback messages when offline
- Stock quotes cached to flash (NVS) — survives reboots
- Market-hours aware — skips API calls when NYSE is closed
- Auto-refreshes every 5 minutes

## Hardware

| Component | Details |
|-----------|---------|
| MCU | Freenove ESP32-S3 |
| Display | DIYables 4-in-1 MAX7219 8x8 LED matrix (SPI) |

### Wiring

| Matrix Pin | ESP32-S3 GPIO |
|------------|---------------|
| VCC | 5V |
| GND | GND |
| DIN | 11 (MOSI) |
| CLK | 12 (SCK) |
| CS | 10 |

Touch input: GPIO 14 (touch the bare pin to toggle modes)

## Setup

1. Install [PlatformIO](https://platformio.org/)

2. Copy the secrets template and fill in your credentials:
   ```
   cp src/secrets.h.example src/secrets.h
   ```

3. Edit `src/secrets.h`:
   ```c
   #define WIFI_SSID "your-ssid"
   #define WIFI_PASS "your-password"
   #define MESSAGES_URL "https://example.com/messages.json"
   #define FINNHUB_API_KEY "your-finnhub-key"
   const char* stockTickers[] = {"AAPL", "GOOGL", "MSFT", "AMZN"};
   ```

   Get a free Finnhub API key at https://finnhub.io/register

4. Build and upload:
   ```
   pio run -t upload
   ```

5. Monitor serial output:
   ```
   pio device monitor
   ```

## Messages URL Format

The messages endpoint should return a JSON array of strings:

```json
["Did you drink water?", "Take a break!", "Stand up and stretch"]
```

Limits: max 2KB response, max 256 chars per string, max 20 strings.

## Configuration

In `src/main.cpp`, comment/uncomment fetch calls in `setup()` to control what displays:

```c
fetchMessages();  // comment to disable remote messages
fetchStocks();    // comment to disable stock quotes
```

Other tunables in `src/main.cpp`:

| Define | Default | Description |
|--------|---------|-------------|
| `SCROLL_SPEED` | 50 | Scroll speed in ms per frame (lower = faster) |
| `FETCH_INTERVAL_MS` | 5 min | How often to refresh data |
| `MAX_DEVICES` | 4 | Number of 8x8 LED modules |
| `TOUCH_THRESHOLD` | 30000 | Capacitive touch sensitivity |
