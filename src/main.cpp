#include <Arduino.h>
#include <MD_Parola.h>
#include <MD_MAX72xx.h>
#include <SPI.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <Preferences.h>
#include <time.h>
#include <NimBLEDevice.h>
#if __has_include("secrets.h")
#include "secrets.h"
#else
#error "Copy src/secrets.h.example to src/secrets.h and fill in your credentials"
#endif
#include "config.h"

// --- Hardware & Display Config ---

#define HARDWARE_TYPE   MD_MAX72XX::FC16_HW
#define MAX_DEVICES     4
#define DIN_PIN         11
#define CLK_PIN         12
#define CS_PIN          10
#define TOUCH_PIN       14
#define TOUCH_THRESHOLD 30000
#define SCROLL_SPEED    50

// --- Fetch Limits ---

#define MAX_RESPONSE_BYTES 2048
#define MAX_STRING_LEN 256
#define MAX_MESSAGES 20
#define MAX_STOCKS 10
#define FETCH_INTERVAL_MS (5 * 60 * 1000)

// --- Display ---

MD_Parola display = MD_Parola(HARDWARE_TYPE, CS_PIN, MAX_DEVICES);

void initDisplay()
{
  SPI.begin(CLK_PIN, -1, DIN_PIN, CS_PIN);
  display.begin();
  display.setIntensity(2);
  display.displayClear();
}

void scrollText(const char *msg)
{
  display.displayScroll(msg, PA_LEFT, PA_SCROLL_LEFT, SCROLL_SPEED);
}

Preferences prefs;

// --- Messages ---

char messageStore[MAX_MESSAGES][MAX_STRING_LEN + 1];
int messageCount = 0;
int currentMsg = 0;

int getTotalMessages()
{
  return messageCount > 0 ? messageCount : fallbackCount;
}

const char *getMessage(int idx)
{
  if (messageCount > 0)
    return messageStore[idx % messageCount];
  return fallbackMessages[idx % fallbackCount];
}

void saveMessagesToNVS()
{
  prefs.begin("msgs", false);
  prefs.putInt("count", messageCount);
  for (int i = 0; i < messageCount; i++)
  {
    char key[8];
    snprintf(key, sizeof(key), "m%d", i);
    prefs.putString(key, messageStore[i]);
  }
  prefs.end();
  Serial.printf("Saved %d messages to NVS\n", messageCount);
}

void loadMessagesFromNVS()
{
  prefs.begin("msgs", true);
  int count = prefs.getInt("count", 0);
  if (count > 0 && count <= MAX_MESSAGES)
  {
    for (int i = 0; i < count; i++)
    {
      char key[8];
      snprintf(key, sizeof(key), "m%d", i);
      prefs.getString(key, messageStore[i], MAX_STRING_LEN);
    }
    prefs.end();
    messageCount = count;
    Serial.printf("Loaded %d messages from NVS\n", count);
  }
  else
  {
    prefs.end();
    Serial.println("No messages in NVS, using fallbacks");
  }
}

// --- Stocks ---

#define MAX_TICKER_LEN 16

char nvsTickers[MAX_STOCKS][MAX_TICKER_LEN];
int nvsTickerCount = 0;

char stockDisplay[MAX_STOCKS][MAX_STRING_LEN + 1];
int stockCount = 0;
int currentStock = 0;

void saveTickersToNVS()
{
  prefs.begin("tickers", false);
  prefs.putInt("count", nvsTickerCount);
  for (int i = 0; i < nvsTickerCount; i++)
  {
    char key[8];
    snprintf(key, sizeof(key), "t%d", i);
    prefs.putString(key, nvsTickers[i]);
  }
  prefs.end();
  Serial.printf("Saved %d tickers to NVS\n", nvsTickerCount);
}

void loadTickersFromNVS()
{
  prefs.begin("tickers", true);
  int count = prefs.getInt("count", 0);
  if (count > 0 && count <= MAX_STOCKS)
  {
    for (int i = 0; i < count; i++)
    {
      char key[8];
      snprintf(key, sizeof(key), "t%d", i);
      prefs.getString(key, nvsTickers[i], MAX_TICKER_LEN);
    }
    prefs.end();
    nvsTickerCount = count;
    Serial.printf("Loaded %d tickers from NVS\n", count);
  }
  else
  {
    prefs.end();
    // First boot: seed from secrets.h defaults
    for (int i = 0; i < stockTickerCount && i < MAX_STOCKS; i++)
    {
      strncpy(nvsTickers[i], stockTickers[i], MAX_TICKER_LEN - 1);
      nvsTickers[i][MAX_TICKER_LEN - 1] = '\0';
    }
    nvsTickerCount = stockTickerCount;
    saveTickersToNVS();
    Serial.printf("Seeded %d tickers from defaults\n", nvsTickerCount);
  }
}

// --- BLE ---

#define BLE_DEVICE_NAME       "LED-Ticker"
#define BLE_SERVICE_UUID      "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define BLE_TICKER_CHAR_UUID  "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define BLE_MODE_CHAR_UUID    "beb5483e-36e1-4688-b7f5-ea07361b26a9"
#define BLE_MSGS_CHAR_UUID    "beb5483e-36e1-4688-b7f5-ea07361b26aa"
#define BLE_CMD_CHAR_UUID     "beb5483e-36e1-4688-b7f5-ea07361b26ab"
#define BLE_TICKER_BUF_LEN    (MAX_STOCKS * (MAX_TICKER_LEN + 1))
#define BLE_MSGS_BUF_LEN      512

volatile bool tickerUpdatePending = false;
volatile bool modeUpdatePending   = false;
volatile bool msgsUpdatePending   = false;
volatile bool cmdPending          = false;

char pendingTickerStr[BLE_TICKER_BUF_LEN];
char pendingModeStr[16];
char pendingMsgsStr[BLE_MSGS_BUF_LEN];
char pendingCmd[16];

// Minimum ms between writes that trigger network activity
#define BLE_FETCH_COOLDOWN_MS 10000
volatile unsigned long lastBLEFetchMs = 0;

class TickerCallbacks : public NimBLECharacteristicCallbacks
{
  void onWrite(NimBLECharacteristic *pChar) override
  {
    if (millis() - lastBLEFetchMs < BLE_FETCH_COOLDOWN_MS)
    {
      Serial.println("BLE tickers: cooldown, ignoring");
      return;
    }
    std::string val = pChar->getValue();
    if (val.length() > 0 && val.length() < BLE_TICKER_BUF_LEN)
    {
      memcpy(pendingTickerStr, val.c_str(), val.length());
      pendingTickerStr[val.length()] = '\0';
      tickerUpdatePending = true;
      lastBLEFetchMs = millis();
      Serial.printf("BLE tickers: \"%s\"\n", pendingTickerStr);
    }
  }
};

class ModeCallbacks : public NimBLECharacteristicCallbacks
{
  void onWrite(NimBLECharacteristic *pChar) override
  {
    std::string val = pChar->getValue();
    if (val.length() > 0 && val.length() < sizeof(pendingModeStr))
    {
      memcpy(pendingModeStr, val.c_str(), val.length());
      pendingModeStr[val.length()] = '\0';
      modeUpdatePending = true;
      Serial.printf("BLE mode: \"%s\"\n", pendingModeStr);
    }
  }
};

class MsgsCallbacks : public NimBLECharacteristicCallbacks
{
  void onWrite(NimBLECharacteristic *pChar) override
  {
    std::string val = pChar->getValue();
    if (val.length() > 0 && val.length() < BLE_MSGS_BUF_LEN)
    {
      memcpy(pendingMsgsStr, val.c_str(), val.length());
      pendingMsgsStr[val.length()] = '\0';
      msgsUpdatePending = true;
      Serial.printf("BLE messages: %d bytes\n", val.length());
    }
  }
};

class CmdCallbacks : public NimBLECharacteristicCallbacks
{
  void onWrite(NimBLECharacteristic *pChar) override
  {
    std::string val = pChar->getValue();
    if (val.length() == 0 || val.length() >= sizeof(pendingCmd))
      return;

    // reload and reset trigger network activity — apply cooldown
    bool fetchCmd = (val == "reload" || val == "reset");
    if (fetchCmd && millis() - lastBLEFetchMs < BLE_FETCH_COOLDOWN_MS)
    {
      Serial.println("BLE cmd: cooldown, ignoring");
      return;
    }

    memcpy(pendingCmd, val.c_str(), val.length());
    pendingCmd[val.length()] = '\0';
    cmdPending = true;
    if (fetchCmd) lastBLEFetchMs = millis();
    Serial.printf("BLE cmd: \"%s\"\n", pendingCmd);
  }
};

void initBLE()
{
  NimBLEDevice::init(BLE_DEVICE_NAME);
  NimBLEDevice::setMTU(512);
  NimBLEServer *pServer = NimBLEDevice::createServer();
  NimBLEService *pService = pServer->createService(BLE_SERVICE_UUID);

  pService->createCharacteristic(BLE_TICKER_CHAR_UUID, NIMBLE_PROPERTY::WRITE)
    ->setCallbacks(new TickerCallbacks());
  pService->createCharacteristic(BLE_MODE_CHAR_UUID, NIMBLE_PROPERTY::WRITE)
    ->setCallbacks(new ModeCallbacks());
  pService->createCharacteristic(BLE_MSGS_CHAR_UUID, NIMBLE_PROPERTY::WRITE)
    ->setCallbacks(new MsgsCallbacks());
  pService->createCharacteristic(BLE_CMD_CHAR_UUID, NIMBLE_PROPERTY::WRITE)
    ->setCallbacks(new CmdCallbacks());

  pService->start();
  NimBLEAdvertising *pAdv = NimBLEDevice::getAdvertising();
  pAdv->addServiceUUID(BLE_SERVICE_UUID);
  pAdv->start();
  Serial.println("BLE advertising as " BLE_DEVICE_NAME);
}

void saveStocksToCache()
{
  prefs.begin("stocks", false);
  prefs.putInt("count", stockCount);
  for (int i = 0; i < stockCount; i++)
  {
    char key[8];
    snprintf(key, sizeof(key), "s%d", i);
    prefs.putString(key, stockDisplay[i]);
  }
  prefs.end();
  Serial.println("Stocks cached to NVS");
}

void loadStocksFromCache()
{
  prefs.begin("stocks", true);
  int count = prefs.getInt("count", 0);
  if (count <= 0 || count > MAX_STOCKS)
  {
    prefs.end();
    return;
  }

  for (int i = 0; i < count; i++)
  {
    char key[8];
    snprintf(key, sizeof(key), "s%d", i);
    prefs.getString(key, stockDisplay[i], MAX_STRING_LEN);
  }
  prefs.end();

  stockCount = count;
  currentStock = 0;
  Serial.printf("Loaded %d stocks from cache\n", stockCount);
}

// --- Time / Market Hours ---

bool timeReady = false;

void initTime()
{
  configTzTime("EST5EDT,M3.2.0,M11.1.0", "pool.ntp.org");

  Serial.print("Syncing NTP");
  for (int i = 0; i < 20; i++)
  {
    struct tm t;
    if (getLocalTime(&t, 100))
    {
      timeReady = true;
      Serial.printf("\nTime: %04d-%02d-%02d %02d:%02d ET\n",
                    t.tm_year + 1900, t.tm_mon + 1, t.tm_mday, t.tm_hour, t.tm_min);
      return;
    }
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nNTP sync failed, will fetch stocks anyway");
}

bool isMarketOpen()
{
  if (!timeReady)
    return true;

  struct tm t;
  if (!getLocalTime(&t, 100))
    return true;

  if (t.tm_wday == 0 || t.tm_wday == 6)
    return false;

  const int MARKET_OPEN  = 9 * 60 + 30;
  const int MARKET_CLOSE = 16 * 60;
  int minutes = t.tm_hour * 60 + t.tm_min;
  return minutes >= MARKET_OPEN && minutes < MARKET_CLOSE;
}

void fetchStocks(bool force = false)
{
  if (WiFi.status() != WL_CONNECTED)
    return;

  if (!force && !isMarketOpen())
  {
    if (stockCount == 0)
      loadStocksFromCache();
    if (stockCount > 0)
      return;
  }

  int count = 0;
  HTTPClient http;
  http.setConnectTimeout(5000);
  http.setTimeout(5000);

  for (int i = 0; i < nvsTickerCount && count < MAX_STOCKS; i++)
  {
    char url[256];
    snprintf(url, sizeof(url),
             "https://finnhub.io/api/v1/quote?symbol=%s&token=%s",
             nvsTickers[i], FINNHUB_API_KEY);

    Serial.printf("Fetching stock: %s\n", nvsTickers[i]);
    http.begin(url);

    int code = http.GET();
    if (code != 200)
    {
      Serial.printf("Stock HTTP error: %d for %s\n", code, nvsTickers[i]);
      http.end();
      continue;
    }

    String body = http.getString();
    http.end();

    if (body.length() > MAX_RESPONSE_BYTES)
      continue;

    JsonDocument doc;
    if (deserializeJson(doc, body))
      continue;

    float current = doc["c"];
    float change = doc["dp"];

    if (current == 0)
      continue;

    const char* sign = change >= 0 ? "(+)" : "(-)";
    snprintf(stockDisplay[count], MAX_STRING_LEN,
             "%s $%.2f %s", nvsTickers[i], current, sign);

    Serial.printf("Stock: %s\n", stockDisplay[count]);
    count++;
  }

  if (count > 0)
  {
    stockCount = count;
    currentStock = 0;
    Serial.printf("Loaded %d stock quotes\n", stockCount);
    saveStocksToCache();
  }
}

// --- Touch Button ---

bool showStocks = true;
unsigned long lastTouchTime = 0;
unsigned long lastTouchPoll = 0;

void checkTouch()
{
  if (millis() - lastTouchPoll < 50) return;
  lastTouchPoll = millis();

  if (touchRead(TOUCH_PIN) > TOUCH_THRESHOLD && millis() - lastTouchTime > 2000)
  {
    showStocks = !showStocks;
    lastTouchTime = millis();
    Serial.printf("Touch: mode -> %s\n", showStocks ? "STOCKS" : "MESSAGES");
  }
}

// --- Display Rotation ---

void showNextMsg()
{
  int total = getTotalMessages();
  scrollText(getMessage(currentMsg));
  currentMsg = (currentMsg + 1) % total;
}

void showNextStock()
{
  scrollText(stockDisplay[currentStock]);
  currentStock = (currentStock + 1) % stockCount;
}

void showNext()
{
  if (showStocks && stockCount > 0)
    showNextStock();
  else
    showNextMsg();
}

// --- WiFi ---

void connectWifi()
{
  if (WiFi.status() == WL_CONNECTED)
    return;

  Serial.printf("Connecting to %s", WIFI_SSID);
  WiFi.begin(WIFI_SSID, WIFI_PASS);

  for (int attempts = 0; WiFi.status() != WL_CONNECTED && attempts < 20; attempts++)
  {
    delay(500);
    Serial.print(".");
  }

  if (WiFi.status() == WL_CONNECTED)
  {
    IPAddress ip = WiFi.localIP();
    Serial.printf("\nConnected, IP: %u.%u.%u.%u\n", ip[0], ip[1], ip[2], ip[3]);
  }
  else
  {
    Serial.println("\nWiFi failed, using fallback messages");
  }
}

// --- BLE Apply ---

void applyPendingCmd()
{
  cmdPending = false;

  if (strcmp(pendingCmd, "reload") == 0)
  {
    Serial.println("BLE cmd: reloading stocks");
    stockCount = 0;
    fetchStocks(true);
  }
  else if (strcmp(pendingCmd, "reset") == 0)
  {
    Serial.println("BLE cmd: resetting to defaults");

    prefs.begin("tickers", false); prefs.clear(); prefs.end();
    prefs.begin("msgs",    false); prefs.clear(); prefs.end();
    prefs.begin("stocks",  false); prefs.clear(); prefs.end();

    loadTickersFromNVS();  // re-seeds from config.h since NVS is now empty

    messageCount = 0;
    currentMsg   = 0;
    stockCount   = 0;
    fetchStocks(true);
  }
  else
  {
    Serial.printf("BLE cmd: unknown command \"%s\"\n", pendingCmd);
  }
}

void applyPendingMode()
{
  modeUpdatePending = false;
  if (strcmp(pendingModeStr, "stocks") == 0)
  {
    showStocks = true;
    Serial.println("BLE: mode -> STOCKS");
  }
  else if (strcmp(pendingModeStr, "messages") == 0)
  {
    showStocks = false;
    Serial.println("BLE: mode -> MESSAGES");
  }
  else
  {
    Serial.printf("BLE: unknown mode \"%s\", ignoring\n", pendingModeStr);
  }
}

void applyPendingMessages()
{
  char buf[BLE_MSGS_BUF_LEN];
  strncpy(buf, pendingMsgsStr, sizeof(buf) - 1);
  buf[sizeof(buf) - 1] = '\0';
  msgsUpdatePending = false;

  char tmp[MAX_MESSAGES][MAX_STRING_LEN + 1];
  int count = 0;

  char *token = strtok(buf, "|");
  while (token && count < MAX_MESSAGES)
  {
    while (*token == ' ') token++;
    int len = strlen(token);
    while (len > 0 && token[len - 1] == ' ') len--;
    token[len] = '\0';

    if (len > 0)
    {
      strncpy(tmp[count], token, MAX_STRING_LEN);
      tmp[count][MAX_STRING_LEN] = '\0';
      count++;
    }
    token = strtok(nullptr, "|");
  }

  if (count == 0)
  {
    Serial.println("BLE: no valid messages, ignoring");
    return;
  }

  for (int i = 0; i < count; i++)
    strncpy(messageStore[i], tmp[i], MAX_STRING_LEN + 1);
  messageCount = count;
  currentMsg = 0;
  saveMessagesToNVS();
  Serial.printf("BLE: applied %d messages\n", count);
}

void applyPendingTickers()
{
  char buf[BLE_TICKER_BUF_LEN];
  strncpy(buf, pendingTickerStr, sizeof(buf) - 1);
  buf[sizeof(buf) - 1] = '\0';
  tickerUpdatePending = false;

  char tmp[MAX_STOCKS][MAX_TICKER_LEN];
  int count = 0;

  char *token = strtok(buf, ",");
  while (token && count < MAX_STOCKS)
  {
    while (*token == ' ') token++;
    int len = strlen(token);
    while (len > 0 && token[len - 1] == ' ') len--;
    token[len] = '\0';

    if (len > 0 && len < MAX_TICKER_LEN)
    {
      strncpy(tmp[count], token, MAX_TICKER_LEN - 1);
      tmp[count][MAX_TICKER_LEN - 1] = '\0';
      for (int j = 0; tmp[count][j]; j++)
        tmp[count][j] = toupper((unsigned char)tmp[count][j]);
      count++;
    }
    token = strtok(nullptr, ",");
  }

  if (count == 0)
  {
    Serial.println("BLE: no valid tickers, ignoring");
    return;
  }

  for (int i = 0; i < count; i++)
    strncpy(nvsTickers[i], tmp[i], MAX_TICKER_LEN);
  nvsTickerCount = count;
  saveTickersToNVS();

  stockCount = 0;
  fetchStocks(true);
}

// --- Main ---

unsigned long lastFetch = 0;

void setup()
{
  Serial.begin(115200);
  delay(500);

  initDisplay();
  loadMessagesFromNVS();
  loadTickersFromNVS();
  loadStocksFromCache();
  showNext();

  connectWifi();
  initTime();
  initBLE();
  fetchStocks();
  showNext();
  lastFetch = millis();
}

void loop()
{
  if (cmdPending)           applyPendingCmd();
  if (modeUpdatePending)    applyPendingMode();
  if (msgsUpdatePending)    applyPendingMessages();
  if (tickerUpdatePending)  applyPendingTickers();

  checkTouch();

  if (display.displayAnimate())
  {
    display.displayReset();
    showNext();
  }

  if (millis() - lastFetch > FETCH_INTERVAL_MS)
  {
    lastFetch = millis();
    if (WiFi.status() != WL_CONNECTED) return;
    fetchStocks();
  }
}
