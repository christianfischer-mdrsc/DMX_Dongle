#include "status_led.h"

#include <Arduino.h>

namespace statusled {
namespace {

constexpr uint32_t kTickMs = 10;
constexpr uint32_t kActivityOffMs = 30;

int g_pin = -1;
volatile Mode g_mode = Mode::Boot;
volatile uint32_t g_activityAt = 0;
volatile uint32_t g_errorAt = 0;

// Blitz-Muster in einer Periode: an für `on` ms ab jedem Startwert in `starts`
bool flashes(uint32_t t, uint32_t period, const uint16_t* starts, int n, uint16_t on) {
  const uint32_t p = t % period;
  for (int i = 0; i < n; ++i)
    if (p >= starts[i] && p < starts[i] + on) return true;
  return false;
}

bool level(uint32_t now) {
  if (g_errorAt && now - g_errorAt < 3000) {
    return (now - g_errorAt) % 1000 < 600;  // 3 lange Blinker
  }
  static const uint16_t kSingle[] = {0};
  static const uint16_t kDouble[] = {0, 200};
  switch (g_mode) {
    case Mode::Boot:           return now % 100 < 50;
    case Mode::WifiConnecting: return now % 500 < 250;
    case Mode::ApWaiting:      return flashes(now, 2000, kSingle, 1, 60);
    case Mode::Ready:          return flashes(now, 2000, kDouble, 2, 60);
    case Mode::Master:         return now - g_activityAt >= kActivityOffMs;
    case Mode::Ota:            return now % 50 < 25;
    case Mode::Button:         return true;
  }
  return false;
}

void task(void*) {
  for (;;) {
    digitalWrite(g_pin, level(millis()) ? HIGH : LOW);
    vTaskDelay(pdMS_TO_TICKS(kTickMs));
  }
}

}  // namespace

void begin(int pin) {
  g_pin = pin;
  pinMode(pin, OUTPUT);
  digitalWrite(pin, LOW);
  // Core 0, niedrige Priorität: stört weder WLAN noch die DMX-Tasks auf Core 1
  xTaskCreatePinnedToCore(task, "statusled", 1536, nullptr, 1, nullptr, 0);
}

void setMode(Mode m) { g_mode = m; }
Mode mode() { return g_mode; }
void activity() { g_activityAt = millis(); }
void error() { g_errorAt = millis() | 1; }

}  // namespace statusled
