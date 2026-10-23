import 'dart:typed_data';

import '../artnet/artnet_packet.dart';
import 'dmx_transport.dart';

/// Platzhalter für Plattformen ohne dart:io (Web). Sendet nichts.
DmxTransport createTransport() => _NullTransport();

class _NullTransport implements DmxTransport {
  @override
  String? target;
  @override
  bool get isOpen => false;
  @override
  int get packetsSent => 0;
  @override
  int get sendErrors => 0;
  @override
  Future<void> open() async {}
  @override
  Future<void> close() async {}
  @override
  Future<void> reopen() async {}
  @override
  void sendDmx(int portAddress, Uint8List data) {}
  @override
  Future<List<ArtNetNode>> discover(
          {Duration timeout = const Duration(seconds: 2)}) async =>
      const [];
}
