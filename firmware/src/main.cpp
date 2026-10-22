// main.cpp – ESP32-Glue: WLAN, UDP, Web-Setup, LED.
// Die eigentliche Art-Net/DMX-Logik steckt in lib/dmxcore (portabel).
#include <Arduino.h>
#include <Preferences.h>
#include <WebServer.h>
#include <WiFi.h>
#include <WiFiUdp.h>

#include "artnet.h"
#include "board_config.h"
#include "dmx_node.h"
#include "dmx_uart_esp32.h"

namespace {

struct ArduinoClock : dmx::IClock {
  uint32_t millis() const override { return ::millis(); }
} gClock;

DmxUartEsp32 gPortA(DMX_A_UART, DMX_A_TX, DMX_A_DE);
DmxUartEsp32 gPortB(DMX_B_UART, DMX_B_TX, DMX_B_DE);
dmx::IDmxOutput* gOutputs[DMX_NUM_PORTS] = {&gPortA, &gPortB};
dmx::DmxNode gNode(gOutputs, DMX_NUM_PORTS, gClock);

WiFiUDP gUdp;
WebServer gWeb(80);
Preferences gPrefs;

uint8_t gRx[600];
uint8_t gTx[artnet::kPollReplySize];
bool gApMode = false;
uint32_t gLedOffAt = 0;

// ---------- Konfiguration (NVS) ----------

void loadConfig(dmx::NodeConfig& cfg, String& ssid, String& pass) {
  gPrefs.begin("dmx", true);
  ssid = gPrefs.getString("ssid", "");
  pass = gPrefs.getString("pass", "");
  cfg.net = gPrefs.getUChar("net", 0);
  cfg.subnet = gPrefs.getUChar("sub", 0);
  for (uint8_t i = 0; i < DMX_NUM_PORTS; ++i) {
    char key[4] = {'u', char('0' + i), 0};
    cfg.universe[i] = gPrefs.getUChar(key, i);
  }
  String name = gPrefs.getString("name", "");
  gPrefs.end();
  if (name.length()) {
    strlcpy(cfg.shortName, name.c_str(), sizeof(cfg.shortName));
    snprintf(cfg.longName, sizeof(cfg.longName), "%s (DMX-Dongle)", cfg.shortName);
  }
}

// ---------- WLAN ----------

void startWifi(const String& ssid, const String& pass) {
  WiFi.persistent(false);
  if (ssid.length()) {
    WiFi.mode(WIFI_STA);
    WiFi.setHostname(gNode.config().shortName);
    WiFi.begin(ssid.c_str(), pass.c_str());
    Serial.printf("[WLAN] Verbinde mit '%s' ...\n", ssid.c_str());
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
  uint8_t mac[6];
  WiFi.macAddress(mac);
  char apName[32];
  snprintf(apName, sizeof(apName), "DMX-Dongle-%02X%02X", mac[4], mac[5]);
  WiFi.mode(WIFI_AP);
  WiFi.softAP(apName, AP_PASSWORD);
  WiFi.setSleep(false);
  Serial.printf("[WLAN] AP '%s' / '%s', IP %s\n", apName, AP_PASSWORD,
                WiFi.softAPIP().toString().c_str());
}

IPAddress localIp() { return gApMode ? WiFi.softAPIP() : WiFi.localIP(); }

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
<button>Speichern &amp; Neustart</button></form>
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
  html.replace("%FW%", String(FW_VERSION >> 8) + "." + String(FW_VERSION & 0xFF));
  html.replace("%FRAMES%", String(gNode.framesReceived()));
  gWeb.send(200, "text/html", html);
}

void handleSave() {
  gPrefs.begin("dmx", false);
  gPrefs.putString("name", gWeb.arg("name"));
  gPrefs.putString("ssid", gWeb.arg("ssid"));
  if (gWeb.arg("pass").length() || !gWeb.arg("ssid").length())
    gPrefs.putString("pass", gWeb.arg("pass"));
  gPrefs.putUChar("net", constrain(gWeb.arg("net").toInt(), 0, 127));
  gPrefs.putUChar("sub", constrain(gWeb.arg("sub").toInt(), 0, 15));
  gPrefs.putUChar("u0", constrain(gWeb.arg("u0").toInt(), 0, 15));
  gPrefs.putUChar("u1", constrain(gWeb.arg("u1").toInt(), 0, 15));
  gPrefs.end();
  gWeb.send(200, "text/html", "<p>Gespeichert, starte neu ...</p>");
  delay(500);
  ESP.restart();
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
    switch (gNode.handlePacket(gRx, static_cast<size_t>(n))) {
      case dmx::PacketResult::PollReceived:
        sendPollReply(gUdp.remoteIP());
        break;
      case dmx::PacketResult::DmxApplied:
        digitalWrite(STATUS_LED, HIGH);
        gLedOffAt = millis() + 30;
        break;
      default:
        break;
    }
  }
}

void checkResetButton() {
  static uint32_t pressedSince = 0;
  if (digitalRead(RESET_BTN) == LOW) {
    if (!pressedSince) pressedSince = millis();
    if (millis() - pressedSince > 3000) {
      gPrefs.begin("dmx", false);
      gPrefs.remove("ssid");
      gPrefs.remove("pass");
      gPrefs.end();
      Serial.println("[RESET] WLAN-Daten geloescht");
      ESP.restart();
    }
  } else {
    pressedSince = 0;
  }
}

}  // namespace

void setup() {
  Serial.begin(115200);
  pinMode(STATUS_LED, OUTPUT);
  pinMode(RESET_BTN, INPUT_PULLUP);

  dmx::NodeConfig cfg;
  String ssid, pass;
  loadConfig(cfg, ssid, pass);
  gNode.setConfig(cfg);

  gPortA.begin("dmxA");
  gPortB.begin("dmxB");

  startWifi(ssid, pass);
  gUdp.begin(artnet::kPort);

  gWeb.on("/", HTTP_GET, handleRoot);
  gWeb.on("/save", HTTP_POST, handleSave);
  gWeb.begin();

  Serial.printf("[DMX] Net %u Sub %u, Universen A=%u B=%u\n", cfg.net, cfg.subnet,
                cfg.universe[0], cfg.universe[1]);
}

void loop() {
  pollUdp();
  gWeb.handleClient();
  checkResetButton();
  if (gLedOffAt && millis() > gLedOffAt) {
    digitalWrite(STATUS_LED, LOW);
    gLedOffAt = 0;
  }
  delay(1);
}
