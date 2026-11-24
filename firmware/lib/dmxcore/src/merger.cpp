#include "merger.h"

#include <cstring>

namespace dmx {

Merger::Merger() {
  std::memset(owner_, kNone, sizeof(owner_));
  std::memset(histOwner_, kNone, sizeof(histOwner_));
}

int8_t Merger::slotOf(uint32_t sourceId) const {
  for (uint8_t i = 0; i < kMaxSources; ++i)
    if (sources_[i].used && sources_[i].id == sourceId) return static_cast<int8_t>(i);
  return -1;
}

bool Merger::isEcho(uint16_t ch, uint8_t value, uint8_t slot, uint32_t now) const {
  const uint16_t t = static_cast<uint16_t>(now >> 3);
  for (uint8_t i = 0; i < kMergeHistory; ++i) {
    const uint8_t o = histOwner_[ch][i];
    if (o == kNone || o == slot || histValue_[ch][i] != value) continue;
    const uint16_t age = static_cast<uint16_t>(t - histTime_[ch][i]);
    if (static_cast<uint32_t>(age) * 8 < kEchoWindowMs) return true;
  }
  return false;
}

void Merger::set(uint16_t ch, uint8_t value, uint8_t slot, uint32_t now) {
  uint8_t& pos = histPos_[ch];
  histValue_[ch][pos] = value;
  histOwner_[ch][pos] = slot;
  histTime_[ch][pos] = static_cast<uint16_t>(now >> 3);
  pos = static_cast<uint8_t>((pos + 1) % kMergeHistory);
  if (merged_[ch] != value) dirty_ = true;
  merged_[ch] = value;
  owner_[ch] = slot;
}

bool Merger::apply(uint32_t sourceId, uint16_t sourcePort, const uint8_t* data,
                   uint16_t length, uint32_t now) {
  if (length > kUniverseSize) length = kUniverseSize;
  const bool wasDirty = dirty_;
  dirty_ = false;

  // Sender suchen oder einen Platz belegen (frei, abgelaufen oder ältester)
  int8_t slot = slotOf(sourceId);
  bool fresh = false;
  if (slot < 0 || !alive(sources_[slot], now)) {
    if (slot < 0) {
      uint8_t best = 0;
      for (uint8_t i = 0; i < kMaxSources; ++i) {
        if (!alive(sources_[i], now)) {
          best = i;
          break;
        }
        if (sources_[i].lastSeenMs < sources_[best].lastSeenMs) best = i;
      }
      slot = static_cast<int8_t>(best);
      // Kanäle des verdrängten Senders behalten ihren Wert, gehören aber niemandem mehr
      for (uint16_t c = 0; c < kUniverseSize; ++c)
        if (owner_[c] == best) owner_[c] = kNone;
    }
    fresh = true;
  }
  Source& s = sources_[slot];

  bool othersAlive = false;
  for (uint8_t i = 0; i < kMaxSources; ++i)
    if (i != slot && alive(sources_[i], now)) othersAlive = true;

  s.id = sourceId;
  s.port = sourcePort;
  s.lastSeenMs = now;
  s.used = true;
  const uint8_t me = static_cast<uint8_t>(slot);

  if (fresh) {
    std::memcpy(s.last, data, length);
    if (length < kUniverseSize) std::memset(s.last + length, 0, kUniverseSize - length);
    // Allein: alles übernehmen (wie ein normaler Node).
    // Andere steuern schon: erst echte Änderungen zählen, sonst würde der
    // Neue mit seinem Startzustand alles überschreiben.
    if (!othersAlive)
      for (uint16_t c = 0; c < length; ++c) set(c, data[c], me, now);
  } else {
    for (uint16_t c = 0; c < length; ++c) {
      const uint8_t v = data[c];
      if (v == s.last[c]) continue;
      s.last[c] = v;
      if (v == merged_[c]) continue;  // folgt nur dem aktuellen Stand
      if (othersAlive && isEcho(c, v, me, now)) continue;
      set(c, v, me, now);
    }
  }

  const bool changed = dirty_;
  dirty_ = wasDirty || changed;  // für das Echo merken
  return changed;
}

uint8_t Merger::activeSources(uint32_t now, uint32_t* ids, uint16_t* ports) const {
  uint8_t n = 0;
  for (uint8_t i = 0; i < kMaxSources; ++i) {
    if (!alive(sources_[i], now)) continue;
    if (ids) ids[n] = sources_[i].id;
    if (ports) ports[n] = sources_[i].port;
    ++n;
  }
  return n;
}

bool Merger::echoDue(uint32_t now, uint32_t minIntervalMs, uint32_t keepAliveMs) {
  const uint32_t since = now - lastEchoMs_;
  const bool due = !echoedOnce_ || (dirty_ && since >= minIntervalMs) || since >= keepAliveMs;
  if (!due) return false;
  lastEchoMs_ = now;
  echoedOnce_ = true;
  dirty_ = false;
  return true;
}

}  // namespace dmx
