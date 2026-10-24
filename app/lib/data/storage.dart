import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Lokale Speicherung als JSON (SharedPreferences, alle Plattformen inkl. Web).
class Storage {
  static const _kFixtures = 'fixtures';
  static const _kScenes = 'scenes';
  static const _kChases = 'chases';
  static const _kProfiles = 'customProfiles';
  static const _kNetwork = 'network';
  static const _kGroups = 'groups';
  static const _kEffects = 'effects';

  late SharedPreferences _p;

  Future<void> init() async => _p = await SharedPreferences.getInstance();

  List<T> _list<T>(String key, T Function(Map<String, dynamic>) f) {
    final raw = _p.getString(key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => f(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(String key, Object value) =>
      _p.setString(key, jsonEncode(value));

  List<Fixture> loadFixtures() => _list(_kFixtures, Fixture.fromJson);
  List<Scene> loadScenes() => _list(_kScenes, Scene.fromJson);
  List<Chase> loadChases() => _list(_kChases, Chase.fromJson);
  List<FixtureProfile> loadProfiles() => _list(_kProfiles, FixtureProfile.fromJson);
  List<FixtureGroup> loadGroups() => _list(_kGroups, FixtureGroup.fromJson);
  List<Effect> loadEffects() => _list(_kEffects, Effect.fromJson);

  NetworkSettings loadNetwork() {
    final raw = _p.getString(_kNetwork);
    if (raw == null) return NetworkSettings();
    try {
      return NetworkSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return NetworkSettings();
    }
  }

  Future<void> saveFixtures(List<Fixture> v) =>
      _save(_kFixtures, v.map((e) => e.toJson()).toList());
  Future<void> saveScenes(List<Scene> v) =>
      _save(_kScenes, v.map((e) => e.toJson()).toList());
  Future<void> saveChases(List<Chase> v) =>
      _save(_kChases, v.map((e) => e.toJson()).toList());
  Future<void> saveProfiles(List<FixtureProfile> v) =>
      _save(_kProfiles, v.map((e) => e.toJson()).toList());
  Future<void> saveNetwork(NetworkSettings v) => _save(_kNetwork, v.toJson());
  Future<void> saveGroups(List<FixtureGroup> v) =>
      _save(_kGroups, v.map((e) => e.toJson()).toList());
  Future<void> saveEffects(List<Effect> v) =>
      _save(_kEffects, v.map((e) => e.toJson()).toList());

  String? loadString(String key) => _p.getString('setting.$key');
  Future<void> saveString(String key, String value) => _p.setString('setting.$key', value);
}
