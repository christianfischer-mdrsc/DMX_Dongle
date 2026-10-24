import 'dart:convert';

import 'package:dmx_control/core/dmx/dmx_engine.dart';
import 'package:dmx_control/core/transport/dmx_transport.dart';
import 'package:dmx_control/data/builtin_profiles.dart';
import 'package:dmx_control/data/storage.dart';
import 'package:dmx_control/models/models.dart';
import 'package:dmx_control/services/account_service.dart';
import 'package:dmx_control/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> _app() async {
  final storage = Storage();
  await storage.init();
  final engine = DmxEngine(DmxTransport.create(), NetworkSettings());
  return AppState(storage, engine, DemoAccountBackend())..load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Show sichern und in leere App laden', () async {
    final a = await _app();
    final rgb = builtinProfiles.firstWhere((p) => p.id == 'gen-rgb-3');
    a.addFixtures(rgb, 'Spot', 0, 1, 4);
    a.saveProfile(const FixtureProfile(
      id: 'custom-test',
      manufacturer: 'Eigenbau',
      name: 'Nebel',
      channels: [ChannelDef('Ausstoß', ChannelType.generic)],
    ));
    a.saveGroup('Links', a.fixtures.take(2).map((f) => f.id).toList());
    a.saveEffect(Effect.preset(EffectType.rainbow, a.fixtures.map((f) => f.id).toList()));
    a.engine.setChannel(0, 0, 200);
    a.saveScene('Rot');
    a.saveChase(Chase(id: 'c1', name: 'Lauf', steps: [ChaseStep(sceneId: a.scenes.first.id)], bpmSync: true));

    // Wie beim echten Teilen: einmal durch JSON-Text
    final text = jsonEncode(a.exportShow());

    SharedPreferences.setMockInitialValues({});
    final b = await _app();
    b.importShow(jsonDecode(text) as Map<String, dynamic>);

    expect(b.fixtures.length, 4);
    expect(b.customProfiles.single.name, 'Nebel');
    expect(b.groups.single.fixtureIds.length, 2);
    expect(b.effects.single.type, EffectType.rainbow);
    expect(b.scenes.single.universes[0]![0], 200);
    expect(b.chases.single.bpmSync, isTrue);

    // und dauerhaft gespeichert
    final c = await _app();
    expect(c.fixtures.length, 4);
    expect(c.effects.length, 1);
  });

  test('Fremde Datei wird abgelehnt', () async {
    final a = await _app();
    expect(() => a.importShow({'format': 'etwas-anderes'}), throwsFormatException);
  });

  test('Lampe entfernen räumt Gruppen und Effekte auf', () async {
    final a = await _app();
    final dim = builtinProfiles.firstWhere((p) => p.id == 'gen-dimmer-1');
    a.addFixtures(dim, 'D', 0, 1, 3);
    final ids = a.fixtures.map((f) => f.id).toList();
    a.saveGroup('Alle', ids);
    a.saveEffect(Effect.preset(EffectType.chase, ids));
    a.removeFixture(a.fixtures.first);
    expect(a.groups.single.fixtureIds.length, 2);
    expect(a.effects.single.fixtureIds.length, 2);
  });

  test('Profil in Benutzung lässt sich nicht löschen', () async {
    final a = await _app();
    const p = FixtureProfile(id: 'custom-x', manufacturer: '', name: 'X', channels: [
      ChannelDef('A', ChannelType.dimmer),
    ]);
    a.saveProfile(p);
    a.addFixtures(a.profileById('custom-x')!, 'X', 0, 1, 1);
    a.deleteProfile(p);
    expect(a.customProfiles.length, 1);
  });
}
