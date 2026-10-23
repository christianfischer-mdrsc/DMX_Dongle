#include "usb_mirror.h"

#include <Arduino.h>
#include <string.h>

#include "board_config.h"

#ifndef USB_MIRROR_ENABLED
#define USB_MIRROR_ENABLED 1
#endif
#ifndef USB_MIRROR_MAX_HZ
#define USB_MIRROR_MAX_HZ 30
#endif
#ifndef USB_MIRROR_MAX_PORTS
#define USB_MIRROR_MAX_PORTS 2
#endif

#if USB_MIRROR_ENABLED

namespace usbmirror {
namespace {

constexpr uint8_t SYNC0 = 0xA5;
constexpr uint8_t SYNC1 = 0x5A;
constexpr uint8_t TYPE_DMX = 0x01;
constexpr uint8_t TYPE_HELLO = 0x02;
constexpr uint8_t TYPE_STATUS = 0x03;

constexpr uint32_t KEEPALIVE_MS = 1000;  // unveraenderte Daten trotzdem 1x/s senden
constexpr uint32_t STATUS_MS = 1000;
constexpr uint32_t HELLO_MS = 5000;
constexpr size_t MAX_PAYLOAD = 5 + 512;

struct PortState {
  uint8_t live[512];
  uint16_t liveLen = 0;
  uint8_t sent[512];
  uint16_t sentLen = 0;
  uint16_t portAddress = 0;
  uint32_t frames = 0;
  uint32_t framesAtStatus = 0;
  uint32_t lastSentMs = 0;
  bool used = false;
};

PortState g_ports[USB_MIRROR_MAX_PORTS];
portMUX_TYPE g_mux = portMUX_INITIALIZER_UNLOCKED;
char g_hello[96] = "DMX-Dongle";
uint8_t g_seq = 0;
uint8_t g_tx[6 + MAX_PAYLOAD + 2];
bool g_started = false;

uint16_t crc16(uint16_t crc, const uint8_t* d, size_t n) {
  while (n--) {
    crc ^= static_cast<uint16_t>(*d++) << 8;
    for (int i = 0; i < 8; ++i) {
      crc = (crc & 0x8000) ? static_cast<uint16_t>((crc << 1) ^ 0x1021)
                           : static_cast<uint16_t>(crc << 1);
    }
  }
  return crc;
}

// Nur aus dem Spiegel-Task aufrufen (g_tx ist nicht geschuetzt).
void sendPacket(uint8_t type, const uint8_t* payload, uint16_t len) {
  if (len > MAX_PAYLOAD) return;
  g_tx[0] = SYNC0;
  g_tx[1] = SYNC1;
  g_tx[2] = type;
  g_tx[3] = g_seq++;
  g_tx[4] = len & 0xFF;
  g_tx[5] = len >> 8;
  if (len) memcpy(g_tx + 6, payload, len);
  const uint16_t c = crc16(0xFFFF, g_tx + 2, 4 + len);
  g_tx[6 + len] = c & 0xFF;
  g_tx[7 + len] = c >> 8;
  Serial.write(g_tx, 8 + len);  // ein write() = Paket wird nicht von Logs zerteilt
}

void sendHello() {
  char text[sizeof(g_hello)];
  portENTER_CRITICAL(&g_mux);
  memcpy(text, g_hello, sizeof(text));
  portEXIT_CRITICAL(&g_mux);
  sendPacket(TYPE_HELLO, reinterpret_cast<const uint8_t*>(text),
             static_cast<uint16_t>(strnlen(text, sizeof(text))));
}

void sendStatus(uint32_t elapsedMs) {
  uint8_t payload[1 + USB_MIRROR_MAX_PORTS * 5];
  uint8_t count = 0;
  for (int p = 0; p < USB_MIRROR_MAX_PORTS; ++p) {
    PortState& s = g_ports[p];
    portENTER_CRITICAL(&g_mux);
    const bool used = s.used;
    const uint16_t pa = s.portAddress;
    const uint32_t delta = s.frames - s.framesAtStatus;
    s.framesAtStatus = s.frames;
    portEXIT_CRITICAL(&g_mux);
    if (!used) continue;
    const uint16_t fps =
        elapsedMs ? static_cast<uint16_t>((delta * 1000UL + elapsedMs / 2) / elapsedMs) : 0;
    uint8_t* o = payload + 1 + count * 5;
    o[0] = static_cast<uint8_t>(p);
    o[1] = pa & 0xFF;
    o[2] = pa >> 8;
    o[3] = fps & 0xFF;
    o[4] = fps >> 8;
    ++count;
  }
  payload[0] = count;
  sendPacket(TYPE_STATUS, payload, 1 + count * 5);
}

void mirrorTask(void*) {
  static uint8_t snap[512];
  static uint8_t payload[MAX_PAYLOAD];
  const TickType_t period = pdMS_TO_TICKS(1000 / USB_MIRROR_MAX_HZ);
  TickType_t wake = xTaskGetTickCount();
  uint32_t lastStatus = millis();
  uint32_t lastHello = millis();
  sendHello();

  for (;;) {
    vTaskDelayUntil(&wake, period);
    const uint32_t now = millis();

    for (int p = 0; p < USB_MIRROR_MAX_PORTS; ++p) {
      PortState& s = g_ports[p];
      portENTER_CRITICAL(&g_mux);
      const bool used = s.used;
      const uint16_t len = s.liveLen;
      const uint16_t pa = s.portAddress;
      if (used) memcpy(snap, s.live, len);
      portEXIT_CRITICAL(&g_mux);
      if (!used) continue;

      const bool changed = len != s.sentLen || memcmp(snap, s.sent, len) != 0;
      if (!changed && now - s.lastSentMs < KEEPALIVE_MS) continue;

      payload[0] = static_cast<uint8_t>(p);
      payload[1] = pa & 0xFF;
      payload[2] = pa >> 8;
      payload[3] = len & 0xFF;
      payload[4] = len >> 8;
      memcpy(payload + 5, snap, len);
      sendPacket(TYPE_DMX, payload, 5 + len);

      memcpy(s.sent, snap, len);
      s.sentLen = len;
      s.lastSentMs = now;
    }

    if (now - lastStatus >= STATUS_MS) {
      sendStatus(now - lastStatus);
      lastStatus = now;
    }
    if (now - lastHello >= HELLO_MS) {
      sendHello();
      lastHello = now;
    }
  }
}

}  // namespace

void begin(const char* helloText) {
  if (helloText) setHello(helloText);
  if (g_started) return;
  g_started = true;
  xTaskCreatePinnedToCore(mirrorTask, "usbmirror", 4096, nullptr, 1, nullptr, 0);
}

void setHello(const char* helloText) {
  if (!helloText) return;
  portENTER_CRITICAL(&g_mux);
  strncpy(g_hello, helloText, sizeof(g_hello) - 1);
  g_hello[sizeof(g_hello) - 1] = '\0';
  portEXIT_CRITICAL(&g_mux);
}

void setPortAddress(uint8_t port, uint16_t portAddress) {
  if (port >= USB_MIRROR_MAX_PORTS) return;
  portENTER_CRITICAL(&g_mux);
  g_ports[port].portAddress = portAddress & 0x7FFF;
  portEXIT_CRITICAL(&g_mux);
}

void onFrame(uint8_t port, const uint8_t* data, size_t len) {
  if (port >= USB_MIRROR_MAX_PORTS || !data) return;
  if (len > 512) len = 512;
  PortState& s = g_ports[port];
  portENTER_CRITICAL(&g_mux);
  memcpy(s.live, data, len);
  s.liveLen = static_cast<uint16_t>(len);
  s.used = true;
  s.frames++;
  portEXIT_CRITICAL(&g_mux);
}

}  // namespace usbmirror

#else  // USB_MIRROR_ENABLED == 0: alles leer, kein Overhead

namespace usbmirror {
void begin(const char*) {}
void setHello(const char*) {}
void setPortAddress(uint8_t, uint16_t) {}
void onFrame(uint8_t, const uint8_t*, size_t) {}
}  // namespace usbmirror

#endif
