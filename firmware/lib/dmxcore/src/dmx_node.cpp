#include "dmx_node.h"

#include <cstdio>

namespace dmx {

DmxNode::DmxNode(IDmxOutput* const* outputs, uint8_t numOutputs,
                 const IClock& clock)
    : outputs_(outputs),
      numOutputs_(numOutputs > kMaxPorts ? kMaxPorts : numOutputs),
      clock_(clock),
      mergers_(new Merger[numOutputs_ ? numOutputs_ : 1]) {}

DmxNode::~DmxNode() { delete[] mergers_; }

uint16_t DmxNode::portAddressOf(uint8_t port) const {
  return artnet::portAddress(cfg_.net, cfg_.subnet, cfg_.universe[port]);
}

bool DmxNode::echoDue(uint8_t port, uint32_t minIntervalMs, uint32_t keepAliveMs) {
  if (port >= numOutputs_ || !everReceived_[port]) return false;
  const uint32_t now = clock_.millis();
  if (mergers_[port].activeSources(now, nullptr, nullptr) == 0) return false;
  return mergers_[port].echoDue(now, minIntervalMs, keepAliveMs);
}

uint8_t DmxNode::echoTargets(uint8_t port, uint32_t* ids, uint16_t* ports) const {
  if (port >= numOutputs_) return 0;
  return mergers_[port].activeSources(clock_.millis(), ids, ports);
}

PacketResult DmxNode::handlePacket(const uint8_t* buf, size_t len,
                                   uint32_t sourceId, uint16_t sourcePort) {
  switch (artnet::opCode(buf, len)) {
    case artnet::OpCode::Poll:
      return PacketResult::PollReceived;

    case artnet::OpCode::Dmx: {
      artnet::DmxPacket pkt;
      if (!artnet::parseDmx(buf, len, pkt)) return PacketResult::Ignored;
      return applyDmx(pkt.portAddress, pkt.data, pkt.length, sourceId, sourcePort);
    }

    default:
      return PacketResult::Ignored;
  }
}

PacketResult DmxNode::applyDmx(uint16_t portAddress, const uint8_t* data, uint16_t length,
                               uint32_t sourceId, uint16_t sourcePort) {
  bool applied = false;
  for (uint8_t p = 0; p < numOutputs_; ++p) {
    if (portAddressOf(p) != portAddress) continue;
    const uint32_t now = clock_.millis();
    mergers_[p].apply(sourceId, sourcePort, data, length, now);
    outputs_[p]->write(mergers_[p].data(), kUniverseSize);
    lastFrameMs_[p] = now;
    everReceived_[p] = true;
    applied = true;
  }
  if (applied) ++frames_;
  return applied ? PacketResult::DmxApplied : PacketResult::DmxNotForUs;
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
