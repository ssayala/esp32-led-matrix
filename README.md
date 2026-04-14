# LED Matrix Ticker

Scrolling message board and stock ticker using a Freenove ESP32-S3 and a DIYables 4-in-1 MAX7219 LED matrix.

## Features

- Scrolling text display on a 32x8 LED matrix
- Live stock quotes from Finnhub API
- Bluetooth (BLE) control — update stock symbols, messages, and display mode wirelessly
- Touch-to-toggle between stocks and messages (capacitive touch on GPIO 14)
- All settings persist across reboots (NVS flash storage)
- Hardcoded fallback messages until you send your own via BLE
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

3. Edit `src/secrets.h` with your credentials:
   ```c
   #define WIFI_SSID "your-ssid"
   #define WIFI_PASS "your-password"
   #define FINNHUB_API_KEY "your-finnhub-key"
   ```

   Get a free Finnhub API key at https://finnhub.io/register

4. Optionally edit `src/config.h` to set default stock symbols and fallback messages:
   ```c
   const char *stockTickers[] = {"AAPL", "GOOGL", "MSFT", "AMZN"};
   ```
   These are only used on first boot to seed NVS. After that, use the BLE tool.

5. Build and upload:
   ```
   pio run -t upload
   ```

6. Monitor serial output:
   ```
   pio device monitor
   ```

## BLE Control

The device advertises as `LED-Ticker`. Use the included script to control it from any machine with Bluetooth:

```bash
# Install uv if needed: https://docs.astral.sh/uv/getting-started/installation/

# Set stock symbols (fetches new quotes immediately)
uv run tools/led.py tickers AAPL TSLA NVDA SPY

# Set scrolling messages (persisted across reboots)
uv run tools/led.py messages "Take a break!" "Drink water!" "Stand up!"

# Switch display mode
uv run tools/led.py mode stocks
uv run tools/led.py mode messages

# Force an immediate stock quote refresh
uv run tools/led.py reload

# Clear all NVS data and revert to config.h defaults
uv run tools/led.py reset
```

The physical touch pin on GPIO 14 also toggles between stocks and messages.

### BLE Service UUIDs

For building a custom app (e.g. iOS with CoreBluetooth):

| | UUID |
|---|---|
| Service | `4fafc201-1fb5-459e-8fcc-c5c9c331914b` |
| Tickers (write) | `beb5483e-36e1-4688-b7f5-ea07361b26a8` |
| Mode (write) | `beb5483e-36e1-4688-b7f5-ea07361b26a9` |
| Messages (write) | `beb5483e-36e1-4688-b7f5-ea07361b26aa` |
| Command (write) | `beb5483e-36e1-4688-b7f5-ea07361b26ab` |

Payload formats:
- **Tickers:** comma-separated symbols — `AAPL,MSFT,GOOGL`
- **Mode:** `stocks` or `messages`
- **Messages:** pipe-separated strings — `Take a break!|Drink water!|Stand up!` (max 511 bytes)
- **Command:** `reload` (force stock refresh) or `reset` (clear NVS, revert to `config.h` defaults)

## Configuration

Tunables at the top of `src/main.cpp`:

| Define | Default | Description |
|--------|---------|-------------|
| `SCROLL_SPEED` | 50 | ms per frame (lower = faster) |
| `FETCH_INTERVAL_MS` | 5 min | Stock quote refresh interval |
| `MAX_DEVICES` | 4 | Number of 8x8 LED modules |
| `TOUCH_THRESHOLD` | 30000 | Capacitive touch sensitivity |
