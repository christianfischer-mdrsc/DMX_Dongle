// Host-Tests für den plattformunabhängigen Kern.
// Bauen & ausführen:  make -C test/host
#include <cassert>
#include <cstdio>
#include <cstring>
#include <vector>

#include "artnet.h"
#include "dmx_node.h"

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

int main() {
  testPortAddress();
  testDmxRoundTrip();
  testNodeRouting();
  testPollReply();
  std::puts("Alle Kern-Tests bestanden.");
  return 0;
}
