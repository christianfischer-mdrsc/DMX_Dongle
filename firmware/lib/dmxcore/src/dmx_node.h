// dmx_node.h – Logik eines Art-Net → DMX Nodes, plattformunabhängig.
//
// Nimmt rohe UDP-Payloads entgegen, routet ArtDmx auf die passenden
// Ausgänge und sagt dem Aufrufer, wann ein ArtPollReply fällig ist.
#pragma once
#include <cstdint>

#include "artnet.h"
#include "hal.h"
#include "merger.h"

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
  ~DmxNode();
  DmxNode(const DmxNode&) = delete;
  DmxNode& operator=(const DmxNode&) = delete;

  void setConfig(const NodeConfig& cfg) { cfg_ = cfg; }
  const NodeConfig& config() const { return cfg_; }
  uint8_t numPorts() const { return numOutputs_; }

  // sourceId/sourcePort: Absender (z.B. IPv4 als Zahl). Mehrere Absender auf
  // demselben Universe werden gemischt, siehe merger.h.
  PacketResult handlePacket(const uint8_t* buf, size_t len, uint32_t sourceId = 0,
                            uint16_t sourcePort = artnet::kPort);

  // DMX-Daten ohne Art-Net-Hülle (z.B. über USB). Gleiche Mischung wie oben.
  PacketResult applyDmx(uint16_t portAddress, const uint8_t* data, uint16_t length,
                        uint32_t sourceId, uint16_t sourcePort);

  // Echo: gemischten Stand an die Steuerungen zurückschicken.
  bool echoDue(uint8_t port, uint32_t minIntervalMs = 33, uint32_t keepAliveMs = 300);
  const uint8_t* mergedData(uint8_t port) const { return mergers_[port].data(); }
  uint16_t portAddressOf(uint8_t port) const;
  uint8_t echoTargets(uint8_t port, uint32_t* ids, uint16_t* ports) const;
  const Merger& merger(uint8_t port) const { return mergers_[port]; }

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
  Merger* mergers_;
};

}  // namespace dmx
