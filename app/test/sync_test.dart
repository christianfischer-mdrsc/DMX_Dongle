import 'dart:typed_data';

import 'package:dmx_control/core/artnet/artnet_packet.dart';
import 'package:dmx_control/core/dmx/dmx_engine.dart';
import 'package:dmx_control/core/transport/dmx_transport.dart';
import 'package:dmx_control/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ArtDmx vom Dongle wird gelesen', () {
    final data = Uint8List(512)..[3] = 99;
    final pkt = ArtNet.buildDmx(1, 5, data);
    final d = ArtNet.parseDmx(pkt, '192.168.4.1')!;
    expect(d.portAddress, 1);
    expect(d.data.length, 512);
    expect(d.data[3], 99);
    expect(d.from, '192.168.4.1');
    expect(ArtNet.parseDmx(ArtNet.buildPoll(), 'x'), isNull);
  });

  test('Änderungen anderer Steuerungen landen in den Fadern', () {
    final engine = DmxEngine(DmxTransport.create(), NetworkSettings());
    final echo = Uint8List(512)..[0] = 200..[7] = 42;
    engine.applyRemote(0, echo);
    expect(engine.getChannel(0, 0), 200);
    expect(engine.getChannel(0, 7), 42);
    expect(engine.remoteChanges, 2);
  });

  test('Eigene frische Änderung wird nicht vom alten Echo überschrieben', () {
    final engine = DmxEngine(DmxTransport.create(), NetworkSettings());
    engine.setChannel(0, 0, 255);
    engine.applyRemote(0, Uint8List(512)..[0] = 10..[1] = 20);
    expect(engine.getChannel(0, 0), 255); // eben selbst gesetzt
    expect(engine.getChannel(0, 1), 20); // anderer Kanal kommt durch
  });

  test('Grandmaster wird herausgerechnet', () {
    final engine = DmxEngine(DmxTransport.create(), NetworkSettings());
    engine.setIntensityChannels({0: {0}});
    engine.grandMaster = 0.5;
    engine.applyRemote(0, Uint8List(512)..[0] = 100);
    expect(engine.getChannel(0, 0), 200);
    expect(engine.outputValue(0, 0), 100);
  });
}
