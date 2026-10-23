#pragma once
// USB-Spiegel: schickt die DMX-Ausgabe zusaetzlich ueber USB-Serial an den
// Windows-Simulator (DmxSimulator). ESP32-spezifisch, gehoert nach src/.
//
// Protokoll (alle Mehrbyte-Werte Little Endian):
//   A5 5A | Typ | Seq | Laenge (2) | Nutzdaten | CRC16 (2)
//   CRC-16/CCITT-FALSE (Poly 0x1021, Start 0xFFFF) ueber Typ..Nutzdaten
//
//   Typ 0x01 DMX:    Port (1) | Port-Address (2) | Anzahl (2) | Kanaldaten (ohne Startcode)
//   Typ 0x02 HELLO:  UTF-8-Text (Name, Version, IP ...)
//   Typ 0x03 STATUS: Anzahl Ports (1) | je Port: Port (1) | Port-Address (2) | DMX-Frames/s (2)
//
// Normale Log-Ausgaben (Serial.printf) duerfen weiterlaufen: der Simulator
// erkennt Pakete an Sync + CRC und zeigt den restlichen Text als Log an.

#include <stddef.h>
#include <stdint.h>

namespace usbmirror {

// Startet den Spiegel-Task (Core 0, niedrige Prioritaet).
// Serial muss vorher mit USB_MIRROR_BAUD gestartet sein.
void begin(const char* helloText = nullptr);

// Text, den der Simulator oben anzeigt (z.B. Name + IP). Jederzeit aufrufbar.
void setHello(const char* helloText);

// Art-Net Port-Address des Ausgangs (fuer die Anzeige im Simulator).
void setPortAddress(uint8_t port, uint16_t portAddress);

// Aus dem DMX-Ausgabe-Task nach jedem Frame aufrufen (nicht aus einer ISR).
// data = Kanal 1..len, OHNE Startcode.
void onFrame(uint8_t port, const uint8_t* data, size_t len);

}  // namespace usbmirror
