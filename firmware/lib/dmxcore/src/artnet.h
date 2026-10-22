// artnet.h – Art-Net 4 Paket-Parsing und -Erzeugung (plattformunabhängig).
#pragma once
#include <cstddef>
#include <cstdint>

namespace artnet {

constexpr uint16_t kPort = 6454;  // 0x1936
constexpr uint16_t kProtocolVersion = 14;

enum class OpCode : uint16_t {
  Poll = 0x2000,
  PollReply = 0x2100,
  Dmx = 0x5000,
  Unknown = 0xFFFF,
};

// 15-Bit Port-Address = Net(7) | SubNet(4) | Universe(4)
inline uint16_t portAddress(uint8_t net, uint8_t subnet, uint8_t universe) {
  return static_cast<uint16_t>(((net & 0x7F) << 8) | ((subnet & 0x0F) << 4) |
                               (universe & 0x0F));
}

struct DmxPacket {
  uint8_t sequence;
  uint8_t physical;
  uint16_t portAddress;  // 15 Bit
  uint16_t length;       // 2..512
  const uint8_t* data;   // zeigt in den Empfangspuffer
};

// Prüft Header + liefert OpCode. Unknown bei ungültigem Paket.
OpCode opCode(const uint8_t* buf, size_t len);

// true wenn gültiges ArtDmx.
bool parseDmx(const uint8_t* buf, size_t len, DmxPacket& out);

struct NodeInfo {
  uint8_t ip[4];
  uint8_t mac[6];
  uint8_t net;
  uint8_t subnet;
  uint8_t numPorts;           // 1..4
  uint8_t universe[4];        // Low-Nibble je Port
  bool outputActive[4];       // Daten werden gerade empfangen
  const char* shortName;      // max 17 Zeichen
  const char* longName;       // max 63 Zeichen
  const char* nodeReport;     // max 63 Zeichen
  uint16_t firmwareVersion;
};

constexpr size_t kPollReplySize = 239;

// Schreibt ein ArtPollReply in buf (mind. kPollReplySize Bytes).
size_t buildPollReply(const NodeInfo& info, uint8_t* buf, size_t cap);

// Für Tests / Gegenstelle: ArtDmx erzeugen.
size_t buildDmx(uint16_t portAddress, uint8_t sequence, const uint8_t* data,
                uint16_t length, uint8_t* buf, size_t cap);

}  // namespace artnet
