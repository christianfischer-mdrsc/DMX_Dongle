import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/dmx/dmx_engine.dart';
import 'core/transport/dmx_transport.dart';
import 'data/storage.dart';
import 'services/account_service.dart';
import 'state/app_state.dart';
import 'ui/app_scope.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = Storage();
  await storage.init();
  final engine = DmxEngine(DmxTransport.create(), storage.loadNetwork());
  // Android meldet, wenn die App ans WLAN gebunden wurde (MainActivity.kt).
  // Sockets hängen am Netz von ihrer Erzeugung, also neu anlegen.
  const MethodChannel('dmx_control/network').setMethodCallHandler((call) async {
    if (call.method == 'networkChanged') await engine.transport.reopen();
  });
  final app = AppState(storage, engine, DemoAccountBackend())..load();
  await app.restoreAccount();
  await engine.start();
  runApp(DmxApp(app: app));
}

class DmxApp extends StatelessWidget {
  const DmxApp({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      app: app,
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) => MaterialApp(
          title: 'DMX Control',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: app.themeMode,
          home: const HomeScreen(),
        ),
      ),
    );
  }
}
