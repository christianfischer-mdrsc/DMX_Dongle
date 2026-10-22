#include "dmx_node.h"

#include <cstdio>

namespace dmx {

DmxNode::DmxNode(IDmxOutput* const* outputs, uint8_t numOutputs,
                 const IClock& clock)
    : outputs_(outputs),
      numOutputs_(numOutputs > kMaxPorts ? kMaxPorts : numOutputs),
      clock_(clock) {}

PacketResult DmxNode::handlePacket(const uint8_t* buf, size_t len) {
  switch (artnet::opCode(buf, len)) {
    case artnet::OpCode::Poll:
      return PacketResult::PollReceived;

    case artnet::OpCode::Dmx: {
      artnet::DmxPacket pkt;
      if (!artnet::parseDmx(buf, len, pkt)) return PacketResult::Ignored;
      bool applied = false;
      for (uint8_t p = 0; p < numOutputs_; ++p) {
        uint16_t addr = artnet::portAddress(cfg_.net, cfg_.subnet, cfg_.universe[p]);
        if (addr != pkt.portAddress) continue;
        outputs_[p]->write(pkt.data, pkt.length);
        lastFrameMs_[p] = clock_.millis();
        everReceived_[p] = true;
        applied = true;
      }
      if (applied) ++frames_;
      return applied ? PacketResult::DmxApplied : PacketResult::DmxNotForUs;
    }

    default:
      return PacketResult::Ignored;
  }
}

bool DmxNode::portActive(uint8_t port, uint32_t timeoutMs) const {
  if (port >= numOutputs_ || !everReceived_[port]) return false;
  return (clock_.millis() - lastFrameMs_[port]) < timeoutMs;
}

size_t DmxNode::buildPollReply(const uint8_t ip[4], const uint8_t mac[6],
                               uint16_t fwVersion, uint8_t* buf,
                               size_t cap) const {
  artnet::NodeInfo info{};
  for (int i = 0; i < 4; ++i) info.ip[i] = ip[i];
  for (int i = 0; i < 6; ++i) info.mac[i] = mac[i];
  info.net = cfg_.net;
  info.subnet = cfg_.subnet;
  info.numPorts = numOutputs_;
  for (uint8_t p = 0; p < numOutputs_; ++p) {
    info.universe[p] = cfg_.universe[p];
    info.outputActive[p] = portActive(p);
  }
  char report[64];
  std::snprintf(report, sizeof(report), "#0001 [%04lu] OK",
                static_cast<unsigned long>(frames_ % 10000));
  info.shortName = cfg_.shortName;
  info.longName = cfg_.longName;
  info.nodeReport = report;
  info.firmwareVersion = fwVersion;
  return artnet::buildPollReply(info, buf, cap);
}

}  // namespace dmx
