import 'package:flutter/material.dart';

import 'core/dmx/dmx_engine.dart';
import 'core/transport/dmx_transport.dart';
import 'data/storage.dart';
import 'state/app_state.dart';
import 'ui/app_scope.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = Storage();
  await storage.init();
  final engine = DmxEngine(DmxTransport.create(), storage.loadNetwork());
  final app = AppState(storage, engine)..load();
  await engine.start();
  runApp(DmxApp(app: app));
}

class DmxApp extends StatelessWidget {
  const DmxApp({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFFFB020),
      brightness: Brightness.dark,
    );
    return AppScope(
      app: app,
      child: MaterialApp(
        title: 'DMX Control',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: scheme,
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF111214),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
