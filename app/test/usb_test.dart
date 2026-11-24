import 'dart:convert';
import 'dart:typed_data';

import 'package:dmx_control/core/usb/usb_proto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CRC wie in der Firmware', () {
    expect(UsbProto.crc16(ascii.encode('123456789')), 0x29B1);
  });

  test('Pakete und Log-Text werden getrennt', () {
    final got = <(int, Uint8List)>[];
    final logs = <String>[];
    final parser = UsbFrameParser((t, p) => got.add((t, p)), onLog: logs.add);

    final cfg = UsbProto.build(UsbProto.config, 7, utf8.encode('{"name":"Bühne"}'));
    final dmx = Uint8List(5 + 512)
      ..[0] = 0
      ..[1] = 1 // Port-Address 1
      ..[3] = 0
      ..[4] = 2 // 512
      ..[5] = 200;
    final mirror = UsbProto.build(UsbProto.dmx, 8, dmx);

    final stream = <int>[
      ...ascii.encode('[WLAN] aus\n'),
      ...cfg.sublist(0, 5),
      ...cfg.sublist(5),
      ...ascii.encode('[USB] ok\r\n'),
      ...mirror,
    ];
    // in kleinen Stücken wie über USB
    for (var i = 0; i < stream.length; i += 37) {
      parser.feed(stream.sublist(i, i + 37 > stream.length ? stream.length : i + 37));
    }
    expect(logs, ['[WLAN] aus', '[USB] ok']);
    expect(got.length, 2);
    expect(got[0].$1, UsbProto.config);
    expect(jsonDecode(utf8.decode(got[0].$2))['name'], 'Bühne');
    expect(got[1].$1, UsbProto.dmx);
    expect(got[1].$2[5], 200);

    final broken = Uint8List.fromList(cfg)..[8] ^= 1;
    parser.feed(broken);
    expect(got.length, 2);
    expect(parser.crcErrors, 1);
  });

  test('DMX an den Dongle', () {
    final data = Uint8List(512)..[0] = 255;
    final pkt = UsbProto.buildDmx(1, 0x0012, data);
    final got = <(int, Uint8List)>[];
    UsbFrameParser((t, p) => got.add((t, p))).feed(pkt);
    expect(got.single.$1, UsbProto.hostDmx);
    final p = got.single.$2;
    expect(p[0] | (p[1] << 8), 0x12);
    expect(p[2] | (p[3] << 8), 512);
    expect(p[4], 255);
  });
}
