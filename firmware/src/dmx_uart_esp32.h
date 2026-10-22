// dmx_uart_esp32.h – DMX512-Ausgang über ESP32-UART (ESP32-spezifisch).
#pragma once
#include <Arduino.h>
#include <driver/uart.h>

#include "hal.h"

class DmxUartEsp32 : public dmx::IDmxOutput {
 public:
  DmxUartEsp32(uart_port_t port, int txPin, int dePin);
  bool begin(const char* taskName);
  void write(const uint8_t* data, uint16_t length) override;
  uint32_t framesSent() const { return framesSent_; }

 private:
  static void taskEntry(void* arg);
  void run();

  uart_port_t port_;
  int txPin_;
  int dePin_;
  portMUX_TYPE mux_ = portMUX_INITIALIZER_UNLOCKED;
  uint8_t shared_[dmx::kUniverseSize + 1] = {0};  // [0] = Startcode
  uint8_t frame_[dmx::kUniverseSize + 1] = {0};
  volatile uint32_t framesSent_ = 0;
};
