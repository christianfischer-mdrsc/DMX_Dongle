#include "usb_proto.h"

#include <cstring>

namespace usbproto {

uint16_t crc16(const uint8_t* d, size_t n, uint16_t crc) {
  while (n--) {
    crc ^= static_cast<uint16_t>(*d++) << 8;
    for (int i = 0; i < 8; ++i)
      crc = (crc & 0x8000) ? static_cast<uint16_t>((crc << 1) ^ 0x1021)
                           : static_cast<uint16_t>(crc << 1);
  }
  return crc;
}

size_t build(uint8_t type, uint8_t seq, const uint8_t* payload, uint16_t len, uint8_t* out,
             size_t cap) {
  if (len > kMaxPayload || cap < kOverhead + len) return 0;
  out[0] = kSync0;
  out[1] = kSync1;
  out[2] = type;
  out[3] = seq;
  out[4] = static_cast<uint8_t>(len & 0xFF);
  out[5] = static_cast<uint8_t>(len >> 8);
  if (len) std::memcpy(out + 6, payload, len);
  const uint16_t c = crc16(out + 2, 4 + len);
  out[6 + len] = static_cast<uint8_t>(c & 0xFF);
  out[7 + len] = static_cast<uint8_t>(c >> 8);
  return kOverhead + len;
}

void Parser::feed(const uint8_t* data, size_t len) {
  for (size_t i = 0; i < len; ++i) step(data[i]);
}

void Parser::step(uint8_t b) {
  switch (state_) {
    case State::Idle:
      if (b == kSync0) state_ = State::Sync;
      break;
    case State::Sync:
      if (b == kSync1) {
        state_ = State::Header;
        hdrPos_ = 0;
      } else if (b != kSync0) {
        state_ = State::Idle;
      }
      break;
    case State::Header:
      hdr_[hdrPos_++] = b;
      if (hdrPos_ == 4) {
        len_ = static_cast<uint16_t>(hdr_[2] | (hdr_[3] << 8));
        pos_ = 0;
        crcPos_ = 0;
        if (len_ > kMaxPayload) state_ = State::Idle;
        else state_ = len_ ? State::Payload : State::Crc;
      }
      break;
    case State::Payload:
      buf_[pos_++] = b;
      if (pos_ == len_) state_ = State::Crc;
      break;
    case State::Crc:
      crc_[crcPos_++] = b;
      if (crcPos_ == 2) {
        state_ = State::Idle;
        uint16_t c = crc16(hdr_, 4);
        c = crc16(buf_, len_, c);
        if (c == static_cast<uint16_t>(crc_[0] | (crc_[1] << 8))) {
          ++packets_;
          if (handler_) handler_(ctx_, hdr_[0], buf_, len_);
        } else {
          ++crcErrors_;
        }
      }
      break;
  }
}

}  // namespace usbproto
