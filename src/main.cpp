#include <Arduino.h>
#include <MD_Parola.h>
#include <MD_MAX72xx.h>
#include <SPI.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <Preferences.h>
#include <time.h>
#if __has_include("secrets.h")
#include "secrets.h"
#else
#error "Copy src/secrets.h.example to src/secrets.h and fill in your credentials"
#endif

// --- Hardware Config ---

#define HARDWARE_TYPE MD_MAX72XX::FC16_HW
#define MAX_DEVICES 4
#define DIN_PIN 11
#define CLK_PIN 12
#define CS_PIN 10
#define TOUCH_PIN 14
#define TOUCH_THRESHOLD 30000

// --- Display Settings ---

#define SCROLL_SPEED 50

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

// --- Messages ---

const char *fallbackMessages[] = {
    "Did you drink water?",
    "Take a break!",
    "Stand up and stretch",
    "How are you doing?",
};
const int fallbackCount = sizeof(fallbackMessages) / sizeof(fallbackMessages[0]);

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

// --- Stocks ---

char stockDisplay[MAX_STOCKS][MAX_STRING_LEN + 1];
int stockCount = 0;
int currentStock = 0;

Preferences prefs;

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

  const int MARKET_OPEN = 9 * 60 + 30;
  const int MARKET_CLOSE = 16 * 60;
  int minutes = t.tm_hour * 60 + t.tm_min;
  bool open = minutes >= MARKET_OPEN && minutes < MARKET_CLOSE;

  return open;
}

void fetchStocks()
{
  if (WiFi.status() != WL_CONNECTED)
    return;

  if (!isMarketOpen())
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

  for (int i = 0; i < stockTickerCount && count < MAX_STOCKS; i++)
  {
    char url[256];
    snprintf(url, sizeof(url),
             "https://finnhub.io/api/v1/quote?symbol=%s&token=%s",
             stockTickers[i], FINNHUB_API_KEY);

    Serial.printf("Fetching stock: %s\n", stockTickers[i]);
    http.begin(url);

    int code = http.GET();
    if (code != 200)
    {
      Serial.printf("Stock HTTP error: %d for %s\n", code, stockTickers[i]);
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
             "%s $%.2f %s", stockTickers[i], current, sign);

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

// --- Fetch Messages ---

bool parseMessages(const String &body)
{
  JsonDocument doc;
  DeserializationError err = deserializeJson(doc, body);
  if (err)
  {
    Serial.printf("JSON parse error: %s\n", err.c_str());
    return false;
  }

  if (!doc.is<JsonArray>())
  {
    Serial.println("Expected JSON array");
    return false;
  }

  int count = 0;
  for (JsonVariant v : doc.as<JsonArray>())
  {
    if (count >= MAX_MESSAGES)
      break;
    if (!v.is<const char *>())
      continue;

    const char *s = v.as<const char *>();
    if (strlen(s) == 0)
      continue;

    strncpy(messageStore[count], s, MAX_STRING_LEN);
    messageStore[count][MAX_STRING_LEN] = '\0';
    count++;
  }

  if (count == 0)
    return false;

  messageCount = count;
  currentMsg = 0;
  Serial.printf("Loaded %d messages\n", messageCount);
  return true;
}

void fetchMessages()
{
  if (WiFi.status() != WL_CONNECTED)
  {
    connectWifi();
    if (WiFi.status() != WL_CONNECTED)
      return;
  }

  HTTPClient http;
  http.setConnectTimeout(5000);
  http.setTimeout(5000);

  Serial.printf("Fetching %s\n", MESSAGES_URL);
  http.begin(MESSAGES_URL);

  int code = http.GET();
  if (code != 200)
  {
    Serial.printf("HTTP error: %d\n", code);
    http.end();
    return;
  }

  int len = http.getSize();
  if (len > 0 && len > MAX_RESPONSE_BYTES)
  {
    Serial.printf("Response too large (%d bytes), aborting\n", len);
    http.end();
    return;
  }

  String body = http.getString();
  http.end();

  if (body.length() > MAX_RESPONSE_BYTES)
  {
    Serial.println("Response exceeded max size, aborting parse");
    return;
  }

  Serial.printf("Received %u bytes\n", body.length());

  if (!parseMessages(body))
  {
    Serial.println("No valid messages, keeping previous set");
  }
}

// --- Main ---

unsigned long lastFetch = 0;

void setup()
{
  Serial.begin(115200);
  delay(500);

  initDisplay();
  loadStocksFromCache();
  showNext();

  connectWifi();
  initTime();
  // fetchMessages();
  fetchStocks();
  showNext();
  lastFetch = millis();
}

void loop()
{
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
    fetchMessages();
    fetchStocks();
  }
}
