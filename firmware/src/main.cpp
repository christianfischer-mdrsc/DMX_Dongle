// main.cpp – ESP32-Glue: WLAN, UDP, Web-Setup, Firmware-Update, LED.
// Die eigentliche Art-Net/DMX-Logik steckt in lib/dmxcore (portabel).
#include <Arduino.h>
#include <Preferences.h>
#include <Update.h>
#include <WebServer.h>
#include <WiFi.h>
#include <WiFiUdp.h>

#include <string>

#include "artnet.h"
#include "board_config.h"
#include "dmx_node.h"
#include "dmx_uart_esp32.h"
#include "minijson.h"
#include "status_led.h"
#include "usb_mirror.h"
#include "usb_proto.h"

namespace {

struct ArduinoClock : dmx::IClock {
  uint32_t millis() const override { return ::millis(); }
} gClock;

DmxUartEsp32 gPortA(DMX_A_UART, DMX_A_TX, DMX_A_DE, 0);
DmxUartEsp32 gPortB(DMX_B_UART, DMX_B_TX, DMX_B_DE, 1);
dmx::IDmxOutput* gOutputs[DMX_NUM_PORTS] = {&gPortA, &gPortB};
dmx::DmxNode gNode(gOutputs, DMX_NUM_PORTS, gClock);

WiFiUDP gUdp;
WebServer gWeb(80);
Preferences gPrefs;

uint8_t gRx[600];
uint8_t gTx[artnet::kPollReplySize];
bool gApMode = false;
uint32_t gLastArtnetAt = 0;  // 0 = noch nie Art-Net gesehen
String gOtaKey;
String gOtaError;

// Diagnose: empfangene UDP-Pakete pro Sekunde (Log im Simulator-Tab "Dongle")
uint32_t gUdpCount = 0, gDmxCount = 0, gUdpStatAt = 0;
IPAddress gUdpLastFrom;

// ---------- Konfiguration (NVS) ----------

// WLAN-Betriebsart. Ohne gespeicherten Wert: Heimnetz, wenn eine SSID da ist, sonst AP.
enum class WifiMode : uint8_t { Sta = 0, Ap = 1, Off = 2 };

struct Settings {
  WifiMode wifi = WifiMode::Ap;
  String ssid, pass;
  String apSsid;  // leer = DMX-Dongle-XXXX
  String apPass;
  bool enabled[DMX_NUM_PORTS];
} gSet;

bool gWifiOff = false;
uint32_t gLastUsbAt = 0;  // 0 = noch nie DMX über USB

const char* wifiModeName(WifiMode m) {
  return m == WifiMode::Off ? "off" : m == WifiMode::Ap ? "ap" : "sta";
}

String defaultApName() {
  uint8_t mac[6];
  WiFi.macAddress(mac);
  char apName[32];
  snprintf(apName, sizeof(apName), "DMX-Dongle-%02X%02X", mac[4], mac[5]);
  return apName;
}

String apName() { return gSet.apSsid.length() ? gSet.apSsid : defaultApName(); }

void loadConfig(dmx::NodeConfig& cfg) {
  gPrefs.begin("dmx", true);
  gSet.ssid = gPrefs.getString("ssid", "");
  gSet.pass = gPrefs.getString("pass", "");
  gSet.apSsid = gPrefs.getString("apssid", "");
  gSet.apPass = gPrefs.getString("appass", AP_PASSWORD);
  if (gSet.apPass.length() < 8) gSet.apPass = AP_PASSWORD;
  const uint8_t legacy = gSet.ssid.length() ? 0 : 1;
  gSet.wifi = static_cast<WifiMode>(gPrefs.getUChar("wifi", legacy));
  if (static_cast<uint8_t>(gSet.wifi) > 2) gSet.wifi = WifiMode::Ap;
  cfg.net = gPrefs.getUChar("net", 0);
  cfg.subnet = gPrefs.getUChar("sub", 0);
  for (uint8_t i = 0; i < DMX_NUM_PORTS; ++i) {
    char key[4] = {'u', char('0' + i), 0};
    cfg.universe[i] = gPrefs.getUChar(key, i);
    char en[4] = {'e', 'n', char('0' + i), 0};
    gSet.enabled[i] = gPrefs.getBool(en, true);
  }
  String name = gPrefs.getString("name", "");
  gOtaKey = gPrefs.getString("otakey", OTA_DEFAULT_KEY);
  gPrefs.end();
  if (name.length()) {
    strlcpy(cfg.shortName, name.c_str(), sizeof(cfg.shortName));
    snprintf(cfg.longName, sizeof(cfg.longName), "%s (DMX-Dongle)", cfg.shortName);
  }
}

// ---------- WLAN ----------

void startWifi() {
  WiFi.persistent(false);
  if (gSet.wifi == WifiMode::Off) {
    WiFi.mode(WIFI_OFF);
    gWifiOff = true;
    Serial.println("[WLAN] aus – Steuerung nur über USB (BOOT 3 s = WLAN wieder an)");
    return;
  }
  const String& ssid = gSet.ssid;
  const String& pass = gSet.pass;
  if (gSet.wifi == WifiMode::Sta && ssid.length()) {
    WiFi.mode(WIFI_STA);
    WiFi.setHostname(gNode.config().shortName);
    WiFi.begin(ssid.c_str(), pass.c_str());
    Serial.printf("[WLAN] Verbinde mit '%s' ...\n", ssid.c_str());
    statusled::setMode(statusled::Mode::WifiConnecting);
    uint32_t t0 = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - t0 < STA_TIMEOUT_MS) delay(100);
    if (WiFi.status() == WL_CONNECTED) {
      WiFi.setSleep(false);  // wichtig: sonst 100+ ms Latenz
      Serial.printf("[WLAN] OK, IP %s\n", WiFi.localIP().toString().c_str());
      return;
    }
    Serial.println("[WLAN] Timeout -> Access-Point");
  }
  gApMode = true;
  const String ap = apName();
  WiFi.onEvent([](WiFiEvent_t, WiFiEventInfo_t info) {
    const uint8_t* m = info.wifi_ap_staconnected.mac;
    Serial.printf("[WLAN] Client verbunden: %02X:%02X:%02X:%02X:%02X:%02X\n", m[0], m[1], m[2],
                  m[3], m[4], m[5]);
  }, ARDUINO_EVENT_WIFI_AP_STACONNECTED);
  WiFi.onEvent([](WiFiEvent_t, WiFiEventInfo_t info) {
    Serial.printf("[WLAN] Client hat IP %s\n",
                  IPAddress(info.wifi_ap_staipassigned.ip.addr).toString().c_str());
  }, ARDUINO_EVENT_WIFI_AP_STAIPASSIGNED);
  WiFi.onEvent([](WiFiEvent_t, WiFiEventInfo_t) { Serial.println("[WLAN] Client getrennt"); },
               ARDUINO_EVENT_WIFI_AP_STADISCONNECTED);
  WiFi.mode(WIFI_AP);
  WiFi.softAP(ap.c_str(), gSet.apPass.c_str());
  WiFi.setSleep(false);
  Serial.printf("[WLAN] AP '%s', IP %s\n", ap.c_str(), WiFi.softAPIP().toString().c_str());
}

IPAddress localIp() {
  if (gWifiOff) return IPAddress(0, 0, 0, 0);
  return gApMode ? WiFi.softAPIP() : WiFi.localIP();
}

// ---------- Web-Setup ----------

const char kPage[] PROGMEM = R"HTML(<!doctype html><html><head>
<meta name=viewport content="width=device-width,initial-scale=1"><title>DMX-Dongle</title>
<style>body{font-family:sans-serif;max-width:420px;margin:20px auto;padding:0 16px}
input{width:100%;padding:8px;margin:4px 0 12px;box-sizing:border-box}
button{padding:10px 16px}</style></head><body>
<h2>DMX-Dongle Setup</h2><form method=post action=/save>
<label>Name</label><input name=name value="%NAME%" maxlength=17>
<label>WLAN SSID (leer = Access-Point)</label><input name=ssid value="%SSID%">
<label>WLAN Passwort</label><input name=pass type=password>
<label>Art-Net Net (0-127)</label><input name=net type=number min=0 max=127 value=%NET%>
<label>Sub-Net (0-15)</label><input name=sub type=number min=0 max=15 value=%SUB%>
<label>Universe Port A (0-15)</label><input name=u0 type=number min=0 max=15 value=%U0%>
<label>Universe Port B (0-15)</label><input name=u1 type=number min=0 max=15 value=%U1%>
<label>Update-Schl&uuml;ssel (leer = unver&auml;ndert, min. 8 Zeichen)</label><input name=otakey type=password minlength=8>
<button>Speichern &amp; Neustart</button></form>
<h3>Firmware-Update</h3>
<form method=post enctype=multipart/form-data
 onsubmit="this.action='/update?key='+encodeURIComponent(k.value);b.disabled=1;b.textContent='Wird geflasht ...'">
<label>Datei (firmware.bin)</label><input name=f type=file accept=.bin required>
<label>Update-Schl&uuml;ssel</label><input id=k type=password required>
<button id=b>Flashen</button></form>
<p>Firmware %FW% &middot; Frames: %FRAMES%</p></body></html>)HTML";

void handleRoot() {
  String html = FPSTR(kPage);
  const auto& c = gNode.config();
  gPrefs.begin("dmx", true);
  html.replace("%SSID%", gPrefs.getString("ssid", ""));
  gPrefs.end();
  html.replace("%NAME%", c.shortName);
  html.replace("%NET%", String(c.net));
  html.replace("%SUB%", String(c.subnet));
  html.replace("%U0%", String(c.universe[0]));
  html.replace("%U1%", String(c.universe[1]));
  html.replace("%FW%", FW_VERSION_STR);
  html.replace("%FRAMES%", String(gNode.framesReceived()));
  gWeb.send(200, "text/html", html);
}

void handleSave() {
  gPrefs.begin("dmx", false);
  gPrefs.putString("name", gWeb.arg("name"));
  gPrefs.putString("ssid", gWeb.arg("ssid"));
  gPrefs.putUChar("wifi", gWeb.arg("ssid").length() ? 0 : 1);
  if (gWeb.arg("pass").length() || !gWeb.arg("ssid").length())
    gPrefs.putString("pass", gWeb.arg("pass"));
  gPrefs.putUChar("net", constrain(gWeb.arg("net").toInt(), 0, 127));
  gPrefs.putUChar("sub", constrain(gWeb.arg("sub").toInt(), 0, 15));
  gPrefs.putUChar("u0", constrain(gWeb.arg("u0").toInt(), 0, 15));
  gPrefs.putUChar("u1", constrain(gWeb.arg("u1").toInt(), 0, 15));
  if (gWeb.arg("otakey").length() >= 8) gPrefs.putString("otakey", gWeb.arg("otakey"));
  gPrefs.end();
  gWeb.send(200, "text/html", "<p>Gespeichert, starte neu ...</p>");
  delay(500);
  ESP.restart();
}

// ---------- Info & Firmware-Update ----------

// GET /api/info – für die App: Name, Firmware-Version, Netz
void handleInfo() {
  const auto& c = gNode.config();
  String j = "{";
  j += "\"name\":\"" + String(c.shortName) + "\",";
  j += "\"fw\":\"" FW_VERSION_STR "\",";
  j += "\"mode\":\"" + String(gApMode ? "ap" : "sta") + "\",";
  j += "\"ip\":\"" + localIp().toString() + "\",";
  j += "\"rssi\":" + String(gApMode ? 0 : WiFi.RSSI()) + ",";
  j += "\"uptime\":" + String(millis() / 1000) + ",";
  j += "\"frames\":" + String(gNode.framesReceived()) + ",";
  j += "\"free\":" + String(ESP.getFreeSketchSpace()) + ",";
  j += "\"ota\":true}";
  gWeb.sendHeader("Access-Control-Allow-Origin", "*");
  gWeb.send(200, "application/json", j);
}

// POST /update?key=...&md5=...  (multipart, Feldname beliebig)
// Schreibt in die freie OTA-Partition. Erst ein erfolgreiches Update.end()
// schaltet um; ein Abbruch lässt die laufende Firmware aktiv.
void handleUpdateUpload() {
  HTTPUpload& up = gWeb.upload();
  switch (up.status) {
    case UPLOAD_FILE_START:
      gOtaError = "";
      if (gWeb.arg("key") != gOtaKey) {
        gOtaError = "key";
        Serial.println("[OTA] falscher Schluessel");
        return;
      }
      if (!Update.begin(UPDATE_SIZE_UNKNOWN, U_FLASH)) {
        gOtaError = Update.errorString();
        return;
      }
      if (gWeb.arg("md5").length() == 32) Update.setMD5(gWeb.arg("md5").c_str());
      statusled::setMode(statusled::Mode::Ota);
      Serial.printf("[OTA] Start: %s\n", up.filename.c_str());
      break;
    case UPLOAD_FILE_WRITE:
      if (gOtaError.length() || !Update.isRunning()) return;
      if (Update.write(up.buf, up.currentSize) != up.currentSize) gOtaError = Update.errorString();
      break;
    case UPLOAD_FILE_END:
      if (gOtaError.length() || !Update.isRunning()) break;
      if (!Update.end(true)) gOtaError = Update.errorString();
      else Serial.printf("[OTA] %u Bytes geschrieben\n", up.totalSize);
      break;
    case UPLOAD_FILE_ABORTED:
      gOtaError = "Upload abgebrochen";
      break;
  }
  if (gOtaError.length() && Update.isRunning()) Update.abort();
}

void handleUpdateDone() {
  gWeb.sendHeader("Access-Control-Allow-Origin", "*");
  if (gOtaError == "key") {
    gWeb.send(401, "application/json", "{\"ok\":false,\"error\":\"Update-Schluessel falsch\"}");
  } else if (gOtaError.length() || !Update.isFinished()) {
    String e = gOtaError.length() ? gOtaError : String("keine Datei empfangen");
    e.replace("\"", "'");
    Serial.printf("[OTA] Fehler: %s\n", e.c_str());
    statusled::error();
    gWeb.send(500, "application/json", "{\"ok\":false,\"error\":\"" + e + "\"}");
  } else {
    gWeb.send(200, "application/json", "{\"ok\":true}");
    Serial.println("[OTA] OK, Neustart");
    delay(500);
    ESP.restart();
  }
  gOtaError = "";
  if (statusled::mode() == statusled::Mode::Ota) statusled::setMode(statusled::Mode::Ready);
}

// ---------- Art-Net ----------

void sendPollReply(const IPAddress& to) {
  uint8_t ip[4], mac[6];
  IPAddress me = localIp();
  for (int i = 0; i < 4; ++i) ip[i] = me[i];
  if (gApMode) WiFi.softAPmacAddress(mac); else WiFi.macAddress(mac);
  size_t n = gNode.buildPollReply(ip, mac, FW_VERSION, gTx, sizeof(gTx));
  gUdp.beginPacket(to, artnet::kPort);
  gUdp.write(gTx, n);
  gUdp.endPacket();
}

void pollUdp() {
  // Mehrere Pakete pro loop() abarbeiten (mehrere Universen bei 40 Hz)
  for (int i = 0; i < 8; ++i) {
    int len = gUdp.parsePacket();
    if (len <= 0) return;
    int n = gUdp.read(gRx, sizeof(gRx));
    if (n <= 0) continue;
    ++gUdpCount;
    gUdpLastFrom = gUdp.remoteIP();
    const auto result = gNode.handlePacket(gRx, static_cast<size_t>(n),
                                           static_cast<uint32_t>(gUdp.remoteIP()),
                                           gUdp.remotePort());
    if (result != dmx::PacketResult::Ignored) {
      if (!gLastArtnetAt || millis() - gLastArtnetAt >= MASTER_TIMEOUT_MS)
        Serial.printf("[ArtNet] Steuerung gefunden: %s\n", gUdp.remoteIP().toString().c_str());
      gLastArtnetAt = millis() | 1;
    }
    switch (result) {
      case dmx::PacketResult::PollReceived:
        Serial.printf("[ArtNet] ArtPoll von %s -> Reply\n", gUdp.remoteIP().toString().c_str());
        sendPollReply(gUdp.remoteIP());
        break;
      case dmx::PacketResult::DmxApplied:
        ++gDmxCount;
        statusled::activity();
        break;
      default:
        break;
    }
  }
}

// Live-Abgleich: den gemischten Stand jedes Ausgangs an alle Steuerungen
// zurückschicken (bei Änderung max. 30/s, sonst alle 0,3 s). So sieht das Handy, was
// am PC geändert wird, und umgekehrt.
uint8_t gEcho[18 + 512];
uint8_t gEchoSeq[DMX_NUM_PORTS] = {};

void sendEchoes() {
  for (uint8_t p = 0; p < DMX_NUM_PORTS; ++p) {
    if (!gNode.echoDue(p)) continue;
    uint32_t ids[dmx::kMaxSources];
    uint16_t ports[dmx::kMaxSources];
    const uint8_t n = gNode.echoTargets(p, ids, ports);
    if (++gEchoSeq[p] == 0) gEchoSeq[p] = 1;
    const size_t len = artnet::buildDmx(gNode.portAddressOf(p), gEchoSeq[p], gNode.mergedData(p),
                                        512, gEcho, sizeof(gEcho));
    for (uint8_t i = 0; i < n; ++i) {
      if (ids[i] == 0xFFFFFFFFu) continue;  // USB-Host: Echo kommt über den USB-Spiegel
      gUdp.beginPacket(IPAddress(ids[i]), ports[i]);
      gUdp.write(gEcho, len);
      gUdp.endPacket();
    }
  }
}

// LED-Modus aus dem aktuellen Zustand ableiten (Update und Taste haben Vorrang)
void updateLedMode() {
  using statusled::Mode;
  const Mode m = statusled::mode();
  if (m == Mode::Ota || m == Mode::Button) return;
  Mode next;
  if ((gLastArtnetAt && millis() - gLastArtnetAt < MASTER_TIMEOUT_MS) ||
      (gLastUsbAt && millis() - gLastUsbAt < MASTER_TIMEOUT_MS)) {
    next = Mode::Master;
  } else if (gWifiOff) {
    next = Mode::Ready;
  } else if (gApMode) {
    next = WiFi.softAPgetStationNum() > 0 ? Mode::Ready : Mode::ApWaiting;
  } else {
    next = WiFi.status() == WL_CONNECTED ? Mode::Ready : Mode::WifiConnecting;
  }
  if (next != m) statusled::setMode(next);
}

void checkResetButton() {
  static uint32_t pressedSince = 0;
  if (digitalRead(RESET_BTN) == LOW) {
    if (!pressedSince) pressedSince = millis();
    if (millis() - pressedSince > 300) statusled::setMode(statusled::Mode::Button);
    if (millis() - pressedSince > 3000) {
      gPrefs.begin("dmx", false);
      gPrefs.remove("ssid");
      gPrefs.remove("pass");
      gPrefs.remove("wifi");
      gPrefs.remove("apssid");
      gPrefs.remove("appass");
      gPrefs.end();
      Serial.println("[RESET] WLAN zurueckgesetzt: eigener Access-Point, Passwort " AP_PASSWORD);
      ESP.restart();
    }
  } else {
    // Modus freigeben, updateLedMode() setzt den passenden
    if (pressedSince && statusled::mode() == statusled::Mode::Button)
      statusled::setMode(statusled::Mode::Ready);
    pressedSince = 0;
  }
}


// ---------- Steuerung & Einrichtung über USB (Handy per USB-C, Android) ----------
// Paketformat siehe lib/dmxcore/src/usb_proto.h. DMX über USB wird genauso
// gemischt wie Art-Net; das Echo bekommt der USB-Host über den USB-Spiegel.

constexpr uint32_t kUsbSource = 0xFFFFFFFFu;  // Absender-Kennung im Merger

void usbReply(uint8_t type, const std::string& json) {
  usbmirror::send(type, reinterpret_cast<const uint8_t*>(json.data()),
                  static_cast<uint16_t>(json.size()));
}

void usbResult(bool ok, const char* error, bool restart) {
  std::string j = "{\"ok\":";
  j += ok ? "true" : "false";
  if (error) {
    j += ",\"error\":";
    minijson::appendString(j, error);
  }
  j += ",\"restart\":";
  j += restart ? "true" : "false";
  j += "}";
  usbReply(usbproto::kResult, j);
}

void addStr(std::string& j, const char* key, const char* value, bool comma = true) {
  if (comma) j += ',';
  minijson::appendString(j, key);
  j += ':';
  minijson::appendString(j, value);
}

void addNum(std::string& j, const char* key, long value) {
  j += ',';
  minijson::appendString(j, key);
  j += ':';
  j += std::to_string(value);
}

void addBool(std::string& j, const char* key, bool value) {
  j += ',';
  minijson::appendString(j, key);
  j += value ? ":true" : ":false";
}

void usbSendConfig() {
  const auto& c = gNode.config();
  std::string j = "{";
  addStr(j, "name", c.shortName, false);
  addStr(j, "fw", FW_VERSION_STR);
  addStr(j, "wifi", wifiModeName(gSet.wifi));
  addStr(j, "ssid", gSet.ssid.c_str());
  addBool(j, "hasPass", gSet.pass.length() > 0);
  addStr(j, "apSsid", gSet.apSsid.c_str());
  addStr(j, "apSsidDefault", defaultApName().c_str());
  addBool(j, "apPassDefault", gSet.apPass == AP_PASSWORD);
  addNum(j, "net", c.net);
  addNum(j, "sub", c.subnet);
  for (uint8_t i = 0; i < DMX_NUM_PORTS; ++i) {
    char k[4] = {'u', char('0' + i), 0};
    addNum(j, k, c.universe[i]);
    char e[4] = {'e', 'n', char('0' + i), 0};
    addBool(j, e, gSet.enabled[i]);
  }
  j += "}";
  usbReply(usbproto::kConfig, j);
}

void usbSendInfo() {
  const auto& c = gNode.config();
  std::string j = "{";
  addStr(j, "name", c.shortName, false);
  addStr(j, "fw", FW_VERSION_STR);
  addStr(j, "wifi", gWifiOff ? "off" : gApMode ? "ap" : "sta");
  addBool(j, "connected", !gWifiOff && !gApMode && WiFi.status() == WL_CONNECTED);
  addStr(j, "ip", localIp().toString().c_str());
  addStr(j, "network", gWifiOff ? "" : gApMode ? apName().c_str() : gSet.ssid.c_str());
  addNum(j, "rssi", (!gWifiOff && !gApMode) ? WiFi.RSSI() : 0);
  addNum(j, "clients", (!gWifiOff && gApMode) ? WiFi.softAPgetStationNum() : 0);
  addNum(j, "uptime", millis() / 1000);
  addNum(j, "frames", gNode.framesReceived());
  addNum(j, "heap", ESP.getFreeHeap());
  addBool(j, "artnet", gLastArtnetAt && millis() - gLastArtnetAt < MASTER_TIMEOUT_MS);
  j += ",\"ports\":[";
  for (uint8_t i = 0; i < DMX_NUM_PORTS; ++i) {
    if (i) j += ',';
    j += "{";
    addStr(j, "port", i == 0 ? "A" : "B", false);
    addBool(j, "on", gSet.enabled[i]);
    addNum(j, "universe", gNode.portAddressOf(i) + 1);
    addBool(j, "active", gSet.enabled[i] && gNode.portActive(i));
    j += "}";
  }
  j += "]}";
  usbReply(usbproto::kInfo, j);
}

void usbScanWifi() {
  const wifi_mode_t old = WiFi.getMode();
  if (old == WIFI_OFF) WiFi.mode(WIFI_STA);
  else if (old == WIFI_AP) WiFi.mode(WIFI_AP_STA);
  Serial.println("[WLAN] Suche Netze ...");
  const int n = WiFi.scanNetworks(false, false);
  std::string j = "{\"networks\":[";
  int added = 0;
  for (int i = 0; i < n && added < 20; ++i) {
    const String ssid = WiFi.SSID(i);
    if (!ssid.length()) continue;
    bool dup = false;  // gleiche SSID mehrfach (Mesh): nur die stärkste
    for (int k = 0; k < i; ++k)
      if (WiFi.SSID(k) == ssid) dup = true;
    if (dup) continue;
    if (added++) j += ',';
    j += "{";
    addStr(j, "ssid", ssid.c_str(), false);
    addNum(j, "rssi", WiFi.RSSI(i));
    addBool(j, "secure", WiFi.encryptionType(i) != WIFI_AUTH_OPEN);
    j += "}";
  }
  j += "]}";
  WiFi.scanDelete();
  WiFi.mode(old);
  usbReply(usbproto::kWifiList, j);
}

// Einstellungen setzen: nur Felder, die im JSON stehen. Danach Neustart.
void usbApplyConfig(const std::string& json) {
  using namespace minijson;
  std::string s;
  long n;
  bool b;
  dmx::NodeConfig c = gNode.config();
  Settings set = gSet;
  String name = c.shortName, otaKey;

  if (getString(json, "name", s)) {
    if (s.empty() || s.size() > 17) return usbResult(false, "Name: 1 bis 17 Zeichen", false);
    name = s.c_str();
  }
  if (getString(json, "wifi", s)) {
    if (s == "sta") set.wifi = WifiMode::Sta;
    else if (s == "ap") set.wifi = WifiMode::Ap;
    else if (s == "off") set.wifi = WifiMode::Off;
    else return usbResult(false, "wifi muss sta, ap oder off sein", false);
  }
  if (getString(json, "ssid", s)) {
    if (s.size() > 32) return usbResult(false, "SSID zu lang (max. 32 Zeichen)", false);
    set.ssid = s.c_str();
  }
  if (getString(json, "pass", s) && !s.empty()) {
    if (s.size() < 8 || s.size() > 63) return usbResult(false, "WLAN-Passwort: 8 bis 63 Zeichen", false);
    set.pass = s.c_str();
  }
  if (getString(json, "apSsid", s)) {
    if (s.size() > 31) return usbResult(false, "Name des Dongle-WLANs: max. 31 Zeichen", false);
    set.apSsid = s.c_str();
  }
  if (getString(json, "apPass", s) && !s.empty()) {
    if (s.size() < 8 || s.size() > 63) return usbResult(false, "Passwort des Dongle-WLANs: 8 bis 63 Zeichen", false);
    set.apPass = s.c_str();
  }
  if (getString(json, "otaKey", s) && !s.empty()) {
    if (s.size() < 8) return usbResult(false, "Update-Schlüssel: mind. 8 Zeichen", false);
    otaKey = s.c_str();
  }
  if (getInt(json, "net", n)) {
    if (n < 0 || n > 127) return usbResult(false, "Net: 0 bis 127", false);
    c.net = static_cast<uint8_t>(n);
  }
  if (getInt(json, "sub", n)) {
    if (n < 0 || n > 15) return usbResult(false, "Sub-Net: 0 bis 15", false);
    c.subnet = static_cast<uint8_t>(n);
  }
  for (uint8_t i = 0; i < DMX_NUM_PORTS; ++i) {
    char k[4] = {'u', char('0' + i), 0};
    if (getInt(json, k, n)) {
      if (n < 0 || n > 15) return usbResult(false, "Universe je Ausgang: 0 bis 15", false);
      c.universe[i] = static_cast<uint8_t>(n);
    }
    char e[4] = {'e', 'n', char('0' + i), 0};
    if (getBool(json, e, b)) set.enabled[i] = b;
  }
  if (set.wifi == WifiMode::Sta && !set.ssid.length())
    return usbResult(false, "Für das Heimnetz eine SSID angeben", false);

  gPrefs.begin("dmx", false);
  gPrefs.putString("name", name);
  gPrefs.putUChar("wifi", static_cast<uint8_t>(set.wifi));
  gPrefs.putString("ssid", set.ssid);
  gPrefs.putString("pass", set.pass);
  gPrefs.putString("apssid", set.apSsid);
  gPrefs.putString("appass", set.apPass);
  gPrefs.putUChar("net", c.net);
  gPrefs.putUChar("sub", c.subnet);
  for (uint8_t i = 0; i < DMX_NUM_PORTS; ++i) {
    char k[4] = {'u', char('0' + i), 0};
    gPrefs.putUChar(k, c.universe[i]);
    char e[4] = {'e', 'n', char('0' + i), 0};
    gPrefs.putBool(e, set.enabled[i]);
  }
  if (otaKey.length()) gPrefs.putString("otakey", otaKey);
  gPrefs.end();

  Serial.printf("[USB] Einstellungen gespeichert (WLAN %s), Neustart\n", wifiModeName(set.wifi));
  usbResult(true, nullptr, true);
  Serial.flush();
  delay(300);
  ESP.restart();
}

void onUsbPacket(void*, uint8_t type, const uint8_t* p, uint16_t len) {
  switch (type) {
    case usbproto::kHostDmx: {
      if (len < 4) return;
      const uint16_t pa = static_cast<uint16_t>(p[0] | (p[1] << 8));
      uint16_t n = static_cast<uint16_t>(p[2] | (p[3] << 8));
      if (n > len - 4) n = len - 4;
      if (n > 512) n = 512;
      if (gNode.applyDmx(pa, p + 4, n, kUsbSource, 0) == dmx::PacketResult::DmxApplied) {
        if (!gLastUsbAt || millis() - gLastUsbAt >= MASTER_TIMEOUT_MS)
          Serial.println("[USB] Steuerung über USB gefunden");
        gLastUsbAt = millis() | 1;
        statusled::activity();
      }
      break;
    }
    case usbproto::kGetConfig:
      usbSendConfig();
      break;
    case usbproto::kSetConfig:
      usbApplyConfig(std::string(reinterpret_cast<const char*>(p), len));
      break;
    case usbproto::kGetInfo:
      usbSendInfo();
      break;
    case usbproto::kScanWifi:
      usbScanWifi();
      break;
    default:
      break;
  }
}

usbproto::Parser gUsbParser(onUsbPacket, nullptr);
uint8_t gUsbRx[512];

void pollUsb() {
  for (int round = 0; round < 8; ++round) {
    const int avail = Serial.available();
    if (avail <= 0) return;
    const size_t n = Serial.read(gUsbRx, avail < static_cast<int>(sizeof(gUsbRx)) ? avail : sizeof(gUsbRx));
    gUsbParser.feed(gUsbRx, n);
  }
}

}  // namespace

void setup() {
  Serial.setTxBufferSize(4096);  // vor begin()!
  Serial.setRxBufferSize(4096);  // DMX vom Handy über USB
  Serial.begin(USB_MIRROR_BAUD);
  statusled::begin(STATUS_LED);  // ab jetzt: Start-Flackern
  pinMode(RESET_BTN, INPUT_PULLUP);
  Serial.printf("\n[DMX-Dongle] Firmware %s\n", FW_VERSION_STR);

  dmx::NodeConfig cfg;
  loadConfig(cfg);
  gNode.setConfig(cfg);

  // Abgeschaltete Ausgänge: kein Sende-Task, Treiber bleibt hochohmig
  if (gSet.enabled[0]) gPortA.begin("dmxA");
  if (gSet.enabled[1]) gPortB.begin("dmxB");

  startWifi();
  if (!gWifiOff) {
    gUdp.begin(artnet::kPort);
    gWeb.on("/", HTTP_GET, handleRoot);
    gWeb.on("/save", HTTP_POST, handleSave);
    gWeb.on("/api/info", HTTP_GET, handleInfo);
    gWeb.on("/update", HTTP_POST, handleUpdateDone, handleUpdateUpload);
    gWeb.begin();
  }

  Serial.printf("[DMX] Net %u Sub %u, Universen A=%u%s B=%u%s\n", cfg.net, cfg.subnet,
                cfg.universe[0], gSet.enabled[0] ? "" : " (aus)", cfg.universe[1],
                gSet.enabled[1] ? "" : " (aus)");

  for (uint8_t i = 0; i < DMX_NUM_PORTS; ++i)
    usbmirror::setPortAddress(i, artnet::portAddress(cfg.net, cfg.subnet, cfg.universe[i]));
  char hello[96];
  snprintf(hello, sizeof hello, "%s · %s", cfg.shortName,
           gWifiOff ? "nur USB" : localIp().toString().c_str());
  usbmirror::begin(hello);
  updateLedMode();
}

void loop() {
  if (!gWifiOff) {
    pollUdp();
    sendEchoes();
    gWeb.handleClient();
  }
  pollUsb();
  checkResetButton();
  updateLedMode();
  if (millis() - gUdpStatAt >= 1000) {
    if (gUdpCount)
      Serial.printf("[ArtNet] %u UDP-Pakete/s (%u DMX), zuletzt von %s\n", gUdpCount, gDmxCount,
                    gUdpLastFrom.toString().c_str());
    gUdpCount = gDmxCount = 0;
    gUdpStatAt = millis();
  }
  delay(1);
}
