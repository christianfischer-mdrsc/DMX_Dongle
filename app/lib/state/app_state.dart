import 'package:flutter/foundation.dart';

import '../core/dmx/dmx_engine.dart';
import '../data/builtin_profiles.dart';
import '../data/storage.dart';
import '../models/models.dart';

/// Show-Daten (Patch, Szenen, Chaser, Netzwerk) + Bindeglied zur Engine.
class AppState extends ChangeNotifier {
  AppState(this.storage, this.engine);

  final Storage storage;
  final DmxEngine engine;

  final List<FixtureProfile> customProfiles = [];
  final List<Fixture> fixtures = [];
  final List<Scene> scenes = [];
  final List<Chase> chases = [];

  List<FixtureProfile> get profiles => [...builtinProfiles, ...customProfiles];
  NetworkSettings get network => engine.settings;

  void load() {
    customProfiles.addAll(storage.loadProfiles());
    fixtures.addAll(storage.loadFixtures());
    scenes.addAll(storage.loadScenes());
    chases.addAll(storage.loadChases());
    _updateIntensityMask();
  }

  // ---------- Profile ----------

  FixtureProfile? profileById(String id) {
    for (final p in profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  FixtureProfile? profileOf(Fixture f) => profileById(f.profileId);

  // ---------- Patch ----------

  /// Erste freie Adresse im Universe, an die [footprint] Kanäle passen.
  int? nextFreeAddress(int universe, int footprint) {
    final used = List<bool>.filled(513, false);
    for (final f in fixtures.where((f) => f.universe == universe)) {
      final n = profileOf(f)?.footprint ?? 1;
      for (var a = f.address; a < f.address + n && a <= 512; a++) {
        used[a] = true;
      }
    }
    for (var start = 1; start + footprint - 1 <= 512; start++) {
      var free = true;
      for (var a = start; a < start + footprint; a++) {
        if (used[a]) {
          free = false;
          break;
        }
      }
      if (free) return start;
    }
    return null;
  }

  /// Prüft, ob sich ein Gerät mit anderen überschneidet.
  Fixture? overlapping(int universe, int address, int footprint, {String? ignoreId}) {
    for (final f in fixtures) {
      if (f.universe != universe || f.id == ignoreId) continue;
      final n = profileOf(f)?.footprint ?? 1;
      if (address < f.address + n && f.address < address + footprint) return f;
    }
    return null;
  }

  void addFixtures(FixtureProfile profile, String baseName, int universe,
      int startAddress, int count) {
    var addr = startAddress;
    for (var i = 0; i < count; i++) {
      if (addr + profile.footprint - 1 > 512) break;
      final f = Fixture(
        id: newId() + i.toString(),
        name: count > 1 ? '$baseName ${i + 1}' : baseName,
        profileId: profile.id,
        universe: universe,
        address: addr,
      );
      fixtures.add(f);
      // Default-Werte (z.B. Pan/Tilt Mitte) setzen
      for (var c = 0; c < profile.channels.length; c++) {
        final d = profile.channels[c].defaultValue;
        if (d != 0) engine.setChannel(universe, addr - 1 + c, d, notify: false);
      }
      addr += profile.footprint;
    }
    _patchChanged();
  }

  void updateFixture(Fixture f, {String? name, int? universe, int? address}) {
    if (name != null) f.name = name;
    if (universe != null) f.universe = universe;
    if (address != null) f.address = address;
    _patchChanged();
  }

  void removeFixture(Fixture f) {
    fixtures.remove(f);
    _patchChanged();
  }

  void _patchChanged() {
    fixtures.sort((a, b) => a.universe != b.universe
        ? a.universe.compareTo(b.universe)
        : a.address.compareTo(b.address));
    _updateIntensityMask();
    storage.saveFixtures(fixtures);
    notifyListeners();
  }

  /// Grandmaster wirkt auf Dimmer-Kanäle; Geräte ohne Dimmer über ihre Farben.
  void _updateIntensityMask() {
    final mask = <int, Set<int>>{};
    for (final f in fixtures) {
      final p = profileOf(f);
      if (p == null) continue;
      final set = mask.putIfAbsent(f.universe, () => <int>{});
      final dim = p.offsetOf(ChannelType.dimmer);
      if (dim != null) {
        set.add(f.address - 1 + dim);
      } else {
        for (var c = 0; c < p.channels.length; c++) {
          if (p.channels[c].type.isColor) set.add(f.address - 1 + c);
        }
      }
    }
    engine.setIntensityChannels(mask);
  }

  /// Welches Gerät belegt diesen Kanal? (für Beschriftung der Fader)
  (Fixture, ChannelDef)? channelOwner(int universe, int ch0) {
    final addr = ch0 + 1;
    for (final f in fixtures) {
      if (f.universe != universe) continue;
      final p = profileOf(f);
      if (p == null) continue;
      final off = addr - f.address;
      if (off >= 0 && off < p.footprint) return (f, p.channels[off]);
    }
    return null;
  }

  // ---------- Gerätesteuerung ----------

  int? fixtureValue(Fixture f, ChannelType t) {
    final off = profileOf(f)?.offsetOf(t);
    return off == null ? null : engine.getChannel(f.universe, f.address - 1 + off);
  }

  void setFixtureValues(Iterable<Fixture> list, Map<ChannelType, int> values) {
    final out = <(int, int, int)>[];
    for (final f in list) {
      final p = profileOf(f);
      if (p == null) continue;
      values.forEach((t, v) {
        final off = p.offsetOf(t);
        if (off != null) out.add((f.universe, f.address - 1 + off, v));
      });
    }
    engine.setMany(out);
  }

  void setFixtureChannel(Iterable<Fixture> list, int offset, int value) {
    engine.setMany([
      for (final f in list)
        if ((profileOf(f)?.footprint ?? 0) > offset)
          (f.universe, f.address - 1 + offset, value),
    ]);
  }

  /// Setzt RGB(W) auf Geräten mit Farbkanälen, Dimmer auf voll falls 0.
  void setFixtureColor(Iterable<Fixture> list, int r, int g, int b) {
    for (final f in list) {
      final p = profileOf(f);
      if (p == null) continue;
      final values = <ChannelType, int>{};
      if (p.has(ChannelType.white)) {
        // Weißanteil aus RGB herausrechnen → sattere Farben bei RGBW
        final w = [r, g, b].reduce((a, c) => a < c ? a : c);
        values[ChannelType.red] = r - w;
        values[ChannelType.green] = g - w;
        values[ChannelType.blue] = b - w;
        values[ChannelType.white] = w;
      } else {
        values[ChannelType.red] = r;
        values[ChannelType.green] = g;
        values[ChannelType.blue] = b;
      }
      if (p.has(ChannelType.dimmer) && (fixtureValue(f, ChannelType.dimmer) ?? 0) == 0) {
        values[ChannelType.dimmer] = 255;
      }
      setFixtureValues([f], values);
    }
  }

  // ---------- Szenen ----------

  Scene saveScene(String name, {int fadeMs = 1000}) {
    final s = Scene(id: newId(), name: name, universes: engine.snapshot(), fadeMs: fadeMs);
    scenes.add(s);
    storage.saveScenes(scenes);
    notifyListeners();
    return s;
  }

  void overwriteScene(Scene s) {
    s.universes
      ..clear()
      ..addAll(engine.snapshot());
    storage.saveScenes(scenes);
    notifyListeners();
  }

  void updateScene(Scene s, {String? name, int? fadeMs}) {
    if (name != null) s.name = name;
    if (fadeMs != null) s.fadeMs = fadeMs;
    storage.saveScenes(scenes);
    notifyListeners();
  }

  void deleteScene(Scene s) {
    scenes.remove(s);
    for (final c in chases) {
      c.steps.removeWhere((st) => st.sceneId == s.id);
    }
    storage.saveScenes(scenes);
    storage.saveChases(chases);
    notifyListeners();
  }

  Scene? sceneById(String id) {
    for (final s in scenes) {
      if (s.id == id) return s;
    }
    return null;
  }

  // ---------- Chaser ----------

  void saveChase(Chase c) {
    if (!chases.contains(c)) chases.add(c);
    storage.saveChases(chases);
    notifyListeners();
  }

  void deleteChase(Chase c) {
    if (engine.activeChaseId == c.id) engine.stopChase();
    chases.remove(c);
    storage.saveChases(chases);
    notifyListeners();
  }

  void playChase(Chase c) =>
      engine.playChase(c, {for (final s in scenes) s.id: s});

  // ---------- Netzwerk ----------

  void updateNetwork(NetworkSettings s) {
    engine.applySettings(s);
    storage.saveNetwork(s);
    notifyListeners();
  }
}
