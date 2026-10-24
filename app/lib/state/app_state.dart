import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color, ThemeMode;

import '../core/dmx/dmx_engine.dart';
import '../core/dmx/effects.dart';
import '../data/builtin_profiles.dart';
import '../data/storage.dart';
import '../models/models.dart';
import '../services/account_service.dart';

/// Show-Daten (Patch, Szenen, Chaser, Netzwerk), Einstellungen, Konto
/// und das Bindeglied zur Engine.
class AppState extends ChangeNotifier {
  AppState(this.storage, this.engine, this.account);

  final Storage storage;
  final DmxEngine engine;
  final AccountBackend account;

  // ---------- Einstellungen ----------

  ThemeMode themeMode = ThemeMode.light;

  void setThemeMode(ThemeMode m) {
    themeMode = m;
    storage.saveString('themeMode', m.name);
    notifyListeners();
  }

  // ---------- Konto & Freischaltungen ----------

  UserAccount? user;
  Set<String> entitlements = {};

  bool isUnlocked(FixtureProfile p) => p.requires == null || entitlements.contains(p.requires);

  // Freischaltungen werden pro Konto auf dem Handy zwischengespeichert:
  // Am Dongle-WLAN gibt es kein Internet, die Pro-Geräte müssen trotzdem gehen.
  String _entKey(UserAccount u) => 'entitlements.${u.id}';

  Set<String> _cachedEntitlements(UserAccount u) {
    final raw = storage.loadString(_entKey(u));
    return raw == null || raw.isEmpty ? {} : raw.split(',').toSet();
  }

  void _setEntitlements(UserAccount u, Set<String> e) {
    entitlements = e;
    storage.saveString(_entKey(u), e.join(','));
  }

  // ---------- Admin & Hinweise vom Server ----------

  /// Darf dieses Konto den Admin-Bereich öffnen? (Zwischengespeichert;
  /// der Server prüft bei jeder Admin-Aktion trotzdem selbst.)
  bool isAdmin = false;

  /// Hinweis an alle Nutzer, gepflegt im Admin-Bereich.
  String announcement = '';
  String supportEmail = '';

  String _adminKey(UserAccount u) => 'isAdmin.${u.id}';

  bool get announcementDismissed =>
      announcement.isNotEmpty && storage.loadString('announcement.dismissed') == announcement;

  void dismissAnnouncement() {
    storage.saveString('announcement.dismissed', announcement);
    notifyListeners();
  }

  void _loadCachedSettings() {
    announcement = storage.loadString('announcement') ?? '';
    supportEmail = storage.loadString('supportEmail') ?? '';
  }

  /// Hinweis & Kontakt vom Server holen (auch ohne Anmeldung).
  Future<void> refreshAppSettings() async {
    try {
      final m = await account.fetchAppSettings();
      final a = m['announcement'];
      announcement = (a is Map ? a['text'] as String? : a as String?)?.trim() ?? '';
      final sEmail = m['support_email'];
      supportEmail = (sEmail is String ? sEmail : '').trim();
      storage.saveString('announcement', announcement);
      storage.saveString('supportEmail', supportEmail);
      notifyListeners();
    } on AccountException {
      // offline – letzter Stand bleibt
    }
  }

  /// Startet ohne zu warten: erst Zwischenspeicher, dann Server im Hintergrund.
  Future<void> restoreAccount() async {
    _loadCachedSettings();
    user = await account.restoreSession();
    final u = user;
    entitlements = u == null ? {} : _cachedEntitlements(u);
    isAdmin = u != null && storage.loadString(_adminKey(u)) == 'true';
    notifyListeners();
    refreshAppSettings();
    if (u != null) refreshEntitlements();
  }

  /// Holt Freischaltungen und Admin-Status vom Server. Offline bleibt der letzte Stand.
  Future<void> refreshEntitlements() async {
    final u = user;
    if (u == null) return;
    try {
      _setEntitlements(u, await account.fetchEntitlements(u));
      isAdmin = await account.checkIsAdmin();
      storage.saveString(_adminKey(u), isAdmin.toString());
      notifyListeners();
    } on AccountException {
      // offline – Zwischenspeicher gilt weiter
    }
  }

  Future<void> _afterLogin(UserAccount u) async {
    user = u;
    entitlements = _cachedEntitlements(u);
    isAdmin = storage.loadString(_adminKey(u)) == 'true';
    notifyListeners();
    await refreshEntitlements();
  }

  Future<void> signIn(String email, String password) async =>
      _afterLogin(await account.signIn(email, password));

  /// true = angemeldet, false = E-Mail muss erst bestätigt werden.
  Future<bool> register(String name, String email, String password) async {
    final u = await account.register(name, email, password);
    if (u == null) return false;
    await _afterLogin(u);
    return true;
  }

  Future<void> verifyEmail(String email, String code) async =>
      _afterLogin(await account.verifyEmail(email, code));

  Future<void> resetPassword(String email, String code, String newPassword) async =>
      _afterLogin(await account.resetPassword(email, code, newPassword));

  Future<void> signOut() async {
    await account.signOut();
    user = null;
    entitlements = {};
    isAdmin = false;
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    final u = user;
    await account.deleteAccount();
    if (u != null) storage.saveString(_entKey(u), '');
    user = null;
    entitlements = {};
    isAdmin = false;
    notifyListeners();
  }

  /// Gibt die neu freigeschalteten Pakete zurück.
  Future<List<FeaturePack>> redeemCode(String code) async {
    final u = user;
    if (u == null) throw const AccountException('Bitte zuerst anmelden.');
    final added = await account.redeemCode(u, code);
    _setEntitlements(u, {...entitlements, ...added});
    notifyListeners();
    return featurePacks.where((p) => added.contains(p.id)).toList();
  }

  final List<FixtureProfile> customProfiles = [];
  final List<Fixture> fixtures = [];
  final List<Scene> scenes = [];
  final List<Chase> chases = [];
  final List<FixtureGroup> groups = [];
  final List<Effect> effects = [];

  List<FixtureProfile> get profiles => [...builtinProfiles, ...customProfiles];
  NetworkSettings get network => engine.settings;

  void load() {
    final tm = storage.loadString('themeMode');
    themeMode = ThemeMode.values.firstWhere((m) => m.name == tm, orElse: () => ThemeMode.light);
    customProfiles.addAll(storage.loadProfiles());
    fixtures.addAll(storage.loadFixtures());
    scenes.addAll(storage.loadScenes());
    chases.addAll(storage.loadChases());
    groups.addAll(storage.loadGroups());
    effects.addAll(storage.loadEffects());
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
    for (final g in groups) {
      g.fixtureIds.remove(f.id);
    }
    for (final e in effects) {
      e.fixtureIds.remove(f.id);
    }
    storage.saveGroups(groups);
    storage.saveEffects(effects);
    _patchChanged();
  }

  Fixture? fixtureById(String id) {
    for (final f in fixtures) {
      if (f.id == id) return f;
    }
    return null;
  }

  List<Fixture> fixturesByIds(Iterable<String> ids) =>
      [for (final id in ids) if (fixtureById(id) case final f?) f];

  void _patchChanged() {
    fixtures.sort((a, b) => a.universe != b.universe
        ? a.universe.compareTo(b.universe)
        : a.address.compareTo(b.address));
    _updateIntensityMask();
    _refreshRunningEffects();
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

  /// Aktuelle Lichtfarbe eines Geräts für Vorschauen (null = keine Farbkanäle).
  Color? fixtureColor(Fixture f) {
    final p = profileOf(f);
    if (p == null || !p.hasColor) return null;
    int v(ChannelType t) => fixtureValue(f, t) ?? 0;
    final w = v(ChannelType.white);
    int c(int x) => x + w > 255 ? 255 : x + w;
    return Color.fromARGB(255, c(v(ChannelType.red)), c(v(ChannelType.green)), c(v(ChannelType.blue)));
  }

  /// Helligkeit 0..1 (Dimmer, sonst hellster Farbkanal).
  double fixtureLevel(Fixture f) {
    final p = profileOf(f);
    if (p == null) return 0;
    final dim = fixtureValue(f, ChannelType.dimmer);
    if (dim != null) return dim / 255;
    var m = 0;
    for (var i = 0; i < p.channels.length; i++) {
      if (p.channels[i].type.isColor || p.channels[i].type == ChannelType.generic) {
        final x = engine.getChannel(f.universe, f.address - 1 + i);
        if (x > m) m = x;
      }
    }
    return m / 255;
  }

  /// Alle Geräte an: Dimmer voll, Geräte ohne Farbe/Dimmer-Wert auf Weiß.
  void allOn([Iterable<Fixture>? list]) {
    for (final f in list ?? fixtures) {
      final p = profileOf(f);
      if (p == null) continue;
      if (p.has(ChannelType.dimmer)) setFixtureValues([f], {ChannelType.dimmer: 255});
      final col = fixtureColor(f);
      if (p.hasColor && (col == null || (col.r == 0 && col.g == 0 && col.b == 0))) {
        setFixtureColor([f], 255, 255, 255);
      }
      if (!p.hasColor && !p.has(ChannelType.dimmer)) setFixtureChannel([f], 0, 255);
    }
  }

  /// Alle Geräte aus: Dimmer- und Farbkanäle auf 0, Positionen bleiben.
  void allOff([Iterable<Fixture>? list]) {
    final out = <(int, int, int)>[];
    for (final f in list ?? fixtures) {
      final p = profileOf(f);
      if (p == null) continue;
      for (var i = 0; i < p.channels.length; i++) {
        final t = p.channels[i].type;
        if (t == ChannelType.dimmer || t.isColor || t == ChannelType.strobe ||
            (p.channels.length == 1)) {
          out.add((f.universe, f.address - 1 + i, 0));
        }
      }
    }
    engine.setMany(out);
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

  // ---------- Gruppen ----------

  FixtureGroup saveGroup(String name, List<String> fixtureIds) {
    final g = FixtureGroup(id: newId(), name: name, fixtureIds: [...fixtureIds]);
    groups.add(g);
    storage.saveGroups(groups);
    notifyListeners();
    return g;
  }

  void updateGroup(FixtureGroup g, {String? name, List<String>? fixtureIds}) {
    if (name != null) g.name = name;
    if (fixtureIds != null) {
      g.fixtureIds
        ..clear()
        ..addAll(fixtureIds);
    }
    storage.saveGroups(groups);
    notifyListeners();
  }

  void deleteGroup(FixtureGroup g) {
    groups.remove(g);
    storage.saveGroups(groups);
    notifyListeners();
  }

  // ---------- Effekte ----------

  List<EffectTarget> targetsFor(Iterable<Fixture> list) => [
        for (final f in list)
          if (profileOf(f) case final p?) EffectTarget.of(f, p),
      ];

  bool isEffectRunning(Effect e) => engine.isEffectRunning(e.id);

  void saveEffect(Effect e) {
    if (!effects.contains(e)) effects.add(e);
    storage.saveEffects(effects);
    if (engine.isEffectRunning(e.id)) {
      engine.updateEffect(e, targetsFor(fixturesByIds(e.fixtureIds)));
    }
    notifyListeners();
  }

  void deleteEffect(Effect e) {
    engine.stopEffect(e.id);
    effects.remove(e);
    storage.saveEffects(effects);
    notifyListeners();
  }

  void toggleEffect(Effect e) {
    if (engine.isEffectRunning(e.id)) {
      engine.stopEffect(e.id);
    } else {
      engine.startEffect(e, targetsFor(fixturesByIds(e.fixtureIds)));
    }
    notifyListeners();
  }

  /// Vorschau eines noch nicht gespeicherten Effekts (Editor).
  void previewEffect(Effect e) {
    final t = targetsFor(fixturesByIds(e.fixtureIds));
    if (engine.isEffectRunning(e.id)) {
      engine.updateEffect(e, t);
    } else {
      engine.startEffect(e, t);
    }
  }

  void _refreshRunningEffects() {
    for (final e in effects) {
      if (engine.isEffectRunning(e.id)) {
        engine.updateEffect(e, targetsFor(fixturesByIds(e.fixtureIds)));
      }
    }
  }

  /// Lampen kurz blinken lassen.
  void identify(Iterable<Fixture> list) => engine.identify(targetsFor(list));

  // ---------- Eigene Geräteprofile ----------

  bool profileInUse(FixtureProfile p) => fixtures.any((f) => f.profileId == p.id);

  void saveProfile(FixtureProfile p) {
    final i = customProfiles.indexWhere((x) => x.id == p.id);
    if (i >= 0) {
      customProfiles[i] = p;
    } else {
      customProfiles.add(p);
    }
    storage.saveProfiles(customProfiles);
    _patchChanged();
  }

  void deleteProfile(FixtureProfile p) {
    if (profileInUse(p)) return;
    customProfiles.removeWhere((x) => x.id == p.id);
    storage.saveProfiles(customProfiles);
    notifyListeners();
  }

  // ---------- Sichern & Laden ----------

  static const backupFormat = 'dmx-master-show';

  /// Komplette Show als JSON (ohne Konto-Daten).
  Map<String, dynamic> exportShow() => {
        'format': backupFormat,
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'network': network.toJson(),
        'profiles': customProfiles.map((e) => e.toJson()).toList(),
        'fixtures': fixtures.map((e) => e.toJson()).toList(),
        'groups': groups.map((e) => e.toJson()).toList(),
        'scenes': scenes.map((e) => e.toJson()).toList(),
        'chases': chases.map((e) => e.toJson()).toList(),
        'effects': effects.map((e) => e.toJson()).toList(),
      };

  /// Ersetzt die aktuelle Show. Wirft FormatException bei fremden Dateien.
  void importShow(Map<String, dynamic> j, {bool includeNetwork = false}) {
    if (j['format'] != backupFormat) {
      throw const FormatException('Das ist keine DMX-Master-Sicherung.');
    }
    List<T> list<T>(String k, T Function(Map<String, dynamic>) f) =>
        [for (final e in (j[k] as List? ?? const [])) f(e as Map<String, dynamic>)];
    final p = list('profiles', FixtureProfile.fromJson);
    final fx = list('fixtures', Fixture.fromJson);
    final g = list('groups', FixtureGroup.fromJson);
    final sc = list('scenes', Scene.fromJson);
    final ch = list('chases', Chase.fromJson);
    final ef = list('effects', Effect.fromJson);

    engine.stopAllEffects();
    engine.stopChase();
    customProfiles
      ..clear()
      ..addAll(p);
    fixtures
      ..clear()
      ..addAll(fx);
    groups
      ..clear()
      ..addAll(g);
    scenes
      ..clear()
      ..addAll(sc);
    chases
      ..clear()
      ..addAll(ch);
    effects
      ..clear()
      ..addAll(ef);
    storage.saveProfiles(customProfiles);
    storage.saveGroups(groups);
    storage.saveScenes(scenes);
    storage.saveChases(chases);
    storage.saveEffects(effects);
    if (includeNetwork && j['network'] is Map) {
      updateNetwork(NetworkSettings.fromJson((j['network'] as Map).cast<String, dynamic>()));
    }
    _patchChanged();
  }
}
