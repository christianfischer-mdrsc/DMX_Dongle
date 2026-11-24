// merger.h – mehrere Steuerungen auf einem Universe ("letzte Änderung gewinnt").
//
// Jede Steuerung (Handy, PC …) schickt wie üblich komplette Frames. Für jeden
// Kanal zählt nur, wenn ein Sender seinen Wert ÄNDERT – dann gehört ihm der
// Kanal, bis ein anderer ihn ändert. Unveränderte Kanäle eines Senders stören
// also nicht.
//
// Der Node schickt den gemischten Stand an alle Sender zurück ("Echo"), damit
// jede Steuerung live sieht, was die andere tut. Übernimmt eine Steuerung diesen
// Stand und sendet ihn verzögert weiter, darf das nicht als neue Änderung gelten:
// Deshalb merkt sich der Merger je Kanal die letzten Werte mit Besitzer und
// ignoriert Änderungen auf einen Wert, den kurz zuvor ein ANDERER Sender gesetzt hat.
#pragma once
#include <cstddef>
#include <cstdint>

#include "hal.h"

namespace dmx {

constexpr uint8_t kMaxSources = 4;
constexpr uint8_t kMergeHistory = 8;
constexpr uint32_t kSourceTimeoutMs = 4000;  // Sender gilt danach als weg
constexpr uint32_t kEchoWindowMs = 1500;     // so lange gilt ein Wert als "Echo"

class Merger {
 public:
  static constexpr uint8_t kNone = 0xFF;

  // Frame eines Senders verarbeiten. true = gemischter Stand hat sich geändert.
  bool apply(uint32_t sourceId, uint16_t sourcePort, const uint8_t* data,
             uint16_t length, uint32_t nowMs);

  const uint8_t* data() const { return merged_; }
  uint8_t ownerOf(uint16_t channel) const { return owner_[channel]; }

  // Aktive Sender (für das Echo). Liefert die Anzahl, füllt ids/ports.
  uint8_t activeSources(uint32_t nowMs, uint32_t* ids, uint16_t* ports) const;
  int8_t slotOf(uint32_t sourceId) const;

  // Echo fällig? (Änderung seit dem letzten Echo, max. alle minIntervalMs,
  // sonst spätestens alle keepAliveMs). Setzt den Zeitpunkt bei true.
  bool echoDue(uint32_t nowMs, uint32_t minIntervalMs = 33,
               uint32_t keepAliveMs = 300);

 private:
  struct Source {
    uint32_t id = 0;
    uint16_t port = 0;
    uint32_t lastSeenMs = 0;
    bool used = false;
    uint8_t last[kUniverseSize] = {};
  };

  bool alive(const Source& s, uint32_t now) const {
    return s.used && now - s.lastSeenMs < kSourceTimeoutMs;
  }
  bool isEcho(uint16_t ch, uint8_t value, uint8_t slot, uint32_t now) const;
  void set(uint16_t ch, uint8_t value, uint8_t slot, uint32_t now);

  Source sources_[kMaxSources];
  uint8_t merged_[kUniverseSize] = {};
  uint8_t owner_[kUniverseSize];
  // Verlauf je Kanal: Wert, Besitzer, Zeit (ms / 8, läuft über – nur Differenzen)
  uint8_t histValue_[kUniverseSize][kMergeHistory] = {};
  uint8_t histOwner_[kUniverseSize][kMergeHistory];
  uint16_t histTime_[kUniverseSize][kMergeHistory] = {};
  uint8_t histPos_[kUniverseSize] = {};
  bool dirty_ = false;
  uint32_t lastEchoMs_ = 0;
  bool echoedOnce_ = false;

 public:
  Merger();
};

}  // namespace dmx
