// Erzeugt Bildschirmfotos der App mit Beispieldaten (nur für CI/Doku).
// flutter test screenshot_test --update-goldens
import 'dart:io';

import 'package:dmx_control/core/dmx/dmx_engine.dart';
import 'package:dmx_control/core/transport/dmx_transport.dart';
import 'package:dmx_control/data/builtin_profiles.dart';
import 'package:dmx_control/data/storage.dart';
import 'package:dmx_control/models/models.dart';
import 'package:dmx_control/services/account_service.dart';
import 'package:dmx_control/state/app_state.dart';
import 'package:dmx_control/ui/app_scope.dart';
import 'package:dmx_control/ui/home_screen.dart';
import 'package:dmx_control/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _font(String family, String path) async {
  final f = File(path);
  if (!f.existsSync()) return;
  final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  await loader.load();
}

Future<AppState> _demo(ControlLayout layout) async {
  SharedPreferences.setMockInitialValues({});
  final storage = Storage();
  await storage.init();
  final engine = DmxEngine(DmxTransport.create(), NetworkSettings());
  final a = AppState(storage, engine, DemoAccountBackend())..load();
  FixtureProfile p(String id) => builtinProfiles.firstWhere((x) => x.id == id);
  a.addFixtures(p('gen-par-7'), 'PAR', 0, 1, 6);
  a.addFixtures(p('gen-mh-11'), 'Moving Head', 0, 50, 2);
  a.addFixtures(p('gen-rgbw-4'), 'Bar', 1, 1, 4);
  a.addFixtures(p('gen-dimmer-1'), 'Fluter', 1, 30, 2);
  final u0 = a.fixturesIn(0), u1 = a.fixturesIn(1);
  a.saveGroup('PARs', u0.take(6).map((f) => f.id).toList());
  a.saveGroup('Heads', u0.skip(6).map((f) => f.id).toList());
  a.saveGroup('Bars', u1.take(4).map((f) => f.id).toList());
  a.allOn(u1.skip(4));
  a.allOn(u0.skip(6));
  a.setGroupMaster(a.groups[1], 0.6);
  final rainbow = Effect.preset(EffectType.rainbow, u0.take(6).map((f) => f.id).toList())..name = 'Regenbogen';
  a.saveEffect(rainbow);
  a.saveEffect(Effect.preset(EffectType.pulse, u1.take(4).map((f) => f.id).toList())..name = 'Bars atmen');
  a.saveEffect(Effect.preset(EffectType.circle, u0.skip(6).map((f) => f.id).toList())..name = 'Kreis');
  if (!a.isEffectRunning(rainbow)) a.toggleEffect(rainbow);
  for (final n in ['Intro', 'Warm', 'Kalt', 'Party', 'Ende']) {
    a.saveScene(n);
  }
  a.saveChase(Chase(id: 'c1', name: 'Show-Lauf', steps: [ChaseStep(sceneId: a.scenes.first.id)]));
  a.setControlLayout(layout);
  for (var i = 0; i < 20; i++) {
    engine.debugTick();
  }
  return a;
}

Widget _wrap(AppState a, ThemeMode mode) => AppScope(
      app: a,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: mode,
        home: const HomeScreen(),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final fonts = Platform.environment['SHOT_FONTS'] ?? 'fonts';
    await _font('Roboto', '$fonts/Roboto.ttf');
    await _font('MaterialIcons', '$fonts/MaterialIcons-Regular.otf');
  });

  Future<void> shot(WidgetTester t, String name, Size size, ControlLayout layout,
      {ThemeMode mode = ThemeMode.dark, String? tab}) async {
    t.view.physicalSize = size * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final a = await _demo(layout);
    await t.pumpWidget(_wrap(a, mode));
    await t.pump(const Duration(milliseconds: 100));
    if (tab != null) {
      await t.tap(find.text(tab).last);
      await t.pump(const Duration(milliseconds: 400));
    }
    // ein paar Takte, damit Live-Werte und Effekte zu sehen sind
    for (var i = 0; i < 6; i++) {
      a.engine.debugTick();
      await t.pump(const Duration(milliseconds: 50));
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/$name.png'));
    a.engine.stopAllEffects();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  }

  testWidgets('Tablet Pult', (t) => shot(t, 'tablet_pult', const Size(1280, 800), ControlLayout.tabs, tab: 'Pult'));
  testWidgets('Tablet Pult schmal',
      (t) => shot(t, 'tablet_pult_hoch', const Size(800, 1280), ControlLayout.tabs, tab: 'Pult'));
  testWidgets('Tablet Steuern nebeneinander',
      (t) => shot(t, 'tablet_steuern_nebeneinander', const Size(1280, 800), ControlLayout.columns));
  testWidgets('Handy Steuern', (t) => shot(t, 'handy_steuern', const Size(412, 915), ControlLayout.tabs));
  testWidgets('Handy quer', (t) => shot(t, 'handy_quer', const Size(915, 412), ControlLayout.tabs));
}
