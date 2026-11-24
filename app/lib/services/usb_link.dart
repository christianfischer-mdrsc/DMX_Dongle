import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/artnet/artnet_packet.dart';
import '../core/usb/usb_proto.dart';

/// Ein angeschlossener USB-Seriell-Chip (CP210x, CH340, CDC).
class UsbDeviceInfo {
  const UsbDeviceInfo(this.deviceId, this.name, this.chip);
  final int deviceId;
  final String name;
  final String chip;

  factory UsbDeviceInfo.fromMap(Map m) => UsbDeviceInfo(
        m['deviceId'] as int,
        (m['name'] as String?) ?? 'USB-Gerät',
        (m['chip'] as String?) ?? '',
      );
}

class UsbException implements Exception {
  UsbException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Verbindung zum Dongle über USB-C (nur Android; Handy ist USB-Host).
///
/// DMX geht dann über USB statt WLAN – das WLAN des Handys bleibt frei fürs Internet.
/// Außerdem lässt sich der Dongle darüber einrichten (Name, WLAN, Ausgänge …).
class UsbLink extends ChangeNotifier {
  UsbLink() {
    _parser = UsbFrameParser(_onPacket, onLog: _onLog);
  }

  static const _method = MethodChannel('dmx_control/usb');
  static const _events = EventChannel('dmx_control/usb/events');
  static const _network = MethodChannel('dmx_control/network');
  static const baud = 921600;

  late final UsbFrameParser _parser;
  StreamSubscription? _sub;
  final _dmx = StreamController<ArtDmxIn>.broadcast();
  final Map<int, Completer<Uint8List>> _waiting = {};
  final List<String> log = [];
  int _seq = 0;
  int _sent = 0;

  /// Beim Einstecken automatisch verbinden.
  bool autoConnect = true;

  List<UsbDeviceInfo> devices = const [];
  UsbDeviceInfo? device;
  String? hello;
  String? error;
  bool busy = false;

  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get isOpen => device != null;
  int get packetsSent => _sent;
  int get packetsReceived => _parser.packets;

  /// Echo des Dongles (gemischter Stand) über den USB-Spiegel.
  Stream<ArtDmxIn> get dmxIn => _dmx.stream;

  Future<void> start() async {
    if (!supported || _sub != null) return;
    _sub = _events.receiveBroadcastStream().listen(_onEvent, onError: (_) {});
    await refresh();
    if (autoConnect && devices.isNotEmpty && !isOpen) {
      await open(devices.first).catchError((_) {});
    }
  }

  Future<List<UsbDeviceInfo>> refresh() async {
    if (!supported) return const [];
    try {
      final list = await _method.invokeListMethod<Map>('list') ?? const [];
      devices = list.map(UsbDeviceInfo.fromMap).toList();
    } on PlatformException catch (e) {
      error = e.message;
    }
    notifyListeners();
    return devices;
  }

  Future<void> open(UsbDeviceInfo d) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final m = await _method.invokeMapMethod<String, dynamic>('open', {'deviceId': d.deviceId, 'baud': baud});
      device = m != null ? UsbDeviceInfo.fromMap(m) : d;
      // DMX geht jetzt über USB: das Handy muss nicht mehr ans Dongle-WLAN gebunden sein
      await _network.invokeMethod('useInternet').catchError((_) {});
    } on PlatformException catch (e) {
      error = e.message ?? e.code;
      device = null;
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> close() async {
    if (!supported) return;
    await _method.invokeMethod('close').catchError((_) {});
    _closed();
  }

  void _closed() {
    if (device == null) return;
    device = null;
    hello = null;
    for (final c in _waiting.values) {
      if (!c.isCompleted) c.completeError(UsbException('USB-Verbindung getrennt'));
    }
    _waiting.clear();
    _network.invokeMethod('useWifi').catchError((_) {});
    notifyListeners();
  }

  void _onEvent(dynamic e) {
    if (e is! Map) return;
    switch (e['type']) {
      case 'data':
        _parser.feed(e['data'] as Uint8List);
      case 'attached':
        refresh().then((list) {
          if (autoConnect && !isOpen && list.isNotEmpty) open(list.first).catchError((_) {});
        });
      case 'detached':
      case 'closed':
        _closed();
        refresh();
    }
  }

  void _onLog(String line) {
    log.add(line);
    if (log.length > 200) log.removeAt(0);
  }

  void _onPacket(int type, Uint8List p) {
    switch (type) {
      case UsbProto.dmx:
        if (p.length < 5) return;
        final pa = p[1] | (p[2] << 8);
        var n = p[3] | (p[4] << 8);
        if (n > p.length - 5) n = p.length - 5;
        _dmx.add(ArtDmxIn(pa, Uint8List.fromList(p.sublist(5, 5 + n)), 'usb'));
      case UsbProto.hello:
        final h = utf8.decode(p, allowMalformed: true);
        if (h != hello) {
          hello = h;
          notifyListeners();
        }
      default:
        final c = _waiting.remove(type);
        if (c != null && !c.isCompleted) c.complete(p);
    }
  }

  Future<void> _write(Uint8List bytes) async {
    if (!isOpen) throw UsbException('Kein Dongle per USB verbunden');
    await _method.invokeMethod('write', bytes);
  }

  /// DMX-Frame senden (vom DmxEngine-Takt, ~40 Hz).
  void sendDmx(int portAddress, Uint8List data) {
    if (!isOpen) return;
    _seq = (_seq + 1) & 0xFF;
    _sent++;
    _write(UsbProto.buildDmx(_seq, portAddress, data)).catchError((_) {});
  }

  Future<Map<String, dynamic>> _request(int type, int answer, {Map<String, dynamic>? json, Duration? timeout}) async {
    final c = Completer<Uint8List>();
    _waiting[answer]?.completeError(UsbException('Abgelöst'));
    _waiting[answer] = c;
    _seq = (_seq + 1) & 0xFF;
    final payload = json == null ? const <int>[] : utf8.encode(jsonEncode(json));
    await _write(UsbProto.build(type, _seq, payload));
    try {
      final p = await c.future.timeout(timeout ?? const Duration(seconds: 3));
      return (jsonDecode(utf8.decode(p, allowMalformed: true)) as Map).cast<String, dynamic>();
    } on TimeoutException {
      _waiting.remove(answer);
      throw UsbException('Der Dongle antwortet nicht. Firmware ab 1.4.0 nötig – älter? Erst per WLAN updaten.');
    } on FormatException {
      throw UsbException('Unverständliche Antwort vom Dongle');
    }
  }

  Future<Map<String, dynamic>> getInfo() => _request(UsbProto.getInfo, UsbProto.info);
  Future<Map<String, dynamic>> getConfig() => _request(UsbProto.getConfig, UsbProto.config);

  /// Nur geänderte Felder schicken. Der Dongle startet danach neu.
  Future<Map<String, dynamic>> setConfig(Map<String, dynamic> changes) =>
      _request(UsbProto.setConfig, UsbProto.result, json: changes);

  Future<List<Map<String, dynamic>>> scanWifi() async {
    final r = await _request(UsbProto.scanWifi, UsbProto.wifiList, timeout: const Duration(seconds: 15));
    return ((r['networks'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _dmx.close();
    super.dispose();
  }
}
