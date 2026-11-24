// Host-Tests für den plattformunabhängigen Kern.
// Bauen & ausführen:  make -C test/host
#include <cassert>
#include <cstdio>
#include <cstring>
#include <vector>

#include "artnet.h"
#include "dmx_node.h"
#include "merger.h"
#include "minijson.h"
#include "usb_proto.h"
#include <string>

struct FakeClock : dmx::IClock {
  uint32_t now = 0;
  uint32_t millis() const override { return now; }
};

struct FakeOutput : dmx::IDmxOutput {
  std::vector<uint8_t> last;
  int writes = 0;
  void write(const uint8_t* d, uint16_t len) override {
    last.assign(d, d + len);
    ++writes;
  }
};

static void testPortAddress() {
  assert(artnet::portAddress(0, 0, 0) == 0);
  assert(artnet::portAddress(0, 0, 1) == 1);
  assert(artnet::portAddress(0, 1, 0) == 16);
  assert(artnet::portAddress(1, 0, 0) == 256);
  assert(artnet::portAddress(127, 15, 15) == 0x7FFF);
}

static void testDmxRoundTrip() {
  uint8_t data[512];
  for (int i = 0; i < 512; ++i) data[i] = static_cast<uint8_t>(i);
  uint8_t buf[600];
  size_t n = artnet::buildDmx(0x0123, 7, data, 512, buf, sizeof(buf));
  assert(n == 18 + 512);
  assert(artnet::opCode(buf, n) == artnet::OpCode::Dmx);
  artnet::DmxPacket p;
  assert(artnet::parseDmx(buf, n, p));
  assert(p.portAddress == 0x0123 && p.sequence == 7 && p.length == 512);
  assert(std::memcmp(p.data, data, 512) == 0);

  // ungerade Länge wird auf gerade aufgerundet
  n = artnet::buildDmx(0, 0, data, 3, buf, sizeof(buf));
  assert(artnet::parseDmx(buf, n, p) && p.length == 4 && p.data[3] == 0);

  // abgeschnittenes Paket wird verworfen
  assert(!artnet::parseDmx(buf, n - 1, p));
  // falscher Header
  buf[0] = 'X';
  assert(artnet::opCode(buf, n) == artnet::OpCode::Unknown);
}

static void testNodeRouting() {
  FakeClock clk;
  FakeOutput a, b;
  dmx::IDmxOutput* outs[] = {&a, &b};
  dmx::DmxNode node(outs, 2, clk);
  dmx::NodeConfig cfg;
  cfg.net = 0; cfg.subnet = 0; cfg.universe[0] = 0; cfg.universe[1] = 5;
  node.setConfig(cfg);

  uint8_t data[4] = {10, 20, 30, 40};
  uint8_t buf[600];
  size_t n = artnet::buildDmx(5, 1, data, 4, buf, sizeof(buf));
  clk.now = 1000;
  assert(node.handlePacket(buf, n) == dmx::PacketResult::DmxApplied);
  assert(a.writes == 0 && b.writes == 1 && b.last[2] == 30);
  assert(node.portActive(1) && !node.portActive(0));

  n = artnet::buildDmx(9, 1, data, 4, buf, sizeof(buf));
  assert(node.handlePacket(buf, n) == dmx::PacketResult::DmxNotForUs);

  clk.now = 5000;
  assert(!node.portActive(1));  // Timeout
}

static void testPollReply() {
  FakeClock clk;
  FakeOutput a;
  dmx::IDmxOutput* outs[] = {&a};
  dmx::DmxNode node(outs, 1, clk);
  uint8_t poll[14] = {'A','r','t','-','N','e','t',0, 0x00,0x20, 0,14, 0,0};
  assert(node.handlePacket(poll, sizeof(poll)) == dmx::PacketResult::PollReceived);

  uint8_t ip[4] = {192, 168, 4, 1};
  uint8_t mac[6] = {1, 2, 3, 4, 5, 6};
  uint8_t buf[300];
  size_t n = node.buildPollReply(ip, mac, 0x0100, buf, sizeof(buf));
  assert(n == artnet::kPollReplySize);
  assert(artnet::opCode(buf, n) == artnet::OpCode::PollReply);
  assert(buf[10] == 192 && buf[13] == 1);
  assert(buf[14] == 0x36 && buf[15] == 0x19);
  assert(std::strcmp(reinterpret_cast<char*>(buf + 26), "DMX-Dongle") == 0);
  assert(buf[173] == 1 && buf[174] == 0x80);
  assert(buf[201] == 1 && buf[206] == 6);
}

// Zwei Steuerungen: letzte Änderung gewinnt, Echo-Übernahme zählt nicht.
static void testMergeTwoControllers() {
  dmx::Merger m;
  uint8_t a[512] = {}, b[512] = {};
  const uint32_t A = 0xC0A80402, B = 0xC0A80403;  // Handy, PC

  a[0] = 100;
  assert(m.apply(A, 6454, a, 512, 0));           // allein: alles übernehmen
  assert(m.data()[0] == 100);

  b[1] = 50;                                      // PC kommt dazu, Startzustand
  assert(!m.apply(B, 6454, b, 512, 10));          // zählt nicht
  assert(m.data()[0] == 100 && m.data()[1] == 0);

  b[1] = 60;                                      // PC ändert Kanal 2
  assert(m.apply(B, 6454, b, 512, 20));
  assert(m.data()[1] == 60 && m.data()[0] == 100);

  assert(!m.apply(A, 6454, a, 512, 30));          // Handy unverändert: stört nicht
  assert(m.data()[1] == 60);

  a[1] = 10;                                      // Handy ändert denselben Kanal
  assert(m.apply(A, 6454, a, 512, 40));
  assert(m.data()[1] == 10);

  // PC übernimmt das Echo (10) und sendet es: keine Änderung
  b[1] = 10;
  assert(!m.apply(B, 6454, b, 512, 60));
  assert(m.data()[1] == 10);

  // Handy fährt schnell (Fader/Effekt), PC folgt verzögert: veraltete Werte ignorieren
  a[0] = 120; m.apply(A, 6454, a, 512, 100);
  a[0] = 130; m.apply(A, 6454, a, 512, 125);
  a[0] = 140; m.apply(A, 6454, a, 512, 150);
  b[0] = 120; assert(!m.apply(B, 6454, b, 512, 160));
  b[0] = 130; assert(!m.apply(B, 6454, b, 512, 185));
  assert(m.data()[0] == 140);

  // Viel später setzt der PC bewusst 120 (alter Handy-Wert, außerhalb des Fensters)
  b[0] = 100; m.apply(B, 6454, b, 512, 3000);
  a[0] = 140; m.apply(A, 6454, a, 512, 3000);   // Handy lebt noch
  assert(m.data()[0] == 100);
  b[0] = 120; assert(m.apply(B, 6454, b, 512, 3100));
  assert(m.data()[0] == 120);

  // Ein einzelner Sender darf schnell hin und her (kein Echo-Filter)
  dmx::Merger s;
  uint8_t c[4] = {10, 0, 0, 0};
  s.apply(A, 6454, c, 4, 0);
  c[0] = 20; s.apply(A, 6454, c, 4, 25);
  c[0] = 10; assert(s.apply(A, 6454, c, 4, 50));
  assert(s.data()[0] == 10);
}

static void testMergeSourcesAndEcho() {
  dmx::Merger m;
  uint8_t d[512] = {};
  uint32_t ids[dmx::kMaxSources];
  uint16_t ports[dmx::kMaxSources];

  m.apply(1, 6454, d, 512, 0);
  m.apply(2, 50000, d, 512, 100);
  assert(m.activeSources(200, ids, ports) == 2);
  assert(ports[1] == 50000);

  assert(m.echoDue(200));                 // erstes Echo sofort
  assert(!m.echoDue(210));                // nichts geändert
  d[5] = 1;
  m.apply(1, 6454, d, 512, 220);
  assert(!m.echoDue(225));                // noch keine 33 ms seit dem letzten
  assert(m.echoDue(240));
  assert(!m.echoDue(500));
  assert(m.echoDue(600));                 // Lebenszeichen nach 0,3 s

  // Sender 2 meldet sich nicht mehr
  m.apply(1, 6454, d, 512, 4000);
  assert(m.activeSources(4200, ids, ports) == 1 && ids[0] == 1);

  // mehr als kMaxSources: ältester fliegt raus, kein Absturz
  for (uint32_t i = 10; i < 20; ++i) m.apply(i, 6454, d, 512, 5000 + i);
  assert(m.activeSources(5100, nullptr, nullptr) == dmx::kMaxSources);
}

static void testNodeEcho() {
  FakeClock clk;
  FakeOutput a;
  dmx::IDmxOutput* outs[] = {&a};
  dmx::DmxNode node(outs, 1, clk);
  dmx::NodeConfig cfg;
  cfg.universe[0] = 0;
  node.setConfig(cfg);
  assert(!node.echoDue(0));               // noch nichts empfangen

  uint8_t data[512] = {};
  uint8_t buf[600];
  data[0] = 255;
  size_t n = artnet::buildDmx(0, 1, data, 512, buf, sizeof(buf));
  clk.now = 100;
  assert(node.handlePacket(buf, n, 0x0A000001, 6454) == dmx::PacketResult::DmxApplied);
  data[0] = 0; data[1] = 77;
  n = artnet::buildDmx(0, 1, data, 512, buf, sizeof(buf));
  clk.now = 120;
  node.handlePacket(buf, n, 0x0A000002, 6454);   // zweiter Sender, Startzustand
  assert(a.last.size() == 512 && a.last[0] == 255 && a.last[1] == 0);
  assert(node.echoDue(0));
  uint32_t ids[4];
  uint16_t ports[4];
  assert(node.echoTargets(0, ids, ports) == 2);
  assert(node.mergedData(0)[0] == 255);
}

struct Got {
  int count = 0;
  uint8_t type = 0;
  std::vector<uint8_t> payload;
};

static void onPacket(void* ctx, uint8_t type, const uint8_t* p, uint16_t len) {
  auto* g = static_cast<Got*>(ctx);
  ++g->count;
  g->type = type;
  g->payload.assign(p, p + len);
}

static void testUsbProto() {
  // Testwert der CRC
  const uint8_t check[] = {'1', '2', '3', '4', '5', '6', '7', '8', '9'};
  assert(usbproto::crc16(check, 9) == 0x29B1);

  uint8_t payload[516] = {};
  payload[0] = 0x01; payload[1] = 0x00;   // Port-Address 1
  payload[2] = 0x00; payload[3] = 0x02;   // 512 Kanäle
  payload[4] = 255; payload[515] = 7;
  uint8_t pkt[600];
  size_t n = usbproto::build(usbproto::kHostDmx, 3, payload, 516, pkt, sizeof(pkt));
  assert(n == 516 + usbproto::kOverhead);

  Got g;
  usbproto::Parser parser(onPacket, &g);
  const char log[] = "[WLAN] Log-Text dazwischen\n\xA5 kein Paket\n";
  parser.feed(reinterpret_cast<const uint8_t*>(log), sizeof(log) - 1);
  parser.feed(pkt, 10);                 // in Stücken, wie über USB
  parser.feed(pkt + 10, n - 10);
  assert(g.count == 1 && g.type == usbproto::kHostDmx && g.payload.size() == 516);
  assert(g.payload[4] == 255 && g.payload[515] == 7);

  pkt[20] ^= 1;                          // kaputtes Paket wird verworfen
  parser.feed(pkt, n);
  assert(g.count == 1 && parser.crcErrors() == 1);

  // leeres Paket (Befehl ohne Nutzdaten)
  n = usbproto::build(usbproto::kGetConfig, 0, nullptr, 0, pkt, sizeof(pkt));
  parser.feed(pkt, n);
  assert(g.count == 2 && g.type == usbproto::kGetConfig && g.payload.empty());

  assert(usbproto::build(usbproto::kInfo, 0, payload, 516, pkt, 100) == 0);  // zu klein
}

static void testMiniJson() {
  const std::string j =
      "{ \"name\": \"B\\u00fchne \\\"1\\\"\", \"wifi\":\"off\", \"u0\": 3, \"en1\":false,"
      " \"ports\":[{\"a\":1},{\"b\":\"}\"}], \"net\":-1, \"pass\":\"a,b}c\" }";
  std::string s;
  long n = 0;
  bool b = true;
  assert(minijson::getString(j, "name", s) && s == "B\xC3\xBChne \"1\"");
  assert(minijson::getString(j, "wifi", s) && s == "off");
  assert(minijson::getInt(j, "u0", n) && n == 3);
  assert(minijson::getBool(j, "en1", b) && !b);
  assert(minijson::getInt(j, "net", n) && n == -1);
  assert(minijson::getString(j, "pass", s) && s == "a,b}c");   // nach verschachteltem Feld
  assert(!minijson::getString(j, "fehlt", s));
  assert(!minijson::getInt(j, "wifi", n));                      // falscher Typ

  std::string out;
  minijson::appendString(out, "a\"b\\c\n");
  assert(out == "\"a\\\"b\\\\c\\n\"");
  std::string obj = "{\"k\":" + out + "}";
  assert(minijson::getString(obj, "k", s) && s == "a\"b\\c\n");  // Hin und zurück
}

int main() {
  testPortAddress();
  testDmxRoundTrip();
  testNodeRouting();
  testPollReply();
  testMergeTwoControllers();
  testMergeSourcesAndEcho();
  testNodeEcho();
  testUsbProto();
  testMiniJson();
  std::puts("Alle Kern-Tests bestanden.");
  return 0;
}
