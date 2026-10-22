import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../artnet/artnet_packet.dart';
import '../transport/dmx_transport.dart';

/// Herzstück der App: hält alle Kanalwerte, rechnet Fades/Chaser/Grandmaster
/// und schickt die Universen mit ~40 Hz an den Transport.
class DmxEngine extends ChangeNotifier {
  DmxEngine(this.transport, NetworkSettings settings) : _settings = settings {
    _resize();
  }

  final DmxTransport transport;
  NetworkSettings _settings;
  NetworkSettings get settings => _settings;

  static const _tick = Duration(milliseconds: 25);
  static const _keepAliveMs = 800; // Art-Net: Frames regelmäßig wiederholen

  final List<Uint8List> _prog = [];
  final List<Uint8List> _lastSent = [];
  final List<int> _lastSendMs = [];
  final Map<int, Set<int>> _intensity = {}; // vom Grandmaster betroffene Kanäle

  Timer? _timer;
  final Stopwatch _clock = Stopwatch()..start();
  int _tickCount = 0;
  bool _dirtyUi = false;

  double _grandMaster = 1.0;
  bool _blackout = false;

  // Fade
  List<Uint8List>? _fadeFrom;
  List<Uint8List>? _fadeTo;
  int _fadeStart = 0;
  int _fadeMs = 0;

  // Chaser
  Chase? _chase;
  List<Scene?> _chaseScenes = const [];
  int _chaseIndex = 0;
  int _chaseStepStart = 0;

  int get universeCount => _prog.length;
  double get grandMaster => _grandMaster;
  bool get blackout => _blackout;
  String? get activeChaseId => _chase?.id;
  bool get running => _timer != null;

  // ---------- Lebenszyklus ----------

  Future<void> start() async {
    transport.target = _settings.nodeIp;
    await transport.open();
    _timer ??= Timer.periodic(_tick, (_) => _onTick());
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await transport.close();
  }

  void applySettings(NetworkSettings s) {
    _settings = s;
    transport.target = s.nodeIp;
    _resize();
    notifyListeners();
  }

  void _resize() {
    final n = _settings.universeCount.clamp(1, 32);
    while (_prog.length < n) {
      _prog.add(Uint8List(512));
      _lastSent.add(Uint8List(512));
      _lastSendMs.add(-_keepAliveMs);
    }
    while (_prog.length > n) {
      _prog.removeLast();
      _lastSent.removeLast();
      _lastSendMs.removeLast();
    }
  }

  int portAddressFor(int universe) =>
      ArtNet.portAddress(_settings.net, _settings.subnet, _settings.firstUniverse) +
      universe;

  // ---------- Kanäle ----------

  /// ch ist 0-basiert (0..511).
  int getChannel(int universe, int ch) =>
      universe < _prog.length ? _prog[universe][ch] : 0;

  void setChannel(int universe, int ch, int value, {bool notify = true}) {
    if (universe >= _prog.length || ch < 0 || ch > 511) return;
    _cancelFade();
    _prog[universe][ch] = _byte(value);
    if (notify) notifyListeners();
  }

  void setMany(Iterable<(int, int, int)> values) {
    _cancelFade();
    for (final (u, ch, v) in values) {
      if (u < _prog.length && ch >= 0 && ch < 512) _prog[u][ch] = _byte(v);
    }
    notifyListeners();
  }

  void clearAll() {
    stopChase();
    _cancelFade();
    for (final u in _prog) {
      u.fillRange(0, 512, 0);
    }
    notifyListeners();
  }

  Map<int, Uint8List> snapshot() => {
        for (var i = 0; i < _prog.length; i++) i: Uint8List.fromList(_prog[i]),
      };

  void setIntensityChannels(Map<int, Set<int>> map) {
    _intensity
      ..clear()
      ..addAll(map);
  }

  set grandMaster(double v) {
    _grandMaster = v < 0 ? 0.0 : (v > 1 ? 1.0 : v);
    notifyListeners();
  }

  set blackout(bool v) {
    _blackout = v;
    notifyListeners();
  }

  // ---------- Szenen & Fades ----------

  void recallScene(Scene scene, {int? fadeMs}) {
    stopChase(notify: false);
    _startFade(scene, fadeMs ?? scene.fadeMs);
    notifyListeners();
  }

  void _startFade(Scene? scene, int ms) {
    final target = [
      for (var i = 0; i < _prog.length; i++)
        scene?.universes[i] != null
            ? Uint8List.fromList(scene!.universes[i]!)
            : Uint8List(512),
    ];
    if (ms <= 0) {
      for (var i = 0; i < _prog.length; i++) {
        _prog[i].setAll(0, target[i]);
      }
      _cancelFade();
      return;
    }
    _fadeFrom = [for (final u in _prog) Uint8List.fromList(u)];
    _fadeTo = target;
    _fadeStart = _clock.elapsedMilliseconds;
    _fadeMs = ms;
  }

  void _cancelFade() {
    _fadeFrom = null;
    _fadeTo = null;
  }

  void _advanceFade(int now) {
    final from = _fadeFrom, to = _fadeTo;
    if (from == null || to == null) return;
    final t = ((now - _fadeStart) / _fadeMs).clamp(0.0, 1.0);
    for (var u = 0; u < _prog.length && u < from.length; u++) {
      final p = _prog[u], f = from[u], g = to[u];
      for (var c = 0; c < 512; c++) {
        p[c] = (f[c] + (g[c] - f[c]) * t).round();
      }
    }
    _dirtyUi = true;
    if (t >= 1.0) _cancelFade();
  }

  // ---------- Chaser ----------

  void playChase(Chase chase, Map<String, Scene> scenes) {
    if (chase.steps.isEmpty) return;
    _chase = chase;
    _chaseScenes = [for (final s in chase.steps) scenes[s.sceneId]];
    _chaseIndex = 0;
    _enterStep(_clock.elapsedMilliseconds);
    notifyListeners();
  }

  void stopChase({bool notify = true}) {
    if (_chase == null) return;
    _chase = null;
    if (notify) notifyListeners();
  }

  void _enterStep(int now) {
    final step = _chase!.steps[_chaseIndex];
    _chaseStepStart = now;
    _startFade(_chaseScenes[_chaseIndex], step.fadeMs);
  }

  void _advanceChase(int now) {
    final chase = _chase;
    if (chase == null) return;
    final step = chase.steps[_chaseIndex];
    if (now - _chaseStepStart < step.fadeMs + step.holdMs) return;
    _chaseIndex++;
    if (_chaseIndex >= chase.steps.length) {
      if (!chase.loop) {
        stopChase();
        return;
      }
      _chaseIndex = 0;
    }
    _enterStep(now);
  }

  // ---------- Ausgabe ----------

  void _onTick() {
    final now = _clock.elapsedMilliseconds;
    _advanceChase(now);
    _advanceFade(now);

    for (var u = 0; u < _prog.length; u++) {
      final out = _computeOutput(u);
      final changed = !_equals(out, _lastSent[u]);
      if (changed || now - _lastSendMs[u] >= _keepAliveMs) {
        transport.sendDmx(portAddressFor(u), out);
        _lastSent[u] = out;
        _lastSendMs[u] = now;
      }
    }

    // UI während Fades mit ~20 Hz aktualisieren
    if (_dirtyUi && (++_tickCount).isEven) {
      _dirtyUi = false;
      notifyListeners();
    }
  }

  Uint8List _computeOutput(int u) {
    final out = Uint8List.fromList(_prog[u]);
    if (_blackout) {
      final mask = _intensity[u];
      if (mask == null || mask.isEmpty) return Uint8List(512);
      for (final c in mask) {
        out[c] = 0;
      }
      return out;
    }
    if (_grandMaster < 1.0) {
      for (final c in _intensity[u] ?? const <int>{}) {
        out[c] = (out[c] * _grandMaster).round();
      }
    }
    return out;
  }

  /// Wert, der tatsächlich rausgeht (inkl. Grandmaster) – für die Anzeige.
  int outputValue(int u, int ch) {
    var v = getChannel(u, ch);
    if (_intensity[u]?.contains(ch) ?? false) {
      v = _blackout ? 0 : (v * _grandMaster).round();
    }
    return v;
  }

  static int _byte(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);

  static bool _equals(Uint8List a, Uint8List b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _timer?.cancel();
    transport.close();
    super.dispose();
  }
}
