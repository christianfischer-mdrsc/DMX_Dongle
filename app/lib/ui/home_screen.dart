import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'faders_screen.dart';
import 'fixtures_screen.dart';
import 'live_screen.dart';
import 'network_screen.dart';
import 'scenes_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  static const _settingsTab = 4;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: [
        const FixturesScreen(),
        LiveScreen(active: _tab == 1),
        const ScenesScreen(),
        const FadersScreen(),
        const SettingsScreen(),
      ]),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_tab != _settingsTab) const MasterBar(),
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.lightbulb_outline),
                  selectedIcon: Icon(Icons.lightbulb),
                  label: 'Steuern'),
              NavigationDestination(
                  icon: Icon(Icons.bolt_outlined),
                  selectedIcon: Icon(Icons.bolt),
                  label: 'Live'),
              NavigationDestination(
                  icon: Icon(Icons.auto_awesome_outlined),
                  selectedIcon: Icon(Icons.auto_awesome),
                  label: 'Szenen'),
              NavigationDestination(
                  icon: Icon(Icons.tune_outlined),
                  selectedIcon: Icon(Icons.tune),
                  label: 'Fader'),
              NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: 'Mehr'),
            ],
          ),
        ],
      ),
    );
  }
}

/// Gesamthelligkeit + Blackout, über den Steuer-Tabs immer erreichbar.
class MasterBar extends StatelessWidget {
  const MasterBar({super.key});

  @override
  Widget build(BuildContext context) {
    return AppListener(builder: (context, app) {
      final e = app.engine;
      final s = Theme.of(context).colorScheme;
      return Container(
        color: s.surfaceContainerLowest,
        padding: const EdgeInsets.fromLTRB(16, 6, 12, 2),
        child: Row(children: [
          Icon(Icons.brightness_6_outlined, size: 20, color: s.onSurfaceVariant),
          Expanded(
            child: Slider(
              value: e.grandMaster,
              onChanged: (v) => e.grandMaster = v,
            ),
          ),
          SizedBox(
            width: 44,
            child: Text('${(e.grandMaster * 100).round()} %',
                textAlign: TextAlign.right,
                style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
          ),
          const SizedBox(width: 10),
          FilterChip(
            label: const Text('Blackout'),
            selected: e.blackout,
            showCheckmark: false,
            selectedColor: s.error,
            labelStyle: TextStyle(
              color: e.blackout ? s.onError : s.onSurface,
              fontWeight: FontWeight.w600,
            ),
            onSelected: (v) => e.blackout = v,
          ),
        ]),
      );
    });
  }
}

/// Zeigt, wohin gesendet wird. Tippen öffnet die Dongle-Einstellungen.
class ConnectionChip extends StatelessWidget {
  const ConnectionChip({super.key});

  @override
  Widget build(BuildContext context) {
    return AppListener(
      engine: false,
      builder: (context, app) {
        final ip = app.network.nodeIp;
        final s = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.only(right: 12),
          child: ActionChip(
            avatar: Icon(Icons.circle, size: 10, color: ip == null ? s.outline : const Color(0xFF22A55B)),
            label: Text(ip == null ? 'Kein Dongle' : ip),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NetworkScreen()),
            ),
          ),
        );
      },
    );
  }
}
