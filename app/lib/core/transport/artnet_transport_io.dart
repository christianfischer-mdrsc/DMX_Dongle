import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../artnet/artnet_packet.dart';
import 'dmx_transport.dart';

DmxTransport createTransport() => ArtNetTransportIo();

/// Art-Net über UDP (Android, iOS, Windows, macOS, Linux).
class ArtNetTransportIo implements DmxTransport {
  RawDatagramSocket? _socket;
  final Map<int, int> _seq = {};
  final _replies = StreamController<ArtNetNode>.broadcast();
  int _sent = 0;
  int _errors = 0;

  @override
  String? target;

  @override
  bool get isOpen => _socket != null;

  @override
  int get packetsSent => _sent;

  @override
  int get sendErrors => _errors;

  @override
  Future<void> open() async {
    if (_socket != null) return;
    RawDatagramSocket s;
    try {
      // Port 6454 binden, damit ArtPollReplies ankommen.
      s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, ArtNet.port,
          reuseAddress: true);
    } on SocketException {
      s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    }
    s.broadcastEnabled = true;
    s.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = s.receive();
      if (dg == null) return;
      final node = ArtNet.parsePollReply(dg.data);
      if (node != null) _replies.add(node);
    });
    _socket = s;
  }

  @override
  Future<void> close() async {
    _socket?.close();
    _socket = null;
  }

  @override
  Future<void> reopen() async {
    await close();
    await open();
  }

  void _send(List<int> packet, InternetAddress to) {
    try {
      if (_socket!.send(packet, to, ArtNet.port) > 0) {
        _sent++;
      } else {
        _errors++;
      }
    } on SocketException {
      _errors++;
    }
  }

  InternetAddress get _dest => InternetAddress.tryParse(target ?? '') ??
      InternetAddress('255.255.255.255');

  @override
  void sendDmx(int portAddress, Uint8List data) {
    final s = _socket;
    if (s == null) return;
    final seq = ((_seq[portAddress] ?? 0) % 255) + 1; // 1..255, 0 = aus
    _seq[portAddress] = seq;
    _send(ArtNet.buildDmx(portAddress, seq, data), _dest);
  }

  @override
  Future<List<ArtNetNode>> discover(
      {Duration timeout = const Duration(seconds: 2)}) async {
    // Frischer Socket: hängt sicher am aktuellen Netz (WLAN-Wechsel seit App-Start)
    await reopen();
    final found = <String, ArtNetNode>{};
    final sub = _replies.stream.listen((n) => found[n.ip] = n);
    final poll = ArtNet.buildPoll();
    _send(poll, InternetAddress('255.255.255.255'));
    // Typisches AP-Netz des Dongles zusätzlich direkt anfragen
    _send(poll, InternetAddress('192.168.4.1'));
    if (target != null && InternetAddress.tryParse(target!) != null) {
      _send(poll, InternetAddress(target!));
    }
    await Future.delayed(timeout);
    await sub.cancel();
    return found.values.toList();
  }
}
