import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import 'app_scope.dart';
import 'effect_editor.dart';
import 'fixture_control_screen.dart';
import 'home_screen.dart';

/// Profi-Ansicht fürs Tablet – aufgebaut wie ein Lichtpult:
/// links Geräte- und Gruppen-Pool, Mitte der Programmer der Auswahl,
/// rechts Szenen, Chaser und Effekte, unten die Playback-Fader.
class PultScreen extends StatefulWidget {
  const PultScreen({super.key});

  @override
  State<PultScreen> createState() => _PultScreenState();
}

class _PultScreenState extends State<PultScreen> {
  final List<String> _selection = []; // Reihenfolge der Auswahl zählt (Effekte)
  int _rightTab = 0;

  void _toggle(String id) => setState(() => _selection.contains(id) ? _selection.remove(id) : _selection.add(id));

  void _selectGroup(FixtureGroup g) => setState(() {
        final all = g.fixtureIds.every(_selection.contains);
        if (all) {
          _selection.removeWhere(g.fixtureIds.contains);
        } else {
          for (final id in g.fixtureIds) {
            if (!_selection.contains(id)) _selection.add(id);
          }
        }
      });

  @override
  Widget build(BuildContext context) {
    return AppListener(
      engine: false,
      builder: (context, app) {
        _selection.removeWhere((id) => app.fixtureById(id) == null);
        final chosen = app.fixturesByIds(_selection);
        final w = MediaQuery.sizeOf(context).width;
        final threeCols = w >= 1100;
        final s = Theme.of(context).colorScheme;

        final pools = _PoolPanel(
          app: app,
          selection: _selection,
          onToggle: _toggle,
          onGroup: _selectGroup,
          onClear: () => setState(_selection.clear),
          onAll: () => setState(() => _selection
            ..clear()
            ..addAll(app.fixtures.map((f) => f.id))),
        );
        final programmer = _ProgrammerPanel(app: app, chosen: chosen);
        final playback = _PlaybackPanel(
          app: app,
          tab: _rightTab,
          onTab: (i) => setState(() => _rightTab = i),
          selection: chosen,
        );

        Widget panel(Widget child) => Container(
              decoration: BoxDecoration(
                color: s.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: s.outlineVariant.withValues(alpha: 0.5)),
              ),
              clipBehavior: Clip.antiAlias,
              child: child,
            );

        return Scaffold(
          appBar: AppBar(
            title: const Text('Pult'),
            actions: [
              if (chosen.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Chip(label: Text('${chosen.length} gewählt')),
                ),
              const ConnectionChip(),
            ],
          ),
          body: Column(children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                child: threeCols
                    ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        SizedBox(width: 340, child: panel(pools)),
                        const SizedBox(width: 8),
                        Expanded(child: panel(programmer)),
                        const SizedBox(width: 8),
                        SizedBox(width: 300, child: panel(playback)),
                      ])
                    : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        SizedBox(width: 300, child: panel(pools)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(children: [
                            Expanded(flex: 3, child: panel(programmer)),
                            const SizedBox(height: 8),
                            Expanded(flex: 2, child: panel(playback)),
                          ]),
                        ),
                      ]),
              ),
            ),
            _FaderWing(app: app),
          ]),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- Pools

class _PoolPanel extends StatelessWidget {
  const _PoolPanel({
    required this.app,
    required this.selection,
    required this.onToggle,
    required this.onGroup,
    required this.onClear,
    required this.onAll,
  });
  final AppState app;
  final List<String> selection;
  final ValueChanged<String> onToggle;
  final ValueChanged<FixtureGroup> onGroup;
  final VoidCallback onClear;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    final n = app.engine.universeCount;
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: _PanelTitle('Geräte', trailing: [
          TextButton(onPressed: onAll, child: const Text('Alle')),
          TextButton(onPressed: selection.isEmpty ? null : onClear, child: const Text('Leeren')),
        ]),
      ),
      if (app.groups.isNotEmpty) ...[
        const SliverToBoxAdapter(child: _SubTitle('GRUPPEN')),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 110, mainAxisExtent: 52, mainAxisSpacing: 6, crossAxisSpacing: 6),
            itemCount: app.groups.length,
            itemBuilder: (context, i) {
              final g = app.groups[i];
              final on = g.fixtureIds.isNotEmpty && g.fixtureIds.every(selection.contains);
              return _PoolKey(
                label: g.name,
                sub: '${g.fixtureIds.length}',
                selected: on,
                icon: Icons.workspaces_outline,
                onTap: () => onGroup(g),
              );
            },
          ),
        ),
      ],
      for (var u = 0; u < n; u++) ...[
        SliverToBoxAdapter(child: _SubTitle('UNIVERSUM ${u + 1}')),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 110, mainAxisExtent: 74, mainAxisSpacing: 6, crossAxisSpacing: 6),
            itemCount: app.fixturesIn(u).length,
            itemBuilder: (context, i) {
              final f = app.fixturesIn(u)[i];
              return _FixtureKey(
                app: app,
                fixture: f,
                index: selection.indexOf(f.id),
                onTap: () => onToggle(f.id),
              );
            },
          ),
        ),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 12)),
    ]);
  }
}

/// Ein Gerät im Pool mit Live-Farbe und Auswahlnummer.
class _FixtureKey extends StatelessWidget {
  const _FixtureKey({required this.app, required this.fixture, required this.index, required this.onTap});
  final AppState app;
  final Fixture fixture;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final selected = index >= 0;
    return Material(
      color: selected ? s.primaryContainer : s.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: ValueListenableBuilder<int>(
            valueListenable: app.engine.live,
            builder: (context, _, __) {
              final level = app.fixtureLevel(fixture, live: true);
              final color = app.fixtureColor(fixture, live: true) ??
                  Color.lerp(s.surfaceContainerHighest, const Color(0xFFFFC94D), level)!;
              final fx = app.fixtureHasEffect(fixture);
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: level > 0.01 ? color : Colors.transparent,
                      border: Border.all(color: s.outline, width: 1),
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (fx)
                    const Text('FX', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFFFFB020))),
                  const Spacer(),
                  if (selected)
                    Text('${index + 1}',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: s.primary)),
                ]),
                const Spacer(),
                Text(fixture.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                Text('${fixture.address}',
                    style: TextStyle(fontSize: 10, color: s.onSurfaceVariant)),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: level,
                    minHeight: 3,
                    color: fx ? const Color(0xFFFFB020) : null,
                    backgroundColor: s.surface,
                  ),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}

class _PoolKey extends StatelessWidget {
  const _PoolKey({
    required this.label,
    required this.selected,
    required this.onTap,
    this.sub,
    this.icon,
    this.active = false,
    this.onLongPress,
  });
  final String label;
  final String? sub;
  final IconData? icon;
  final bool selected;
  final bool active; // läuft gerade (grün)
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    const green = Color(0xFF22A55B);
    return Material(
      color: active
          ? green.withValues(alpha: 0.22)
          : selected
              ? s.primaryContainer
              : s.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: active ? green : Colors.transparent, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: active ? green : s.onSurfaceVariant),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  if (sub != null)
                    Text(sub!, maxLines: 1, style: TextStyle(fontSize: 10, color: s.onSurfaceVariant)),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Programmer

class _ProgrammerPanel extends StatelessWidget {
  const _ProgrammerPanel({required this.app, required this.chosen});
  final AppState app;
  final List<Fixture> chosen;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final title = chosen.isEmpty
        ? 'Programmer'
        : chosen.length == 1
            ? chosen.first.name
            : '${chosen.length} Geräte';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _PanelTitle(title, trailing: [
        IconButton(
          tooltip: 'Finden (blinken lassen)',
          icon: const Icon(Icons.flare),
          onPressed: chosen.isEmpty ? null : () => app.identify(chosen),
        ),
        IconButton(
          tooltip: 'Auswahl an',
          icon: const Icon(Icons.light_mode_outlined),
          onPressed: chosen.isEmpty ? null : () => app.allOn(chosen),
        ),
        IconButton(
          tooltip: 'Auswahl aus',
          icon: const Icon(Icons.dark_mode_outlined),
          onPressed: chosen.isEmpty ? null : () => app.allOff(chosen),
        ),
        IconButton(
          tooltip: 'Effekt auf Auswahl',
          icon: const Icon(Icons.auto_awesome_motion),
          onPressed: chosen.isEmpty
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => EffectEditor(fixtureIds: chosen.map((f) => f.id).toList()))),
        ),
        IconButton(
          tooltip: 'Als Szene speichern',
          icon: const Icon(Icons.save_outlined),
          onPressed: () => _storeScene(context, app),
        ),
      ]),
      Divider(height: 1, color: s.outlineVariant),
      Expanded(
        child: chosen.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Links Geräte oder Gruppen antippen.\nDie Reihenfolge der Auswahl bestimmt, wie Effekte laufen.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: s.onSurfaceVariant),
                  ),
                ),
              )
            : FixtureProgrammer(
                key: ValueKey(chosen.map((f) => f.id).join(',')),
                fixtures: chosen,
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
              ),
      ),
    ]);
  }
}

Future<void> _storeScene(BuildContext context, AppState app) async {
  final ctrl = TextEditingController(text: 'Szene ${app.scenes.length + 1}');
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Aktuelles Bild als Szene speichern'),
      content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: 'Name')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Speichern')),
      ],
    ),
  );
  if (name != null && name.isNotEmpty) app.saveScene(name);
}

// ---------------------------------------------------------------- Szenen / Chaser / Effekte

class _PlaybackPanel extends StatelessWidget {
  const _PlaybackPanel({required this.app, required this.tab, required this.onTab, required this.selection});
  final AppState app;
  final int tab;
  final ValueChanged<int> onTab;
  final List<Fixture> selection;

  @override
  Widget build(BuildContext context) {
    final e = app.engine;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
        child: SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 0, label: Text('Szenen (${app.scenes.length})')),
            ButtonSegment(value: 1, label: Text('Chaser (${app.chases.length})')),
            ButtonSegment(value: 2, label: Text('Effekte (${app.effects.length})')),
          ],
          selected: {tab},
          onSelectionChanged: (v) => onTab(v.first),
        ),
      ),
      Expanded(
        child: ListenableBuilder(
          listenable: e,
          builder: (context, _) {
            final items = switch (tab) {
              0 => [
                  for (final sc in app.scenes)
                    _PoolKey(
                      label: sc.name,
                      sub: sc.fadeMs > 0 ? 'Fade ${(sc.fadeMs / 1000).toStringAsFixed(1)} s' : 'Sofort',
                      icon: Icons.photo_outlined,
                      selected: false,
                      onTap: () => e.recallScene(sc),
                    ),
                ],
              1 => [
                  for (final c in app.chases)
                    _PoolKey(
                      label: c.name,
                      sub: '${c.steps.length} Schritte',
                      icon: Icons.repeat,
                      selected: false,
                      active: e.activeChaseId == c.id,
                      onTap: () => e.activeChaseId == c.id ? e.stopChase() : app.playChase(c),
                    ),
                ],
              _ => [
                  for (final fx in app.effects)
                    _PoolKey(
                      label: fx.name,
                      sub: fx.type.label,
                      icon: Icons.auto_awesome_motion,
                      selected: false,
                      active: app.isEffectRunning(fx),
                      onTap: () => app.toggleEffect(fx),
                      onLongPress: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => EffectEditor(effect: fx))),
                    ),
                ],
            };
            if (items.isEmpty) {
              return Center(
                child: Text(
                  switch (tab) {
                    0 => 'Noch keine Szenen.\nMit 💾 im Programmer speichern.',
                    1 => 'Noch keine Chaser.\nIm Tab „Szenen“ anlegen.',
                    _ => selection.isEmpty
                        ? 'Noch keine Effekte.\nGeräte wählen und ✨ tippen.'
                        : 'Noch keine Effekte.\nOben ✨ tippen.',
                  },
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              );
            }
            return GridView(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 140, mainAxisExtent: 56, mainAxisSpacing: 6, crossAxisSpacing: 6),
              children: items,
            );
          },
        ),
      ),
      if (tab == 2 && e.runningEffects.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Alle Effekte stoppen'),
            onPressed: e.stopAllEffects,
          ),
        ),
    ]);
  }
}

// ---------------------------------------------------------------- Fader-Wing

/// Untere Leiste wie die Playback-Fader eines Pults:
/// ein Master je Gruppe, Grandmaster, Blackout, Tempo.
class _FaderWing extends StatelessWidget {
  const _FaderWing({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Material(
      color: s.surfaceContainerLowest,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 196,
          child: ListenableBuilder(
            listenable: Listenable.merge([app, app.engine]),
            builder: (context, _) {
              final e = app.engine;
              return Row(children: [
                Expanded(
                  child: app.groups.isEmpty
                      ? Center(
                          child: Text(
                            'Gruppen anlegen (im Tab „Steuern“ Lampen wählen → Gruppe speichern),\n'
                            'dann bekommt jede Gruppe hier einen eigenen Fader.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: s.onSurfaceVariant),
                          ),
                        )
                      : ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          children: [
                            for (final g in app.groups)
                              _WingFader(
                                label: g.name,
                                value: app.groupMaster(g),
                                onChanged: (v) => app.setGroupMaster(g, v),
                              ),
                          ],
                        ),
                ),
                VerticalDivider(width: 1, color: s.outlineVariant),
                _WingFader(
                  label: 'Grand\nMaster',
                  value: e.grandMaster,
                  color: s.primary,
                  onChanged: (v) => e.grandMaster = v,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
                  child: SizedBox(
                    width: 120,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: e.blackout ? s.error : s.surfaceContainerHighest,
                            foregroundColor: e.blackout ? s.onError : s.onSurface,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () => e.blackout = !e.blackout,
                          child: const FittedBox(child: Text('BLACKOUT', style: TextStyle(fontWeight: FontWeight.w800))),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: e.tap,
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const Text('TAP', style: TextStyle(fontWeight: FontWeight.w800)),
                            Text('${e.bpm.round()} BPM',
                                style: const TextStyle(
                                    fontSize: 11, fontFeatures: [FontFeature.tabularFigures()])),
                          ]),
                        ),
                      ),
                    ]),
                  ),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}

class _WingFader extends StatelessWidget {
  const _WingFader({required this.label, required this.value, required this.onChanged, this.color});
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return SizedBox(
      width: 72,
      child: Column(children: [
        const SizedBox(height: 8),
        Text('${(value * 100).round()}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 10,
                activeTrackColor: color,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
              ),
              child: Slider(value: value, onChanged: onChanged),
            ),
          ),
        ),
        SizedBox(
          height: 30,
          child: Text(label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, height: 1.1, color: s.onSurfaceVariant)),
        ),
        const SizedBox(height: 6),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Kleinteile

class _PanelTitle extends StatelessWidget {
  const _PanelTitle(this.text, {this.trailing = const []});
  final String text;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 4, 2),
      child: Row(children: [
        Expanded(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        ),
        ...trailing,
      ]),
    );
  }
}

class _SubTitle extends StatelessWidget {
  const _SubTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Text(text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              )),
    );
  }
}
