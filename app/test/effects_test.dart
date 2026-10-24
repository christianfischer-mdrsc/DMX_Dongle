import 'package:dmx_control/core/dmx/effects.dart';
import 'package:dmx_control/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Kleiner Speicher für 1 Universe, wie ihn die Engine benutzt.
class _Mem {
  final base = List<int>.filled(512, 0);
  final out = <int, int>{};
  int read(int u, int ch) => base[ch];
  void write(int u, int ch, int v) => out[ch] = v;
}

const _rgb = EffectTarget(universe: 0, red: 0, green: 1, blue: 2);
const _drgb = EffectTarget(universe: 0, dimmer: 10, red: 11, green: 12, blue: 13);
const _mh = EffectTarget(universe: 0, dimmer: 20, pan: 21, tilt: 22);

void main() {
  test('Farbkreis', () {
    expect(hueToRgb(0), 0xFF0000);
    expect(hueToRgb(1 / 3), 0x00FF00);
    expect(hueToRgb(2 / 3), 0x0000FF);
    expect(hueToRgb(1), 0xFF0000);
  });

  test('Regenbogen verteilt Farben über die Lampen', () {
    final m = _Mem();
    final e = Effect.preset(EffectType.rainbow, const [])..spread = 1;
    const a = EffectTarget(universe: 0, red: 0, green: 1, blue: 2);
    const b = EffectTarget(universe: 0, red: 3, green: 4, blue: 5);
    const c = EffectTarget(universe: 0, red: 6, green: 7, blue: 8);
    renderEffect(e, const [a, b, c], 0, m.read, m.write);
    // Lampe 0 rot, die anderen um 1/3 bzw. 2/3 versetzt
    expect([m.out[0], m.out[1], m.out[2]], [255, 0, 0]);
    expect(m.out[3]! + m.out[4]! + m.out[5]!, greaterThan(0));
    expect(m.out[3] == 255 && m.out[4] == 0 && m.out[5] == 0, isFalse);
  });

  test('Regenbogen schaltet dunklen Dimmer ein', () {
    final m = _Mem();
    renderEffect(Effect.preset(EffectType.rainbow, const []), const [_drgb], 0, m.read, m.write);
    expect(m.out[10], 255);
  });

  test('Pulsieren bleibt im Hub', () {
    final m = _Mem();
    final e = Effect.preset(EffectType.pulse, const [])..size = 0.5;
    renderEffect(e, const [_drgb], 0, m.read, m.write);
    expect(m.out[10], 128); // Tiefpunkt = 1 - size
    renderEffect(e, const [_drgb], 0.5, m.read, m.write);
    expect(m.out[10], 255); // Hochpunkt
  });

  test('Pulsieren ohne Dimmer skaliert die Grundfarbe', () {
    final m = _Mem()..base[0] = 200;
    final e = Effect.preset(EffectType.pulse, const [])..size = 1;
    renderEffect(e, const [_rgb], 0.5, m.read, m.write);
    expect(m.out[0], 200);
    expect(m.out[1], 0);
    renderEffect(e, const [_rgb], 0, m.read, m.write);
    expect(m.out[0], 0);
  });

  test('Lauflicht: genau eine Lampe an', () {
    final m = _Mem();
    final e = Effect.preset(EffectType.chase, const []);
    final ts = [for (var i = 0; i < 4; i++) EffectTarget(universe: 0, dimmer: 100 + i)];
    for (final phase in [0.0, 0.3, 0.6, 0.9]) {
      m.out.clear();
      renderEffect(e, ts, phase, m.read, m.write);
      final on = [for (var i = 0; i < 4; i++) if (m.out[100 + i] == 255) i];
      expect(on.length, 1, reason: 'phase $phase');
      expect(on.single, (phase * 4).floor());
    }
  });

  test('Strobe wechselt zwischen an und aus', () {
    final m = _Mem();
    final e = Effect.preset(EffectType.strobe, const []);
    renderEffect(e, const [_drgb], 0.01, m.read, m.write);
    expect(m.out[10], 255);
    renderEffect(e, const [_drgb], 0.9, m.read, m.write);
    expect(m.out[10], 0);
  });

  test('Flackern bleibt in den Grenzen', () {
    final m = _Mem();
    final e = Effect.preset(EffectType.flicker, const [])..size = 0.6;
    for (var i = 0; i < 200; i++) {
      renderEffect(e, const [_drgb], i * 0.037, m.read, m.write);
      expect(m.out[10]!, inInclusiveRange(255 * 0.4 - 1, 255));
    }
  });

  test('Kreis um die aktuelle Position', () {
    final m = _Mem()
      ..base[21] = 128
      ..base[22] = 100;
    final e = Effect.preset(EffectType.circle, const [])..size = 0.2;
    renderEffect(e, const [_mh], 0, m.read, m.write);
    expect(m.out[21], 128 + 25); // cos 0 = 1, 0.2 * 127 ≈ 25
    expect(m.out[22], 100);
    renderEffect(e, const [_mh], 0.25, m.read, m.write);
    expect(m.out[21], 128);
    expect(m.out[22], 125);
  });

  test('RGBW zieht Weiß heraus', () {
    final m = _Mem();
    const t = EffectTarget(universe: 0, red: 0, green: 1, blue: 2, white: 3);
    writeColor(t, 255, 255, 200, m.write);
    expect([m.out[0], m.out[1], m.out[2], m.out[3]], [55, 55, 0, 200]);
  });

  test('Tap-Tempo', () {
    final t = TapTempo();
    t.tap(0);
    t.tap(500);
    t.tap(1000);
    t.tap(1500);
    expect(t.bpm, closeTo(120, 0.01));
    // nach Pause neu beginnen
    t.tap(10000);
    t.tap(10400);
    expect(t.bpm, closeTo(150, 0.01));
  });

  test('Effekt übersteht JSON', () {
    final e = Effect.preset(EffectType.flicker, ['a', 'b'])
      ..syncTempo = false
      ..cyclesPerMinute = 42;
    final back = Effect.fromJson(e.toJson());
    expect(back.type, EffectType.flicker);
    expect(back.fixtureIds, ['a', 'b']);
    expect(back.cyclesPerMinute, 42);
    expect(back.color, 0xFF7A1E);
  });

  test('Ablauf im Takt übersteht JSON, alte Daten bleiben lesbar', () {
    final c = Chase(id: 'c', name: 'x', steps: [], bpmSync: true, beatsPerStep: 2);
    final back = Chase.fromJson(c.toJson());
    expect(back.bpmSync, isTrue);
    expect(back.beatsPerStep, 2);
    final old = Chase.fromJson({'id': 'o', 'name': 'alt', 'steps': []});
    expect(old.bpmSync, isFalse);
  });
}
