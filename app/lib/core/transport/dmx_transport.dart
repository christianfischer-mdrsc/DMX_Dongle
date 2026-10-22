import 'dart:typed_data';

import '../artnet/artnet_packet.dart';
import 'transport_stub.dart'
    if (dart.library.io) 'artnet_transport_io.dart' as impl;

/// Abstraktion des Wegs zum Dongle.
///
/// Android/iOS/Desktop: Art-Net über UDP (dart:io).
/// Web: Browser können kein UDP – dort kommt später ein WebSocket-Transport
/// (Firmware stellt dann zusätzlich einen WS-Endpunkt bereit).
abstract class DmxTransport {
  Future<void> open();
  Future<void> close();
  bool get isOpen;

  /// Ziel: IP des Nodes, oder null = Broadcast.
  String? target;

  /// Sendet einen kompletten Universe-Frame (bis 512 Byte).
  void sendDmx(int portAddress, Uint8List data);

  /// Sucht Nodes per ArtPoll.
  Future<List<ArtNetNode>> discover(
      {Duration timeout = const Duration(seconds: 2)});

  int get packetsSent;

  factory DmxTransport.create() => impl.createTransport();
}
