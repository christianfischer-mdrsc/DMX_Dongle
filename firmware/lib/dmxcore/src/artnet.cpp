#include "artnet.h"

#include <cstring>

namespace artnet {
namespace {

const uint8_t kId[8] = {'A', 'r', 't', '-', 'N', 'e', 't', 0};
constexpr size_t kDmxHeader = 18;

void copyStr(uint8_t* dst, size_t cap, const char* src) {
  std::memset(dst, 0, cap);
  if (!src) return;
  size_t n = std::strlen(src);
  if (n > cap - 1) n = cap - 1;
  std::memcpy(dst, src, n);
}

}  // namespace

OpCode opCode(const uint8_t* buf, size_t len) {
  if (len < 10 || std::memcmp(buf, kId, 8) != 0) return OpCode::Unknown;
  uint16_t op = static_cast<uint16_t>(buf[8] | (buf[9] << 8));  // little endian
  switch (op) {
    case 0x2000: return OpCode::Poll;
    case 0x2100: return OpCode::PollReply;
    case 0x5000: return OpCode::Dmx;
    default:     return OpCode::Unknown;
  }
}

bool parseDmx(const uint8_t* buf, size_t len, DmxPacket& out) {
  if (len < kDmxHeader + 2 || opCode(buf, len) != OpCode::Dmx) return false;
  uint16_t ver = static_cast<uint16_t>((buf[10] << 8) | buf[11]);
  if (ver < kProtocolVersion) return false;
  uint16_t length = static_cast<uint16_t>((buf[16] << 8) | buf[17]);
  if (length < 2 || length > 512) return false;
  if (len < kDmxHeader + length) return false;
  out.sequence = buf[12];
  out.physical = buf[13];
  out.portAddress = static_cast<uint16_t>(buf[14] | ((buf[15] & 0x7F) << 8));
  out.length = length;
  out.data = buf + kDmxHeader;
  return true;
}

size_t buildPollReply(const NodeInfo& info, uint8_t* buf, size_t cap) {
  if (cap < kPollReplySize) return 0;
  std::memset(buf, 0, kPollReplySize);
  std::memcpy(buf, kId, 8);
  buf[8] = 0x00;  // OpPollReply = 0x2100, little endian
  buf[9] = 0x21;
  std::memcpy(buf + 10, info.ip, 4);
  buf[14] = kPort & 0xFF;  // Port little endian
  buf[15] = kPort >> 8;
  buf[16] = info.firmwareVersion >> 8;
  buf[17] = info.firmwareVersion & 0xFF;
  buf[18] = info.net & 0x7F;
  buf[19] = info.subnet & 0x0F;
  buf[20] = 0x00;  // OEM hi  (0x0000 = unbekannt/Eigenbau)
  buf[21] = 0x00;  // OEM lo
  buf[22] = 0;     // UBEA
  buf[23] = 0xD0;  // Status1: Indikatoren normal, Port-Adresse per Netzwerk
  buf[24] = 0;     // ESTA lo
  buf[25] = 0;     // ESTA hi
  copyStr(buf + 26, 18, info.shortName);
  copyStr(buf + 44, 64, info.longName);
  copyStr(buf + 108, 64, info.nodeReport);
  uint8_t ports = info.numPorts > 4 ? 4 : info.numPorts;
  buf[172] = 0;
  buf[173] = ports;
  for (uint8_t i = 0; i < ports; ++i) {
    buf[174 + i] = 0x80;                                // kann DMX ausgeben
    buf[182 + i] = info.outputActive[i] ? 0x80 : 0x00;  // GoodOutput
    buf[190 + i] = info.universe[i] & 0x0F;             // SwOut
  }
  buf[200] = 0x00;  // Style: StNode
  std::memcpy(buf + 201, info.mac, 6);
  std::memcpy(buf + 207, info.ip, 4);  // BindIp
  buf[211] = 1;                        // BindIndex
  buf[212] = 0x08;                     // Status2: Art-Net 4 / 15-Bit Port-Adresse
  return kPollReplySize;
}

size_t buildDmx(uint16_t portAddress, uint8_t sequence, const uint8_t* data,
                uint16_t length, uint8_t* buf, size_t cap) {
  if (length > 512) length = 512;
  uint16_t sendLen = static_cast<uint16_t>((length + 1) & ~1);  // gerade Länge
  if (sendLen < 2) sendLen = 2;
  if (cap < kDmxHeader + sendLen) return 0;
  std::memcpy(buf, kId, 8);
  buf[8] = 0x00;
  buf[9] = 0x50;
  buf[10] = 0;
  buf[11] = kProtocolVersion;
  buf[12] = sequence;
  buf[13] = 0;
  buf[14] = portAddress & 0xFF;
  buf[15] = (portAddress >> 8) & 0x7F;
  buf[16] = sendLen >> 8;
  buf[17] = sendLen & 0xFF;
  std::memset(buf + kDmxHeader, 0, sendLen);
  std::memcpy(buf + kDmxHeader, data, length);
  return kDmxHeader + sendLen;
}

}  // namespace artnet
