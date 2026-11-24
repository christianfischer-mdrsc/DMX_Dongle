import 'dart:typed_data';

/// Paketformat zwischen App und Dongle über USB (siehe firmware/lib/dmxcore/src/usb_proto.h).
///
///   A5 5A | Typ | Seq | Länge (2, LE) | Nutzdaten | CRC16 (2, LE)
///
/// Alles außerhalb gültiger Pakete ist Log-Text der Firmware.
class UsbProto {
  static const int sync0 = 0xA5;
  static const int sync1 = 0x5A;
  static const int maxPayload = 1536;

  // Dongle → App
  static const int dmx = 0x01; // Port | Port-Address (2) | Anzahl (2) | Daten
  static const int hello = 0x02;
  static const int status = 0x03;
  static const int config = 0x21;
  static const int result = 0x23;
  static const int info = 0x25;
  static const int wifiList = 0x27;
  // App → Dongle
  static const int hostDmx = 0x10; // Port-Address (2) | Anzahl (2) | Daten
  static const int getConfig = 0x20;
  static const int setConfig = 0x22;
  static const int getInfo = 0x24;
  static const int scanWifi = 0x26;

  static int crc16(List<int> data, [int start = 0, int? end, int crc = 0xFFFF]) {
    final e = end ?? data.length;
    for (var i = start; i < e; i++) {
      crc ^= (data[i] & 0xFF) << 8;
      for (var b = 0; b < 8; b++) {
        crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) & 0xFFFF : (crc << 1) & 0xFFFF;
      }
    }
    return crc;
  }

  static Uint8List build(int type, int seq, List<int> payload) {
    final n = payload.length;
    final b = Uint8List(8 + n);
    b[0] = sync0;
    b[1] = sync1;
    b[2] = type;
    b[3] = seq & 0xFF;
    b[4] = n & 0xFF;
    b[5] = n >> 8;
    b.setRange(6, 6 + n, payload);
    final c = crc16(b, 2, 6 + n);
    b[6 + n] = c & 0xFF;
    b[7 + n] = c >> 8;
    return b;
  }

  /// DMX-Frame für den Dongle (wie ArtDmx, nur über USB).
  static Uint8List buildDmx(int seq, int portAddress, Uint8List data) {
    final n = data.length > 512 ? 512 : data.length;
    final p = Uint8List(4 + n);
    p[0] = portAddress & 0xFF;
    p[1] = (portAddress >> 8) & 0x7F;
    p[2] = n & 0xFF;
    p[3] = n >> 8;
    p.setRange(4, 4 + n, data);
    return build(hostDmx, seq, p);
  }
}

typedef UsbPacketHandler = void Function(int type, Uint8List payload);

/// Zerlegt den Byte-Strom vom Dongle in Pakete und Log-Zeilen.
class UsbFrameParser {
  UsbFrameParser(this.onPacket, {this.onLog});
  final UsbPacketHandler onPacket;
  final void Function(String line)? onLog;

  int _state = 0; // 0 frei, 1 Sync, 2 Kopf, 3 Daten, 4 CRC
  final _hdr = Uint8List(4);
  int _hdrPos = 0;
  int _len = 0, _pos = 0;
  Uint8List _buf = Uint8List(UsbProto.maxPayload);
  final _crc = Uint8List(2);
  int _crcPos = 0;
  final _text = <int>[];
  int packets = 0, crcErrors = 0;

  void feed(List<int> data) {
    for (final b in data) {
      _step(b & 0xFF);
    }
  }

  void _textByte(int b) {
    if (onLog == null) return;
    if (b == 0x0A) {
      if (_text.isNotEmpty) onLog!(String.fromCharCodes(_text).trimRight());
      _text.clear();
    } else if (b != 0x0D && _text.length < 300) {
      _text.add(b);
    }
  }

  void _step(int b) {
    switch (_state) {
      case 0:
        if (b == UsbProto.sync0) {
          _state = 1;
        } else {
          _textByte(b);
        }
      case 1:
        if (b == UsbProto.sync1) {
          _state = 2;
          _hdrPos = 0;
        } else if (b != UsbProto.sync0) {
          _state = 0;
        }
      case 2:
        _hdr[_hdrPos++] = b;
        if (_hdrPos == 4) {
          _len = _hdr[2] | (_hdr[3] << 8);
          _pos = 0;
          _crcPos = 0;
          if (_len > UsbProto.maxPayload) {
            _state = 0;
          } else {
            if (_buf.length < _len) _buf = Uint8List(_len);
            _state = _len == 0 ? 4 : 3;
          }
        }
      case 3:
        _buf[_pos++] = b;
        if (_pos == _len) _state = 4;
      case 4:
        _crc[_crcPos++] = b;
        if (_crcPos == 2) {
          _state = 0;
          var c = UsbProto.crc16(_hdr);
          c = UsbProto.crc16(_buf, 0, _len, c);
          if (c == (_crc[0] | (_crc[1] << 8))) {
            packets++;
            onPacket(_hdr[0], Uint8List.fromList(_buf.sublist(0, _len)));
          } else {
            crcErrors++;
          }
        }
    }
  }
}
