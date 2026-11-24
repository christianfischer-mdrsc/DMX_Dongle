import 'dart:async';
import 'dart:typed_data';

import '../../services/usb_link.dart';
import '../artnet/artnet_packet.dart';
import 'dmx_transport.dart';

/// Art-Net über WLAN – oder USB, sobald ein Dongle per USB-C verbunden ist.
/// Suche, Ziel-IP usw. bleiben beim Art-Net-Transport.
class HybridTransport implements DmxTransport {
  HybridTransport(this.artnet, this.usb) {
    _subs = [
      artnet.dmxIn.listen(_in.add),
      usb.dmxIn.listen(_in.add),
    ];
  }

  final DmxTransport artnet;
  final UsbLink usb;
  final _in = StreamController<ArtDmxIn>.broadcast();
  late final List<StreamSubscription> _subs;

  bool get viaUsb => usb.isOpen;

  @override
  String? get target => artnet.target;
  @override
  set target(String? v) => artnet.target = v;

  @override
  bool get isOpen => artnet.isOpen || usb.isOpen;

  @override
  Stream<ArtDmxIn> get dmxIn => _in.stream;

  @override
  int get packetsSent => artnet.packetsSent + usb.packetsSent;

  @override
  int get sendErrors => artnet.sendErrors;

  @override
  Future<void> open() => artnet.open();

  @override
  Future<void> close() async {
    await artnet.close();
  }

  @override
  Future<void> reopen() => artnet.reopen();

  @override
  void sendDmx(int portAddress, Uint8List data) {
    if (usb.isOpen) {
      usb.sendDmx(portAddress, data);
    } else {
      artnet.sendDmx(portAddress, data);
    }
  }

  @override
  Future<List<ArtNetNode>> discover({Duration timeout = const Duration(seconds: 2)}) =>
      artnet.discover(timeout: timeout);

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _in.close();
  }
}
