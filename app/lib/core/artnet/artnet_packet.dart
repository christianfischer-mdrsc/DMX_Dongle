import 'dart:convert';
import 'dart:typed_data';

/// Art-Net 4 Pakete (pure Dart, ohne dart:io – auch im Web nutzbar).
class ArtNet {
  static const int port = 6454;
  static const int protocolVersion = 14;
  static const int opPoll = 0x2000;
  static const int opPollReply = 0x2100;
  static const int opDmx = 0x5000;
  static const List<int> _id = [0x41, 0x72, 0x74, 0x2D, 0x4E, 0x65, 0x74, 0x00];

  /// 15-Bit Port-Address aus Net / SubNet / Universe.
  static int portAddress(int net, int subnet, int universe) =>
      ((net & 0x7F) << 8) | ((subnet & 0x0F) << 4) | (universe & 0x0F);

  static Uint8List buildDmx(int portAddress, int sequence, Uint8List data) {
    int len = data.length < 2 ? 2 : (data.length > 512 ? 512 : data.length);
    if (len.isOdd) len++;
    final b = Uint8List(18 + len);
    b.setRange(0, 8, _id);
    b[8] = opDmx & 0xFF;
    b[9] = opDmx >> 8;
    b[10] = 0;
    b[11] = protocolVersion;
    b[12] = sequence & 0xFF;
    b[13] = 0;
    b[14] = portAddress & 0xFF;
    b[15] = (portAddress >> 8) & 0x7F;
    b[16] = len >> 8;
    b[17] = len & 0xFF;
    b.setRange(18, 18 + data.length.clamp(0, 512), data);
    return b;
  }

  static Uint8List buildPoll() {
    final b = Uint8List(14);
    b.setRange(0, 8, _id);
    b[8] = opPoll & 0xFF;
    b[9] = opPoll >> 8;
    b[11] = protocolVersion;
    b[12] = 0x02; // Flags: PollReply bei Änderungen senden
    return b;
  }

  static int? opCode(Uint8List b) {
    if (b.length < 10) return null;
    for (var i = 0; i < 8; i++) {
      if (b[i] != _id[i]) return null;
    }
    return b[8] | (b[9] << 8);
  }

  static ArtNetNode? parsePollReply(Uint8List b) {
    if (b.length < 207 || opCode(b) != opPollReply) return null;
    String str(int off, int len) {
      final raw = b.sublist(off, off + len);
      final end = raw.indexOf(0);
      return latin1.decode(end < 0 ? raw : raw.sublist(0, end)).trim();
    }

    final numPorts = b[173].clamp(0, 4);
    return ArtNetNode(
      ip: '${b[10]}.${b[11]}.${b[12]}.${b[13]}',
      shortName: str(26, 18),
      longName: str(44, 64),
      report: str(108, 64),
      net: b[18] & 0x7F,
      subnet: b[19] & 0x0F,
      outputUniverses: [for (var i = 0; i < numPorts; i++) b[190 + i] & 0x0F],
      mac: List.generate(6, (i) => b[201 + i].toRadixString(16).padLeft(2, '0'))
          .join(':'),
    );
  }
}

class ArtNetNode {
  final String ip;
  final String shortName;
  final String longName;
  final String report;
  final int net;
  final int subnet;
  final List<int> outputUniverses;
  final String mac;

  const ArtNetNode({
    required this.ip,
    required this.shortName,
    required this.longName,
    required this.report,
    required this.net,
    required this.subnet,
    required this.outputUniverses,
    required this.mac,
  });

  /// Port-Adressen, die dieser Node ausgibt.
  List<int> get portAddresses =>
      [for (final u in outputUniverses) ArtNet.portAddress(net, subnet, u)];
}
