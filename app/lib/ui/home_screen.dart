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
    return AppListener(
      engine: false,
      builder: (context, app) {
        final tablet = MediaQuery.sizeOf(context).shortestSide >= 600;
        final withPult = tablet || app.pultOnPhone;
        final pages = <(Widget, _Dest)>[
          (const FixturesScreen(), const _Dest(Icons.lightbulb_outline, Icons.lightbulb, 'Steuern')),
          if (withPult)
            (const PultScreen(), const _Dest(Icons.dashboard_customize_outlined, Icons.dashboard_customize, 'Pult')),
          (LiveScreen(active: _tab == (withPult ? 2 : 1)), const _Dest(Icons.bolt_outlined, Icons.bolt, 'Live')),
          (const ScenesScreen(), const _Dest(Icons.auto_awesome_outlined, Icons.auto_awesome, 'Szenen')),
          (const FadersScreen(), const _Dest(Icons.tune_outlined, Icons.tune, 'Fader')),
          (const SettingsScreen(), const _Dest(Icons.settings_outlined, Icons.settings, 'Mehr')),
        ];
        final tab = _tab.clamp(0, pages.length - 1);
        final current = pages[tab].$1;
        // Pult hat eigene Master-Fader, Einstellungen brauchen keine
        final showMaster = current is! SettingsScreen && current is! PultScreen;
        final open = app.navOpen ?? tablet;

        return Scaffold(
          body: Stack(children: [
            Row(children: [
              _SideBar(
                open: open,
                selected: tab,
                destinations: [for (final p in pages) p.$2],
                onSelect: (i) => setState(() => _tab = i),
                onClose: () => app.setNavOpen(false),
              ),
              Expanded(
                child: Column(children: [
                  Expanded(
                    child: MediaQuery.removePadding(
                      context: context,
                      removeLeft: open,
                      removeBottom: showMaster,
                      child: IndexedStack(index: tab, children: [for (final p in pages) p.$1]),
                    ),
                  ),
                  if (showMaster) const SafeArea(top: false, left: false, child: MasterBar()),
                ]),
              ),
            ]),
            if (!open) _SideHandle(onOpen: () => app.setNavOpen(true)),
          ]),
        );
      },
    );
  }
}

class _Dest {
  const _Dest(this.icon, this.selectedIcon, this.label);
  final IconData icon, selectedIcon;
  final String label;
}

/// Ein- und ausklappbare Navigation am linken Rand (ersetzt die untere Leiste).
class _SideBar extends StatelessWidget {
  const _SideBar({
    required this.open,
    required this.selected,
    required this.destinations,
    required this.onSelect,
    required this.onClose,
  });
  final bool open;
  final int selected;
  final List<_Dest> destinations;
  final ValueChanged<int> onSelect;
  final VoidCallback onClose;

  static const width = 76.0;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final pad = MediaQuery.paddingOf(context).left;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: open ? width + pad : 0,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: s.surfaceContainer,
        border: Border(right: BorderSide(color: s.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: OverflowBox(
        alignment: Alignment.centerRight,
        minWidth: width + pad,
        maxWidth: width + pad,
        child: SafeArea(
          right: false,
          child: Column(children: [
            const SizedBox(height: 6),
            IconButton(
              tooltip: 'Seitenleiste einklappen',
              icon: const Icon(Icons.keyboard_double_arrow_left),
              onPressed: onClose,
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  // Auf flachen Bildschirmen (Handy quer) dichter packen
                  final h = (c.maxHeight / destinations.length).clamp(44.0, 72.0);
                  return SingleChildScrollView(
                    child: Column(children: [
                      for (var i = 0; i < destinations.length; i++)
                        _SideItem(
                          dest: destinations[i],
                          selected: i == selected,
                          height: h,
                          onTap: () => onSelect(i),
                        ),
                    ]),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _SideItem extends StatelessWidget {
  const _SideItem({required this.dest, required this.selected, required this.height, required this.onTap});
  final _Dest dest;
  final bool selected;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final compact = height < 60;
    return SizedBox(
      height: height,
      width: _SideBar.width,
      child: InkWell(
        onTap: onTap,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 52,
            height: compact ? 28 : 32,
            decoration: BoxDecoration(
              color: selected ? s.secondaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(selected ? dest.selectedIcon : dest.icon,
                size: compact ? 20 : 24, color: selected ? s.onSecondaryContainer : s.onSurfaceVariant),
          ),
          if (!compact || height >= 48) ...[
            const SizedBox(height: 2),
            Text(dest.label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: compact ? 10 : 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? s.onSurface : s.onSurfaceVariant,
                )),
          ],
        ]),
      ),
    );
  }
}

/// Griff am linken Rand bei eingeklappter Leiste: antippen oder nach rechts wischen.
class _SideHandle extends StatelessWidget {
  const _SideHandle({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      child: Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onOpen,
          onHorizontalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) > 100) onOpen();
          },
          child: Tooltip(
            message: 'Navigation ausklappen',
            child: Container(
              width: 22,
              height: 72,
              decoration: BoxDecoration(
                color: s.primaryContainer.withValues(alpha: 0.92),
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 6)],
              ),
              child: Icon(Icons.chevron_right, size: 20, color: s.onPrimaryContainer),
            ),
          ),
        ),
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
