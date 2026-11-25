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

  FixtureProfile dimmer() => builtinProfiles.firstWhere((p) => p.channels.length == 1);

  test('Reihenfolge per Ziehen bleibt gespeichert', () async {
    final a = await _app();
    a.addFixtures(dimmer(), 'L', 0, 1, 3); // L 1..3
    final ids = a.fixturesIn(0).map((f) => f.id).toList();
    a.moveFixture(ids[2], ids[0]); // dritte vor die erste
    expect(a.fixturesIn(0).map((f) => f.id), [ids[2], ids[0], ids[1]]);

    final b = await _app();
    expect(b.fixturesIn(0).map((f) => f.id), [ids[2], ids[0], ids[1]]);

    b.sortByAddress(0);
    expect(b.fixturesIn(0).map((f) => f.id), ids);
  });

  test('Universen getrennt', () async {
    final a = await _app();
    a.addFixtures(dimmer(), 'A', 0, 1, 2);
    a.addFixtures(dimmer(), 'B', 1, 1, 3);
    expect(a.fixturesIn(0).length, 2);
    expect(a.fixturesIn(1).length, 3);
  });

  test('Gruppen-Master dimmt nur seine Lampen', () async {
    final a = await _app();
    a.addFixtures(dimmer(), 'L', 0, 1, 2);
    a.saveGroup('Links', [a.fixtures.first.id]);
    a.engine.setChannel(0, 0, 200);
    a.engine.setChannel(0, 1, 200);
    a.setGroupMaster(a.groups.single, 0.5);
    expect(a.engine.outputValue(0, 0), 100);
    expect(a.engine.outputValue(0, 1), 200);
    expect(a.engine.getChannel(0, 0), 200); // Programmer unverändert
  });

  test('Anordnung der Universen wird gespeichert', () async {
    final a = await _app();
    a.setControlLayout(ControlLayout.columns);
    final b = await _app();
    expect(b.controlLayout, ControlLayout.columns);
  });
}
