#pragma once

// Default stock symbols — used to seed NVS on first boot.
// After that, update them via BLE: uv run tools/led.py tickers AAPL MSFT ...
const char *stockTickers[]  = {"AAPL", "GOOGL", "MSFT", "AMZN"};
const int   stockTickerCount = sizeof(stockTickers) / sizeof(stockTickers[0]);

// Fallback messages shown until you send your own via BLE:
//   uv run tools/led.py messages "msg1" "msg2" ...
const char *fallbackMessages[] = {
    "Did you drink water?",
    "Take a break!",
    "Stand up and stretch",
    "How are you doing?",
};
const int fallbackCount = sizeof(fallbackMessages) / sizeof(fallbackMessages[0]);
