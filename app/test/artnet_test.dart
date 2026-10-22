import 'dart:typed_data';

import 'package:dmx_control/core/artnet/artnet_packet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Port-Address', () {
    expect(ArtNet.portAddress(0, 0, 1), 1);
    expect(ArtNet.portAddress(0, 1, 0), 16);
    expect(ArtNet.portAddress(1, 0, 0), 256);
  });

  test('ArtDmx Header', () {
    final data = Uint8List(512)..[0] = 255;
    final p = ArtNet.buildDmx(0x0102, 5, data);
    expect(p.length, 18 + 512);
    expect(ArtNet.opCode(p), ArtNet.opDmx);
    expect(p[11], 14); // Protokollversion
    expect(p[12], 5); // Sequence
    expect(p[14], 0x02); // SubUni
    expect(p[15], 0x01); // Net
    expect((p[16] << 8) | p[17], 512);
    expect(p[18], 255);
  });

  test('ungerade Länge wird aufgerundet', () {
    final p = ArtNet.buildDmx(0, 1, Uint8List.fromList([1, 2, 3]));
    expect((p[16] << 8) | p[17], 4);
  });

  test('PollReply parsen', () {
    final b = Uint8List(239);
    b.setAll(0, 'Art-Net'.codeUnits);
    b[8] = 0x00;
    b[9] = 0x21;
    b.setAll(10, [192, 168, 4, 1]);
    b.setAll(26, 'DMX-Dongle'.codeUnits);
    b[173] = 2;
    b[190] = 0;
    b[191] = 1;
    final n = ArtNet.parsePollReply(b)!;
    expect(n.ip, '192.168.4.1');
    expect(n.shortName, 'DMX-Dongle');
    expect(n.outputUniverses, [0, 1]);
  });
}
