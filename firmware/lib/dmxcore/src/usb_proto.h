// usb_proto.h – Paketformat auf der USB-Seriell-Verbindung (beide Richtungen).
//
//   A5 5A | Typ (1) | Seq (1) | Länge (2, LE) | Nutzdaten | CRC16 (2, LE)
//   CRC-16/CCITT-FALSE (Poly 0x1021, Start 0xFFFF) über Typ..Nutzdaten
//
// Dongle → Host
//   0x01 DMX      Port (1) | Port-Address (2) | Anzahl (2) | Kanaldaten   (USB-Spiegel)
//   0x02 HELLO    UTF-8-Text
//   0x03 STATUS   Anzahl Ports | je Port: Port, Port-Address (2), Frames/s (2)
//   0x21 CONFIG   JSON (Antwort auf 0x20)
//   0x23 RESULT   JSON {"ok":..,"error":..,"restart":..} (Antwort auf 0x22)
//   0x25 INFO     JSON (Antwort auf 0x24)
//   0x27 WIFILIST JSON {"networks":[{"ssid":..,"rssi":..,"secure":..}]} (Antwort auf 0x26)
// Host → Dongle
//   0x10 DMX      Port-Address (2) | Anzahl (2) | Kanaldaten – wie ArtDmx, nur über USB
//   0x20 GETCFG   –
//   0x22 SETCFG   JSON, nur die zu ändernden Felder
//   0x24 GETINFO  –
//   0x26 SCANWIFI –
//
// Alles, was nicht zu einem gültigen Paket gehört, ist Log-Text der Firmware.
#pragma once
#include <cstddef>
#include <cstdint>

namespace usbproto {

constexpr uint8_t kSync0 = 0xA5;
constexpr uint8_t kSync1 = 0x5A;
constexpr size_t kMaxPayload = 1536;
constexpr size_t kOverhead = 8;

enum Type : uint8_t {
  kDmx = 0x01,
  kHello = 0x02,
  kStatus = 0x03,
  kHostDmx = 0x10,
  kGetConfig = 0x20,
  kConfig = 0x21,
  kSetConfig = 0x22,
  kResult = 0x23,
  kGetInfo = 0x24,
  kInfo = 0x25,
  kScanWifi = 0x26,
  kWifiList = 0x27,
};

uint16_t crc16(const uint8_t* data, size_t len, uint16_t crc = 0xFFFF);

// Paket bauen. Liefert die Gesamtlänge oder 0, wenn cap nicht reicht.
size_t build(uint8_t type, uint8_t seq, const uint8_t* payload, uint16_t len, uint8_t* out,
             size_t cap);

// Byteweiser Empfänger. Ruft für jedes gültige Paket den Handler auf.
class Parser {
 public:
  using Handler = void (*)(void* ctx, uint8_t type, const uint8_t* payload, uint16_t len);
  Parser(Handler handler, void* ctx) : handler_(handler), ctx_(ctx) {}

  void feed(const uint8_t* data, size_t len);
  uint32_t packets() const { return packets_; }
  uint32_t crcErrors() const { return crcErrors_; }

 private:
  enum class State : uint8_t { Idle, Sync, Header, Payload, Crc };
  void step(uint8_t b);

  Handler handler_;
  void* ctx_;
  State state_ = State::Idle;
  uint8_t hdr_[4] = {};
  uint8_t hdrPos_ = 0;
  uint16_t len_ = 0, pos_ = 0;
  uint8_t crc_[2] = {};
  uint8_t crcPos_ = 0;
  uint8_t buf_[kMaxPayload];
  uint32_t packets_ = 0, crcErrors_ = 0;
};

}  // namespace usbproto
