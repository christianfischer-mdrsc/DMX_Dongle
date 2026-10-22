// dmx_node.h – Logik eines Art-Net → DMX Nodes, plattformunabhängig.
//
// Nimmt rohe UDP-Payloads entgegen, routet ArtDmx auf die passenden
// Ausgänge und sagt dem Aufrufer, wann ein ArtPollReply fällig ist.
#pragma once
#include <cstdint>

#include "artnet.h"
#include "hal.h"

namespace dmx {

constexpr uint8_t kMaxPorts = 4;

struct NodeConfig {
  uint8_t net = 0;
  uint8_t subnet = 0;
  uint8_t universe[kMaxPorts] = {0, 1, 2, 3};
  char shortName[18] = "DMX-Dongle";
  char longName[64] = "DMX-Dongle Art-Net Node";
};

enum class PacketResult { Ignored, DmxApplied, DmxNotForUs, PollReceived };

class DmxNode {
 public:
  DmxNode(IDmxOutput* const* outputs, uint8_t numOutputs, const IClock& clock);

  void setConfig(const NodeConfig& cfg) { cfg_ = cfg; }
  const NodeConfig& config() const { return cfg_; }
  uint8_t numPorts() const { return numOutputs_; }

  PacketResult handlePacket(const uint8_t* buf, size_t len);

  // Port erhält Daten, wenn der letzte Frame jünger als timeoutMs ist.
  bool portActive(uint8_t port, uint32_t timeoutMs = 3000) const;
  uint32_t framesReceived() const { return frames_; }

  size_t buildPollReply(const uint8_t ip[4], const uint8_t mac[6],
                        uint16_t fwVersion, uint8_t* buf, size_t cap) const;

 private:
  IDmxOutput* const* outputs_;
  uint8_t numOutputs_;
  const IClock& clock_;
  NodeConfig cfg_;
  uint32_t lastFrameMs_[kMaxPorts] = {};
  bool everReceived_[kMaxPorts] = {};
  uint32_t frames_ = 0;
};

}  // namespace dmx
