import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'faders_screen.dart';
import 'fixtures_screen.dart';
import 'network_screen.dart';
import 'scenes_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  static const _pages = [
    FadersScreen(),
    FixturesScreen(),
    ScenesScreen(),
    NetworkScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _tab, children: _pages)),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _MasterBar(),
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.tune), label: 'Fader'),
              NavigationDestination(icon: Icon(Icons.lightbulb_outline), label: 'Geräte'),
              NavigationDestination(icon: Icon(Icons.auto_awesome_motion), label: 'Szenen'),
              NavigationDestination(icon: Icon(Icons.wifi_tethering), label: 'Netzwerk'),
            ],
          ),
        ],
      ),
    );
  }
}

/// Grandmaster + Blackout, immer sichtbar.
class _MasterBar extends StatelessWidget {
  const _MasterBar();

  @override
  Widget build(BuildContext context) {
    return AppListener(builder: (context, app) {
      final e = app.engine;
      final scheme = Theme.of(context).colorScheme;
      return Material(
        color: scheme.surfaceContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
          child: Row(
            children: [
              const Text('GM', style: TextStyle(fontWeight: FontWeight.bold)),
              Expanded(
                child: Slider(
                  value: e.grandMaster,
                  onChanged: (v) => e.grandMaster = v,
                ),
              ),
              SizedBox(
                width: 40,
                child: Text('${(e.grandMaster * 100).round()}%',
                    textAlign: TextAlign.right),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: e.blackout ? Colors.red : scheme.surfaceContainerHighest,
                  foregroundColor: e.blackout ? Colors.white : scheme.onSurface,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: () => e.blackout = !e.blackout,
                child: const Text('BO'),
              ),
            ],
          ),
        ),
      );
    });
  }
}
