# DMX-Projekt: App + WLAN-Dongle

Flutter-App (Android zuerst, später iOS/Web/Desktop) steuert über **Art-Net (UDP, WLAN)** einen selbstgebauten Dongle, der daraus echtes **DMX512** für die Lampen macht.

```
┌──────────────┐   WLAN / Art-Net 4    ┌───────────────────┐  RS485   ┌────────┐
│  Flutter-App │ ───── UDP 6454 ─────▶ │  Dongle (ESP32)   │ ───────▶ │ Lampen │
│  Android     │ ◀── ArtPollReply ──── │  2 × DMX-Ausgang  │  XLR     └────────┘
└──────────────┘                       └───────────────────┘
```

Warum Art-Net statt eigenem Protokoll: Standard, also funktioniert der Dongle auch mit QLC+, MA onPC, Resolume usw. – und die App kann auch fremde Art-Net-Nodes steuern. Gut zum Testen, bevor die eigene Hardware fertig ist.

---

## Ordnerstruktur

```
firmware/
  lib/dmxcore/src/      ← portabler Kern (KEIN Arduino/ESP-Code)
    hal.h                 Interfaces: IDmxOutput, IClock
    artnet.h/.cpp         Art-Net Parsing + PollReply
    dmx_node.h/.cpp       Routing Port-Address → Ausgang, Status
  src/                  ← ESP32-spezifisch
    main.cpp              WLAN (STA + AP-Fallback), UDP, Web-Setup, LED
    dmx_uart_esp32.*      DMX-Treiber: UART 250k 8N2, Break per TX-Inversion
  include/board_config.h  Pins & Konstanten
  test/host/            ← Unit-Tests des Kerns auf dem PC (g++)

app/
  lib/core/artnet/      Art-Net Pakete (pure Dart)
  lib/core/transport/   DmxTransport-Interface, UDP-Implementierung, Web-Stub
  lib/core/dmx/         DmxEngine: Werte, Fades, Chaser, Grandmaster, 40-Hz-Ausgabe
  lib/models/           Profile, Geräte, Szenen, Chaser, Netzwerk
  lib/data/             Eingebaute Profile, Speicherung (SharedPreferences)
  lib/state/            AppState: Patch, Show-Daten
  lib/ui/               Fader · Geräte · Szenen/Chaser · Netzwerk
  tool/setup_platforms.dart   setzt Netzwerk-Berechtigungen nach flutter create
```

---

## Hardware (ESP32-Prototyp)

Pro DMX-Ausgang ein RS485-Transceiver (MAX485, SN75176 oder besser isoliert: ADM2587E).

| ESP32 | MAX485 Port A | MAX485 Port B |
|---|---|---|
| GPIO 17 (UART2 TX) | DI | – |
| GPIO 4 | DE + /RE | – |
| GPIO 25 (UART1 TX) | – | DI |
| GPIO 26 | – | DE + /RE |
| 3V3 / GND | VCC / GND | VCC / GND |

MAX485 → XLR: **A → Pin 3 (Data+)**, **B → Pin 2 (Data−)**, GND → Pin 1.
Am letzten Gerät der Kette 120 Ω Abschluss. Der MAX485 ist eigentlich ein 5-V-Baustein, läuft an 3,3 V meist trotzdem – für saubere Hardware einen 3,3-V-Typ (z.B. MAX3485, SP3485) nehmen.

---

## Firmware

Voraussetzung: [PlatformIO](https://platformio.org) (VS Code-Extension oder CLI).

```bash
cd firmware
pio run -t upload        # bauen + flashen
pio device monitor       # Log ansehen (115200)
make -C test/host        # Kern-Tests auf dem PC
```

**Erster Start:** Kein WLAN gespeichert → Dongle öffnet Access-Point `DMX-Dongle-XXXX`, Passwort `dmxdongle`, IP `192.168.4.1`.
Im Browser `http://192.168.4.1` öffnen → Heim-WLAN, Name, Net/Sub-Net/Universen einstellen. Ohne SSID bleibt er im AP-Modus (gut für unterwegs).
**BOOT-Taste 3 s halten** löscht die WLAN-Daten.

**Standard-Zuordnung:** Port A = Universe 0, Port B = Universe 1 (Net 0, Sub-Net 0) → passt zu App-Universe 1 und 2.

Timing: Break 176 µs, MAB 12 µs, 512 Kanäle ≈ 43 Hz. Jeder Ausgang läuft in eigenem FreeRTOS-Task auf Core 1, WLAN auf Core 0. Bei ausbleibenden Daten hält der Dongle den letzten Zustand.

---

## App

Voraussetzung: [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.35+), Android Studio für das Android-SDK.

```bash
cd app
flutter create --project-name dmx_control --org de.dmxcontrol \
  --platforms=android,ios,web,windows,macos,linux .
dart run tool/setup_platforms.dart     # Berechtigungen eintragen
flutter pub get
flutter test                            # Art-Net-Tests
flutter run                             # Handy per USB anschließen
```

`flutter create .` legt nur die Plattform-Ordner an, vorhandener Code bleibt.

**Bedienung**
- **Fader:** 512 Kanäle pro Universe, Kanalnummer antippen = 0/255. Gepatchte Geräte werden beschriftet.
- **Geräte:** + → Profil, Universe, Startadresse (wird automatisch vorgeschlagen), Anzahl. Tippen = steuern; lang drücken = Mehrfachauswahl → mehrere gleichzeitig (Dimmer, Farbe inkl. RGBW-Weißanteil, Pan/Tilt-Feld, Strobe, alle Kanäle).
- **Szenen:** speichern den kompletten Zustand aller Universen; Tippen = mit Fade abrufen, lang drücken = Menü.
- **Chaser:** Szenen als Schritte mit Fade- und Haltezeit, sortierbar, mit Schleife.
- **Unten immer:** Grandmaster (wirkt auf Dimmer-Kanäle, bei Geräten ohne Dimmer auf die Farben) und Blackout.
- **Netzwerk:** „Suchen“ schickt ArtPoll, gefundenen Dongle mit „Nutzen“ übernehmen. Anzeige der gesendeten Pakete/s.

Senden: geänderte Universen sofort, sonst alle 800 ms Keep-Alive (Art-Net-Empfehlung, und schont das WLAN).

---

## Architektur-Entscheidungen

| Thema | Entscheidung | Grund |
|---|---|---|
| Protokoll | Art-Net 4, Unicast an Dongle-IP, Broadcast als Fallback | Standard, Fremd-Software kompatibel |
| Firmware-Schnitt | `dmxcore` ohne Plattform-Includes, nur `IDmxOutput`/`IClock` | STM32-Port = nur neue Treiber |
| App-Transport | Interface `DmxTransport`, UDP-Impl. über `dart:io` | Web braucht später WebSocket |
| App-State | `ChangeNotifier` + `ListenableBuilder`, keine Zusatz-Pakete | Wenig Abhängigkeiten, leicht erweiterbar |
| Speicherung | JSON in SharedPreferences | Läuft auf allen Plattformen inkl. Web |

---

## Fahrplan

**Als Nächstes**
1. Auf Hardware testen: Logic-Analyzer an DI → Break/MAB/Frame prüfen.
2. Profil-Editor in der App (eigene Geräte anlegen, Import/Export als JSON).
3. Fixture-Library: Open Fixture Library (OFL) Import.
4. Show-Export/-Import (Backup, zwischen Geräten teilen).

**iOS / Desktop:** gleicher Code; `tool/setup_platforms.dart` setzt die Netzwerk-Hinweise. iOS fragt beim ersten Start nach „Lokales Netzwerk“.

**Web:** Browser können kein UDP. Plan: Firmware bekommt einen WebSocket-Endpunkt (`/ws`, binäre Frames: 2 Byte Port-Address + 512 Byte), App bekommt `WebSocketTransport` in `transport_stub.dart`-Platz.

**Eigene STM32-Hardware**
- `dmxcore` unverändert übernehmen.
- `IDmxOutput` mit USART + DMA implementieren (Break per GPIO-Umschaltung oder LIN-Break-Funktion), ein Timer für die Frame-Rate.
- Netzwerk: Ethernet (W5500 oder STM32 mit MAC + LAN8742) oder ESP32-C3 als WLAN-Coprozessor über SPI/UART.
- Empfehlung: STM32G4 oder F4, isolierte RS485-Treiber, 5-Pol-XLR, Status-LEDs je Port.
- RDM (Rückkanal, Geräte-Adressierung aus der App) wird mit eigener Hardware möglich – Transceiver dafür bidirektional verdrahten.

## Bekannte Grenzen (Stand 0.1)
- Firmware-ESP32-Schicht und App sind noch nicht auf echter Hardware/Gerät getestet; der Firmware-Kern hat Unit-Tests.
- Kein HTP/LTP-Merge mehrerer Sender – der letzte gewinnt.
- Universen-Einstellung am Dongle derzeit nur über die Webseite (ArtAddress aus der App folgt).
- Pan/Tilt nur 8 Bit (Fine-Kanäle bleiben 0).
