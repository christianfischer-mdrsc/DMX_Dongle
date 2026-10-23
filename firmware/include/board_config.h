// board_config.h – Pinbelegung & Konstanten für das ESP32-Devboard.
// Für eigene Hardware nur diese Datei anpassen.
#pragma once
#include <driver/uart.h>

#define FW_VERSION 0x0100  // 1.0

// Anzahl DMX-Ausgänge (ESP32: UART1 + UART2 frei, UART0 = USB-Log)
#define DMX_NUM_PORTS 2

// Port A  →  MAX485/SN75176:  DI = TX-Pin, DE+/RE = DE-Pin
#define DMX_A_UART  UART_NUM_2
#define DMX_A_TX    17
#define DMX_A_DE    4

// Port B
#define DMX_B_UART  UART_NUM_1
#define DMX_B_TX    25
#define DMX_B_DE    26

#define STATUS_LED  2      // Onboard-LED: blinkt bei DMX-Empfang
#define RESET_BTN   0      // BOOT-Taste 3 s halten → WLAN-Daten löschen

// Access-Point, wenn kein WLAN konfiguriert / erreichbar
#define AP_PASSWORD "dmxdongle"   // min. 8 Zeichen
#define STA_TIMEOUT_MS 15000

// USB-Spiegel für den Windows-Simulator (DmxSimulator)
#define USB_MIRROR_ENABLED   1        // 0 = komplett aus, kein Overhead
#define USB_MIRROR_BAUD      921600
#define USB_MIRROR_MAX_HZ    30       // max. Pakete/s pro Ausgang
#define USB_MIRROR_MAX_PORTS 2
