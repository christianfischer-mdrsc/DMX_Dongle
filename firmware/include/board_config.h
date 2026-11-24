// board_config.h – Pinbelegung & Konstanten für das ESP32-Devboard.
// Für eigene Hardware nur diese Datei anpassen.
#pragma once
#include <driver/uart.h>

// Firmware-Version. Die App vergleicht FW_VERSION_STR mit den veröffentlichten
// Updates; FW_VERSION (Major.Minor) steht zusätzlich im ArtPollReply.
#define FW_MAJOR 1
#define FW_MINOR 4
#define FW_PATCH 0
#define FW_VERSION ((FW_MAJOR << 8) | FW_MINOR)
#define FW_STR2(x) #x
#define FW_STR(x) FW_STR2(x)
#define FW_VERSION_STR FW_STR(FW_MAJOR) "." FW_STR(FW_MINOR) "." FW_STR(FW_PATCH)

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

#define STATUS_LED  2      // Status-LED, Blinkmuster siehe src/status_led.h
#define RESET_BTN   0      // BOOT-Taste 3 s halten → WLAN zurücksetzen (eigener AP)

// Access-Point, wenn kein WLAN konfiguriert / erreichbar
#define AP_PASSWORD "dmxdongle"   // min. 8 Zeichen
#define STA_TIMEOUT_MS 15000

// Steuerung gilt als verloren, wenn so lange kein Art-Net kam (LED-Anzeige)
#define MASTER_TIMEOUT_MS 5000

// Firmware-Update über WLAN: Standard-Schlüssel, änderbar auf der Setup-Seite
#define OTA_DEFAULT_KEY AP_PASSWORD

// USB-Spiegel für den Windows-Simulator (DmxSimulator)
#define USB_MIRROR_ENABLED   1        // 0 = komplett aus, kein Overhead
#define USB_MIRROR_BAUD      921600
#define USB_MIRROR_MAX_HZ    30       // max. Pakete/s pro Ausgang
#define USB_MIRROR_MAX_PORTS 2
