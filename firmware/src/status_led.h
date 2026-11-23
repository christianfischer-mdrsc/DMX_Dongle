#pragma once
// Status-LED (IO2): zeigt per Blinkmuster, was der Dongle gerade tut.
// Läuft in einem eigenen kleinen Task, blinkt also auch während setup()
// blockiert (z.B. beim Verbinden mit dem WLAN).
//
//   Muster                               Bedeutung
//   ─────────────────────────────────────────────────────────────────────
//   schnelles Flackern (10 Hz)           Start / Initialisierung
//   gleichmäßig blinken (2 Hz)           verbindet mit Heim-WLAN
//   kurzer Blitz alle 2 s                Access-Point offen, niemand verbunden
//   Doppelblitz alle 2 s                 im WLAN / Handy verbunden, wartet auf Steuerung
//   dauerhaft an, kurz aus bei Daten     Steuerung (App/Pult) gefunden, DMX läuft
//   sehr schnelles Flackern (20 Hz)      Firmware-Update läuft
//   3 lange Blinker                      Fehler (z.B. Update fehlgeschlagen)
//   an, solange BOOT gedrückt            nach 3 s werden die WLAN-Daten gelöscht

#include <stdint.h>

namespace statusled {

enum class Mode : uint8_t {
  Boot,
  WifiConnecting,
  ApWaiting,
  Ready,     // WLAN steht bzw. Client am AP, aber noch keine Steuerung
  Master,    // Art-Net-Steuerung gesehen
  Ota,
  Button,
};

void begin(int pin);
void setMode(Mode m);
Mode mode();

// Bei jedem empfangenen DMX-Paket aufrufen: LED geht kurz aus (Aktivität).
void activity();

// Einmal 3 lange Blinker, danach zurück zum vorherigen Modus.
void error();

}  // namespace statusled
