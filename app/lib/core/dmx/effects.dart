import 'dart:math' as math;

import '../../models/models.dart';

/// Wo die Kanäle einer Lampe liegen – das, was Effekte brauchen.
/// Alle Kanäle 0-basiert im Universe, null = Lampe hat diesen Kanal nicht.
class EffectTarget {
  final int universe;
  final int? dimmer, red, green, blue, white, pan, tilt;

  /// Für 1-Kanal-Geräte ohne Dimmer/Farbe (z. B. generischer Dimmer-Kanal).
  final int? single;

  const EffectTarget({
    required this.universe,
    this.dimmer,
    this.red,
    this.green,
    this.blue,
    this.white,
    this.pan,
    this.tilt,
    this.single,
  });

  bool get hasColor => red != null || green != null || blue != null;
  bool get hasPanTilt => pan != null && tilt != null;

  factory EffectTarget.of(Fixture f, FixtureProfile p) {
    int? at(ChannelType t) {
      final o = p.offsetOf(t);
      return o == null ? null : f.address - 1 + o;
    }

    final d = at(ChannelType.dimmer);
    final hasColor = p.hasColor;
    return EffectTarget(
      universe: f.universe,
      dimmer: d,
      red: at(ChannelType.red),
      green: at(ChannelType.green),
      blue: at(ChannelType.blue),
      white: at(ChannelType.white),
      pan: at(ChannelType.pan),
      tilt: at(ChannelType.tilt),
      single: (d == null && !hasColor && p.channels.isNotEmpty) ? f.address - 1 : null,
    );
  }
}

/// Lesen der Grundwerte (Programmer) und Schreiben der Effekt-Ausgabe.
typedef ChannelRead = int Function(int universe, int ch);
typedef ChannelWrite = void Function(int universe, int ch, int value);

int _b(num v) => v < 0 ? 0 : (v > 255 ? 255 : v.round());

/// Farbe (0xRRGGBB) auf eine Lampe; bei RGBW wird der Weißanteil herausgezogen.
void writeColor(EffectTarget t, int r, int g, int b, ChannelWrite w) {
  if (t.white != null) {
    final wv = math.min(r, math.min(g, b));
    r -= wv;
    g -= wv;
    b -= wv;
    w(t.universe, t.white!, wv);
  }
  if (t.red != null) w(t.universe, t.red!, _b(r));
  if (t.green != null) w(t.universe, t.green!, _b(g));
  if (t.blue != null) w(t.universe, t.blue!, _b(b));
}

/// Helligkeit 0..1 auf eine Lampe. Mit Dimmer: Dimmer setzen (und ggf. Farbe).
/// Ohne Dimmer: Farbe (oder die aktuelle Grundfarbe) mit der Helligkeit skalieren.
void writeLevel(EffectTarget t, double level, int? color, ChannelRead read, ChannelWrite w) {
  level = level.clamp(0.0, 1.0);
  if (t.dimmer != null) {
    w(t.universe, t.dimmer!, _b(level * 255));
    if (color != null && t.hasColor) {
      writeColor(t, (color >> 16) & 0xFF, (color >> 8) & 0xFF, color & 0xFF, w);
    }
    return;
  }
  if (t.hasColor) {
    int r, g, b;
    if (color != null) {
      r = (color >> 16) & 0xFF;
      g = (color >> 8) & 0xFF;
      b = color & 0xFF;
    } else {
      int rd(int? ch) => ch == null ? 0 : read(t.universe, ch);
      final wv = rd(t.white);
      r = rd(t.red) + wv;
      g = rd(t.green) + wv;
      b = rd(t.blue) + wv;
      if (r + g + b == 0) r = g = b = 255; // dunkel → Weiß, sonst sieht man nichts
    }
    writeColor(t, _b(r * level), _b(g * level), _b(b * level), w);
    return;
  }
  if (t.single != null) w(t.universe, t.single!, _b(level * 255));
}

/// HSV (h 0..1, volle Sättigung/Helligkeit) → 0xRRGGBB
int hueToRgb(double h) {
  h = h - h.floorToDouble();
  final x = h * 6;
  final i = x.floor();
  final f = x - i;
  final q = _b(255 * (1 - f)), t = _b(255 * f);
  final (r, g, b) = switch (i % 6) {
    0 => (255, t, 0),
    1 => (q, 255, 0),
    2 => (0, 255, t),
    3 => (0, q, 255),
    4 => (t, 0, 255),
    _ => (255, 0, q),
  };
  return (r << 16) | (g << 8) | b;
}

/// Gleichmäßiges „Rauschen“ 0..1, deterministisch (für Flackern und Tests).
double smoothNoise(int seed, double x) {
  double h(int n) {
    var v = (n * 374761393 + seed * 668265263) & 0x7fffffff;
    v = ((v ^ (v >> 13)) * 1274126177) & 0x7fffffff;
    return (v & 0xffff) / 0xffff;
  }

  final i = x.floor();
  final f = x - i;
  final s = f * f * (3 - 2 * f);
  return h(i) * (1 - s) + h(i + 1) * s;
}

/// Rechnet einen Effekt für den Zeitpunkt [phase] (Anzahl Zyklen seit Start)
/// und schreibt die Werte für alle [targets].
void renderEffect(
  Effect e,
  List<EffectTarget> targets,
  double phase,
  ChannelRead read,
  ChannelWrite write,
) {
  final n = targets.length;
  if (n == 0) return;
  final size = e.size.clamp(0.0, 1.0);
  for (var i = 0; i < n; i++) {
    final t = targets[i];
    final offset = n > 1 ? e.spread * i / n : 0.0;
    final p = phase - offset;
    final frac = p - p.floorToDouble();
    switch (e.type) {
      case EffectType.rainbow:
        final c = hueToRgb(frac);
        if (t.dimmer != null && read(t.universe, t.dimmer!) == 0) {
          write(t.universe, t.dimmer!, 255);
        }
        if (t.hasColor) {
          writeColor(t, (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF, write);
        }
      case EffectType.pulse:
        final wave = 0.5 - 0.5 * math.cos(2 * math.pi * frac);
        writeLevel(t, 1 - size + size * wave, e.color, read, write);
      case EffectType.chase:
        // Fixture i ist an, solange der Lauf über ihm steht; size = Länge des Schweifs
        final pos = phase - phase.floorToDouble();
        final mine = i / n;
        final d = (pos - mine) - (pos - mine).floorToDouble();
        final width = math.max(1 / n, size * 0.9);
        writeLevel(t, d < width ? 1.0 : 0.0, e.color, read, write);
      case EffectType.strobe:
        final on = frac < math.max(0.05, 0.5 * (1 - size) + 0.05);
        writeLevel(t, on ? 1.0 : 0.0, e.color ?? 0xFFFFFF, read, write);
      case EffectType.flicker:
        final v = smoothNoise(i + 1, phase * 8) * 0.65 + smoothNoise(i + 101, phase * 23) * 0.35;
        writeLevel(t, 1 - size * v, e.color ?? 0xFF7A1E, read, write);
      case EffectType.circle:
        if (!t.hasPanTilt) continue;
        final cx = read(t.universe, t.pan!), cy = read(t.universe, t.tilt!);
        final amp = size * 127;
        final a = 2 * math.pi * frac;
        write(t.universe, t.pan!, _b(cx + amp * math.cos(a)));
        write(t.universe, t.tilt!, _b(cy + amp * math.sin(a)));
    }
  }
}

/// Tempo aus getippten Schlägen. Mittelt die letzten Abstände,
/// beginnt nach 2 s Pause neu.
class TapTempo {
  TapTempo({this.bpm = 120});

  double bpm;
  final List<int> _taps = [];

  /// Gibt true zurück, wenn sich das Tempo geändert hat.
  bool tap(int nowMs) {
    if (_taps.isNotEmpty && nowMs - _taps.last > 2000) _taps.clear();
    _taps.add(nowMs);
    if (_taps.length > 6) _taps.removeAt(0);
    if (_taps.length < 2) return false;
    final avg = (_taps.last - _taps.first) / (_taps.length - 1);
    if (avg <= 0) return false;
    bpm = (60000 / avg).clamp(30.0, 300.0);
    return true;
  }

  double get beatMs => 60000 / bpm;
}
