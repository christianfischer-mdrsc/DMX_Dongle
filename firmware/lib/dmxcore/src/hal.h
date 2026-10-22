// hal.h – Hardware-Abstraktion für den DMX-Kern.
//
// Der Kern (artnet.*, dmx_node.*) kennt nur diese Interfaces und ist damit
// frei von Arduino/ESP-IDF/STM32-HAL. Für eine neue Plattform (z.B. eigene
// STM32-Hardware) werden nur diese Klassen implementiert.
#pragma once
#include <cstddef>
#include <cstdint>

namespace dmx {

constexpr uint16_t kUniverseSize = 512;

// Ein physischer DMX-Ausgang (UART + RS485-Transceiver).
class IDmxOutput {
 public:
  virtual ~IDmxOutput() = default;
  // Übernimmt einen neuen Frame. Muss thread-/ISR-sicher sein, weil der
  // Ausgang typischerweise in einem eigenen Task/DMA-Kontext sendet.
  virtual void write(const uint8_t* data, uint16_t length) = 0;
};

// Monotone Zeitbasis in Millisekunden.
class IClock {
 public:
  virtual ~IClock() = default;
  virtual uint32_t millis() const = 0;
};

}  // namespace dmx
