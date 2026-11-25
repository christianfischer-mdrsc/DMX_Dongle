import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../artnet/artnet_packet.dart';
import '../transport/dmx_transport.dart';
import 'effects.dart';

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

  // Live-Abgleich mit anderen Steuerungen (Echo des Dongles)
  final List<Int32List> _localChangeMs = []; // wann der Kanal hier zuletzt geändert wurde
  final List<Set<int>> _adopted = []; // im aktuellen Takt vom Dongle übernommen
  StreamSubscription<ArtDmxIn>? _echoSub;
  int _remoteChanges = 0;

  /// Ignoriert Echos für einen Kanal so lange nach einer eigenen Änderung
  /// (das Echo kann noch den alten Stand enthalten).
  static const _echoGuardMs = 600;

  /// Live-Abgleich an/aus (Standard an).
  bool syncEnabled = true;

  /// Anzahl Kanaländerungen, die von anderen Steuerungen übernommen wurden.
  int get remoteChanges => _remoteChanges;
  final List<int> _lastSendMs = [];
  final Map<int, Set<int>> _intensity = {}; // vom Grandmaster betroffene Kanäle

  /// Gruppen-Master: Faktor 0..1 je Helligkeitskanal (fehlt = 1).
  final Map<int, Map<int, double>> _submaster = {};

  /// Kanäle, die im letzten Takt von Effekten überschrieben wurden.
  final List<Set<int>> _fxChannels = [];

  /// Zählt hoch, wenn sich die Ausgabe ändert (~15 Hz). Für Live-Anzeigen
  /// (Fader-Pegel, Kachelfarben), ohne die ganze App neu zu zeichnen.
  final ValueNotifier<int> live = ValueNotifier(0);

  Timer? _timer;
  final Stopwatch _clock = Stopwatch()..start();
  int _tickCount = 0;
  bool _dirtyUi = false;
  bool _liveDirty = false;

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

  // Effekte & Tempo
  final TapTempo tempo = TapTempo();
  int _beatOrigin = 0;
  final Map<String, _RunningEffect> _effects = {};

  int get universeCount => _prog.length;
  double get grandMaster => _grandMaster;
  bool get blackout => _blackout;
  String? get activeChaseId => _chase?.id;
  bool get running => _timer != null;

  // ---------- Lebenszyklus ----------

  Future<void> start() async {
    transport.target = _settings.nodeIp;
    await transport.open();
    _echoSub ??= transport.dmxIn.listen(_onEcho);
    _timer ??= Timer.periodic(_tick, (_) => _onTick());
  }

  /// Nur für Tests und Screenshots: einen Takt ohne Timer rechnen.
  @visibleForTesting
  void debugTick() => _onTick();

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _echoSub?.cancel();
    _echoSub = null;
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
      _localChangeMs.add(Int32List(512)..fillRange(0, 512, -1 << 30));
      _adopted.add(<int>{});
      _lastSent.add(Uint8List(512));
      _lastSendMs.add(-_keepAliveMs);
      _fxChannels.add(<int>{});
    }
    while (_prog.length > n) {
      _prog.removeLast();
      _localChangeMs.removeLast();
      _adopted.removeLast();
      _lastSent.removeLast();
      _lastSendMs.removeLast();
      _fxChannels.removeLast();
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
    _localChangeMs[universe][ch] = _clock.elapsedMilliseconds;
    if (notify) notifyListeners();
  }

  void setMany(Iterable<(int, int, int)> values) {
    _cancelFade();
    for (final (u, ch, v) in values) {
      if (u < _prog.length && ch >= 0 && ch < 512) {
        _prog[u][ch] = _byte(v);
        _localChangeMs[u][ch] = _clock.elapsedMilliseconds;
      }
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

  /// Gruppen-Master setzen: je Universe die Helligkeitskanäle mit Faktor.
  void setSubmasters(Map<int, Map<int, double>> map) {
    _submaster
      ..clear()
      ..addAll(map);
  }

  double _sub(int u, int ch) => _submaster[u]?[ch] ?? 1.0;

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

  /// Dauer eines Schritts (Fade, Gesamt) – im Takt aus dem Tempo.
  (int, int) _stepTiming(Chase c, ChaseStep step) {
    if (!c.bpmSync) return (step.fadeMs, step.fadeMs + step.holdMs);
    final total = (tempo.beatMs * c.beatsPerStep).round().clamp(50, 600000);
    return (step.fadeMs < total ? step.fadeMs : total, total);
  }

  void _enterStep(int now) {
    final c = _chase!;
    _chaseStepStart = now;
    _startFade(_chaseScenes[_chaseIndex], _stepTiming(c, c.steps[_chaseIndex]).$1);
  }

  void _advanceChase(int now) {
    final chase = _chase;
    if (chase == null) return;
    final step = chase.steps[_chaseIndex];
    if (now - _chaseStepStart < _stepTiming(chase, step).$2) return;
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

  // ---------- Tempo ----------

  double get bpm => tempo.bpm;

  set bpm(double v) {
    tempo.bpm = v.clamp(30.0, 300.0);
    notifyListeners();
  }

  /// Takt antippen: stellt das Tempo und setzt den Schlag auf „jetzt“.
  void tap() {
    final now = _clock.elapsedMilliseconds;
    tempo.tap(now);
    _beatOrigin = now;
    notifyListeners();
  }

  /// 0..1 innerhalb des aktuellen Schlags (für eine blinkende Anzeige).
  double get beatPhase {
    final x = (_clock.elapsedMilliseconds - _beatOrigin) / tempo.beatMs;
    return x - x.floorToDouble();
  }

  // ---------- Effekte ----------

  bool isEffectRunning(String id) => _effects.containsKey(id);
  Iterable<String> get runningEffects => _effects.keys;

  void startEffect(Effect e, List<EffectTarget> targets) {
    _effects[e.id] = _RunningEffect(e, targets, _clock.elapsedMilliseconds);
    notifyListeners();
  }

  /// Parameter oder Lampen eines laufenden Effekts ändern, ohne neu zu starten.
  void updateEffect(Effect e, List<EffectTarget> targets) {
    final r = _effects[e.id];
    if (r == null) return;
    _effects[e.id] = _RunningEffect(e, targets, r.startMs, r.untilMs);
  }

  void stopEffect(String id) {
    if (_effects.remove(id) != null) notifyListeners();
  }

  void stopAllEffects() {
    _effects.removeWhere((k, _) => !k.startsWith('_'));
    notifyListeners();
  }

  /// Lampen kurz weiß blinken lassen, um sie im Raum zu finden.
  void identify(List<EffectTarget> targets, {int ms = 3000}) {
    final now = _clock.elapsedMilliseconds;
    final e = Effect(
      id: '_identify',
      name: 'Finden',
      type: EffectType.strobe,
      fixtureIds: const [],
      syncTempo: false,
      cyclesPerMinute: 240,
      size: 0.5,
      color: 0xFFFFFF,
    );
    _effects[e.id] = _RunningEffect(e, targets, now, now + ms);
  }

  void _applyEffects(int now, List<Uint8List> out) {
    if (_effects.isEmpty) return;
    _effects.removeWhere((_, r) => r.untilMs != null && now > r.untilMs!);
    int read(int u, int ch) => u < _prog.length && ch >= 0 && ch < 512 ? _prog[u][ch] : 0;
    void write(int u, int ch, int v) {
      if (u < out.length && ch >= 0 && ch < 512) {
        out[u][ch] = v;
        _fxChannels[u].add(ch);
      }
    }

    for (final r in _effects.values) {
      final e = r.effect;
      final double phase;
      if (e.syncTempo) {
        final cycleMs = tempo.beatMs * (e.beats <= 0 ? 1 : e.beats);
        phase = (now - _beatOrigin) / cycleMs;
      } else {
        final cycleMs = 60000 / (e.cyclesPerMinute <= 0 ? 1 : e.cyclesPerMinute);
        phase = (now - r.startMs) / cycleMs;
      }
      renderEffect(e, r.targets, phase, read, write);
    }
  }

  // ---------- Live-Abgleich ----------

  /// Gemischter Stand vom Dongle: was andere Steuerungen geändert haben, wird
  /// übernommen, als hätte man es hier eingestellt. Fader zeigen es sofort.
  void _onEcho(ArtDmxIn e) {
    if (!syncEnabled) return;
    final target = transport.target;
    // Echo nur vom eigenen Dongle: per WLAN (Ziel-IP) oder per USB
    if (e.from != 'usb' && target != null && target.isNotEmpty && e.from != target) return;
    final u = e.portAddress - portAddressFor(0);
    if (u < 0 || u >= _prog.length) return;
    applyRemote(u, e.data);
  }

  /// Öffentlich für Tests. data = gemischter Stand des Universe u.
  void applyRemote(int u, Uint8List data) {
    final now = _clock.elapsedMilliseconds;
    final sent = _lastSent[u], prog = _prog[u], changedAt = _localChangeMs[u];
    final mask = _intensity[u];
    var changed = false;
    final n = data.length < 512 ? data.length : 512;
    for (var c = 0; c < n; c++) {
      final v = data[c];
      if (v == sent[c]) continue;
      if (now - changedAt[c] < _echoGuardMs) continue;
      // Kanäle unter Effekt-Kontrolle nicht übernehmen (Echo hinkt hinterher)
      if (_fxChannels[u].contains(c)) continue;
      var base = v;
      if (mask != null && mask.contains(c)) {
        // Grandmaster und Gruppen-Master herausrechnen, damit hier wieder genau v rausgeht
        final f = _grandMaster * _sub(u, c);
        if (_blackout || f <= 0) continue;
        base = (v / f).round();
      }
      prog[c] = _byte(base);
      _adopted[u].add(c);
      changed = true;
      _remoteChanges++;
    }
    if (changed) _dirtyUi = true;
  }

  // ---------- Ausgabe ----------

  void _onTick() {
    final now = _clock.elapsedMilliseconds;
    _advanceChase(now);
    _advanceFade(now);

    final base = [for (final u in _prog) Uint8List.fromList(u)];
    for (final fx in _fxChannels) {
      fx.clear();
    }
    _applyEffects(now, base);
    var anyChange = false;
    for (var u = 0; u < _prog.length; u++) {
      final out = _computeOutput(u, base[u]);
      final last = _lastSent[u], adopted = _adopted[u], changedAt = _localChangeMs[u];
      for (var c = 0; c < 512; c++) {
        if (out[c] != last[c] && !adopted.contains(c)) changedAt[c] = now;
      }
      adopted.clear();
      final changed = !_equals(out, _lastSent[u]);
      if (changed) anyChange = true;
      if (changed || now - _lastSendMs[u] >= _keepAliveMs) {
        transport.sendDmx(portAddressFor(u), out);
        _lastSent[u] = out;
        _lastSendMs[u] = now;
      }
    }

    // Live-Anzeigen mit ~13 Hz, wenn sich die Ausgabe ändert (Effekte, Fades)
    _tickCount++;
    if (anyChange) _liveDirty = true;
    if (_liveDirty && _tickCount % 3 == 0) {
      _liveDirty = false;
      live.value++;
    }
    // Ganze UI nur bei Fades/Übernahmen (Fader-Stellungen ändern sich) mit ~20 Hz
    if (_dirtyUi && _tickCount.isEven) {
      _dirtyUi = false;
      notifyListeners();
    }
  }

  Uint8List _computeOutput(int u, Uint8List out) {
    if (_blackout) {
      final mask = _intensity[u];
      if (mask == null || mask.isEmpty) return Uint8List(512);
      for (final c in mask) {
        out[c] = 0;
      }
      return out;
    }
    final subs = _submaster[u];
    if (_grandMaster < 1.0 || (subs != null && subs.isNotEmpty)) {
      for (final c in _intensity[u] ?? const <int>{}) {
        final f = _grandMaster * (subs?[c] ?? 1.0);
        if (f < 1.0) out[c] = (out[c] * f).round();
      }
    }
    return out;
  }

  /// Wert, der gerade tatsächlich rausgeht: mit Effekten, Grandmaster,
  /// Gruppen-Mastern und Blackout. Für Live-Anzeigen.
  int liveValue(int u, int ch) =>
      u < _lastSent.length && ch >= 0 && ch < 512 ? _lastSent[u][ch] : 0;

  /// true, wenn ein Effekt diesen Kanal gerade steuert.
  bool isEffectChannel(int u, int ch) => u < _fxChannels.length && _fxChannels[u].contains(ch);

  /// Wert nach Grandmaster (ohne Effekte) – für die Anzeige.
  int outputValue(int u, int ch) {
    var v = getChannel(u, ch);
    if (_intensity[u]?.contains(ch) ?? false) {
      v = _blackout ? 0 : (v * _grandMaster * _sub(u, ch)).round();
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
    live.dispose();
    _timer?.cancel();
    _echoSub?.cancel();
    transport.close();
    super.dispose();
  }
}

class _RunningEffect {
  _RunningEffect(this.effect, this.targets, this.startMs, [this.untilMs]);
  final Effect effect;
  final List<EffectTarget> targets;
  final int startMs;
  final int? untilMs;
}
