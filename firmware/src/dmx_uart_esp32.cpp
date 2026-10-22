#include "dmx_uart_esp32.h"

// DMX512 Timing (ANSI E1.11):
//   Break        >= 92 µs  (wir: 176 µs, wie viele Pulte)
//   Mark After   >= 12 µs
//   Daten        250 kBaud, 8N2, Startcode 0x00 + bis zu 512 Slots
// Volle 512 Kanäle ⇒ ~22.7 ms pro Frame ⇒ ~43 Hz Refresh.
static constexpr uint32_t kBreakUs = 176;
static constexpr uint32_t kMabUs = 12;

DmxUartEsp32::DmxUartEsp32(uart_port_t port, int txPin, int dePin)
    : port_(port), txPin_(txPin), dePin_(dePin) {}

bool DmxUartEsp32::begin(const char* taskName) {
  pinMode(dePin_, OUTPUT);
  digitalWrite(dePin_, HIGH);  // Transceiver dauerhaft auf Senden

  uart_config_t cfg = {};
  cfg.baud_rate = 250000;
  cfg.data_bits = UART_DATA_8_BITS;
  cfg.parity = UART_PARITY_DISABLE;
  cfg.stop_bits = UART_STOP_BITS_2;
  cfg.flow_ctrl = UART_HW_FLOWCTRL_DISABLE;
  cfg.source_clk = UART_SCLK_APB;

  if (uart_driver_install(port_, 256, 1024, 0, nullptr, 0) != ESP_OK) return false;
  if (uart_param_config(port_, &cfg) != ESP_OK) return false;
  if (uart_set_pin(port_, txPin_, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE,
                   UART_PIN_NO_CHANGE) != ESP_OK)
    return false;

  // Priorität über loop(), damit das Timing stabil bleibt; Core 1 (WLAN läuft auf Core 0).
  return xTaskCreatePinnedToCore(taskEntry, taskName, 3072, this, 5, nullptr, 1) == pdPASS;
}

void DmxUartEsp32::write(const uint8_t* data, uint16_t length) {
  if (length > dmx::kUniverseSize) length = dmx::kUniverseSize;
  portENTER_CRITICAL(&mux_);
  memcpy(shared_ + 1, data, length);
  portEXIT_CRITICAL(&mux_);
}

void DmxUartEsp32::taskEntry(void* arg) { static_cast<DmxUartEsp32*>(arg)->run(); }

void DmxUartEsp32::run() {
  for (;;) {
    portENTER_CRITICAL(&mux_);
    memcpy(frame_, shared_, sizeof(frame_));
    portEXIT_CRITICAL(&mux_);
    frame_[0] = 0x00;  // Startcode: Dimmer-Daten

    uart_wait_tx_done(port_, portMAX_DELAY);  // letztes Byte komplett raus

    // Break: TX-Leitung invertieren = Dauer-Low
    uart_set_line_inverse(port_, UART_SIGNAL_TXD_INV);
    delayMicroseconds(kBreakUs);
    uart_set_line_inverse(port_, UART_SIGNAL_INV_DISABLE);
    delayMicroseconds(kMabUs);

    uart_write_bytes(port_, reinterpret_cast<const char*>(frame_), sizeof(frame_));
    framesSent_ = framesSent_ + 1;
  }
}
