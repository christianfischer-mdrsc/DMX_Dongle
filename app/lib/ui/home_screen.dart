import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'faders_screen.dart';
import 'fixtures_screen.dart';
import 'live_screen.dart';
import 'network_screen.dart';
import 'pult_screen.dart';
import 'scenes_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    // Tablet (quer oder groß): zusätzlicher Tab „Pult“
    final tablet = MediaQuery.sizeOf(context).shortestSide >= 600;
    final pages = <(Widget, NavigationDestination)>[
      (
        const FixturesScreen(),
        const NavigationDestination(
            icon: Icon(Icons.lightbulb_outline), selectedIcon: Icon(Icons.lightbulb), label: 'Steuern')
      ),
      if (tablet)
        (
          const PultScreen(),
          const NavigationDestination(
              icon: Icon(Icons.dashboard_customize_outlined),
              selectedIcon: Icon(Icons.dashboard_customize),
              label: 'Pult')
        ),
      (
        LiveScreen(active: _tab == (tablet ? 2 : 1)),
        const NavigationDestination(icon: Icon(Icons.bolt_outlined), selectedIcon: Icon(Icons.bolt), label: 'Live')
      ),
      (
        const ScenesScreen(),
        const NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'Szenen')
      ),
      (
        const FadersScreen(),
        const NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: 'Fader')
      ),
      (
        const SettingsScreen(),
        const NavigationDestination(
            icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Mehr')
      ),
    ];
    final tab = _tab.clamp(0, pages.length - 1);
    final current = pages[tab].$1;
    // Pult hat eigene Master-Fader, Einstellungen brauchen keine
    final showMaster = current is! SettingsScreen && current is! PultScreen;

    return Scaffold(
      body: IndexedStack(index: tab, children: [for (final p in pages) p.$1]),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showMaster) const MasterBar(),
          NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [for (final p in pages) p.$2],
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
