import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import 'app_scope.dart';
import 'effect_editor.dart';
import 'fixture_control_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

/// Startseite: alle Geräte als Kacheln, nach Universen getrennt.
/// Tippen = steuern, lang drücken = mehrere auswählen.
/// „Anordnen“: Kacheln per Ziehen in eine eigene Reihenfolge bringen.
/// Tablet: Universen einzeln, nebeneinander oder untereinander.
class FixturesScreen extends StatefulWidget {
  const FixturesScreen({super.key});

  @override
  State<FixturesScreen> createState() => _FixturesScreenState();
}

class _FixturesScreenState extends State<FixturesScreen> with TickerProviderStateMixin {
  final Set<String> _selected = {};
  bool _arranging = false;
  TabController? _tabs;

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  /// TabController passend zur Zahl der Universen halten.
  TabController _tabsFor(int n) {
    final t = _tabs;
    if (t != null && t.length == n) return t;
    final keep = t == null ? 0 : t.index.clamp(0, n - 1);
    t?.dispose();
    return _tabs = TabController(length: n, vsync: this, initialIndex: keep);
  }

  int get _currentUniverse => _tabs?.index ?? 0;

  void _open(List<Fixture> list) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => FixtureControlScreen(fixtures: list)),
      );

  void _toggle(String id) =>
      setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));

  Future<void> _saveGroup(AppState app, List<Fixture> chosen) async {
    final ctrl = TextEditingController(text: 'Gruppe ${app.groups.length + 1}');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${chosen.length} Lampen als Gruppe speichern'),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Speichern')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    app.saveGroup(name, chosen.map((f) => f.id).toList());
    setState(_selected.clear);
  }

  void _groupMenu(AppState app, FixtureGroup g) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(g.name, style: Theme.of(ctx).textTheme.titleMedium)),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('Steuern'),
            onTap: () {
              Navigator.pop(ctx);
              final list = app.fixturesByIds(g.fixtureIds);
              if (list.isNotEmpty) _open(list);
            },
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome_motion),
            title: const Text('Effekt starten'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => EffectEditor(fixtureIds: [...g.fixtureIds])));
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Umbenennen'),
            onTap: () async {
              Navigator.pop(ctx);
              final ctrl = TextEditingController(text: g.name);
              final name = await showDialog<String>(
                context: context,
                builder: (c2) => AlertDialog(
                  title: const Text('Gruppe umbenennen'),
                  content: TextField(controller: ctrl, autofocus: true),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c2), child: const Text('Abbrechen')),
                    FilledButton(onPressed: () => Navigator.pop(c2, ctrl.text.trim()), child: const Text('OK')),
                  ],
                ),
              );
              if (name != null && name.isNotEmpty) app.updateGroup(g, name: name);
            },
          ),
          ListTile(
            leading: const Icon(Icons.checklist),
            title: const Text('Auswahl übernehmen'),
            subtitle: const Text('Lampen der Gruppe wählen und bearbeiten'),
            onTap: () {
              Navigator.pop(ctx);
              setState(() => _selected
                ..clear()
                ..addAll(g.fixtureIds));
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Gruppe löschen'),
            subtitle: const Text('Die Lampen bleiben erhalten'),
            onTap: () {
              Navigator.pop(ctx);
              app.deleteGroup(g);
            },
          ),
        ]),
      ),
    );
  }

  void _add(AppState app, [int? universe]) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => AddFixtureSheet(app: app, initialUniverse: universe ?? _currentUniverse),
      );

  @override
  Widget build(BuildContext context) {
    return AppListener(
      engine: false,
      builder: (context, app) {
        _selected.removeWhere((id) => !app.fixtures.any((f) => f.id == id));
        final selecting = _selected.isNotEmpty && !_arranging;
        final chosen = app.fixtures.where((f) => _selected.contains(f.id)).toList();
        final n = app.engine.universeCount;
        final wide = MediaQuery.sizeOf(context).width >= 700;
        // Am Handy immer eine Seite pro Universe
        final layout = (wide && n > 1) ? app.controlLayout : ControlLayout.tabs;
        final tabs = layout == ControlLayout.tabs && n > 1 ? _tabsFor(n) : null;

        Widget universeBody(int u) => _UniverseGrid(
              app: app,
              universe: u,
              selected: _selected,
              arranging: _arranging,
              compact: layout == ControlLayout.columns,
              onTap: (f) => selecting ? _toggle(f.id) : _open([f]),
              onLongPress: (f) => _toggle(f.id),
              onAdd: () => _add(app, u),
            );

        final header = _Header(
          app: app,
          selecting: selecting,
          chosen: chosen,
          onGroupTap: (g) {
            final list = app.fixturesByIds(g.fixtureIds);
            if (list.isNotEmpty) _open(list);
          },
          onGroupLongPress: (g) => _groupMenu(app, g),
        );

        Widget body;
        if (app.fixtures.isEmpty) {
          body = _EmptyState(onAdd: () => _add(app));
        } else if (layout == ControlLayout.columns) {
          body = Column(children: [
            header,
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (var u = 0; u < n; u++) ...[
                  if (u > 0) VerticalDivider(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
                  Expanded(
                    child: Column(children: [
                      _UniverseTitle(app: app, universe: u, onAdd: () => _add(app, u)),
                      Expanded(child: universeBody(u)),
                    ]),
                  ),
                ],
              ]),
            ),
          ]);
        } else if (layout == ControlLayout.stacked) {
          body = CustomScrollView(slivers: [
            SliverToBoxAdapter(child: header),
            for (var u = 0; u < n; u++) ...[
              SliverToBoxAdapter(child: _UniverseTitle(app: app, universe: u, onAdd: () => _add(app, u))),
              _UniverseGrid.sliver(
                app: app,
                universe: u,
                selected: _selected,
                arranging: _arranging,
                onTap: (f) => selecting ? _toggle(f.id) : _open([f]),
                onLongPress: (f) => _toggle(f.id),
                bottom: u == n - 1 ? 96 : 8,
              ),
            ],
          ]);
        } else if (tabs != null) {
          body = Column(children: [
            header,
            TabBar(
              controller: tabs,
              tabs: [
                for (var u = 0; u < n; u++)
                  Tab(text: 'Universum ${u + 1} (${app.fixturesIn(u).length})'),
              ],
            ),
            Expanded(
              child: TabBarView(controller: tabs, children: [
                for (var u = 0; u < n; u++) universeBody(u),
              ]),
            ),
          ]);
        } else {
          body = Column(children: [header, Expanded(child: universeBody(0))]);
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(_arranging
                ? 'Anordnen'
                : selecting
                    ? '${_selected.length} ausgewählt'
                    : 'Steuern'),
            leading: selecting
                ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_selected.clear))
                : null,
            actions: selecting
                ? [
                    IconButton(
                      tooltip: 'Finden (blinken lassen)',
                      icon: const Icon(Icons.flare),
                      onPressed: () => app.identify(chosen),
                    ),
                    IconButton(
                      tooltip: 'Effekt starten',
                      icon: const Icon(Icons.auto_awesome_motion),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => EffectEditor(fixtureIds: chosen.map((f) => f.id).toList()))),
                    ),
                    IconButton(
                      tooltip: 'Als Gruppe speichern',
                      icon: const Icon(Icons.workspaces_outline),
                      onPressed: () => _saveGroup(app, chosen),
                    ),
                    IconButton(
                      tooltip: 'Alle wählen',
                      icon: const Icon(Icons.select_all),
                      onPressed: () => setState(() => _selected.addAll(app.fixtures.map((f) => f.id))),
                    ),
                  ]
                : [
                    if (wide && n > 1 && !_arranging)
                      PopupMenuButton<ControlLayout>(
                        tooltip: 'Anordnung der Universen',
                        icon: Icon(switch (app.controlLayout) {
                          ControlLayout.tabs => Icons.tab_outlined,
                          ControlLayout.columns => Icons.view_column_outlined,
                          ControlLayout.stacked => Icons.view_agenda_outlined,
                        }),
                        initialValue: app.controlLayout,
                        onSelected: app.setControlLayout,
                        itemBuilder: (_) => [
                          for (final l in ControlLayout.values)
                            CheckedPopupMenuItem(value: l, checked: l == app.controlLayout, child: Text(l.label)),
                        ],
                      ),
                    if (app.fixtures.isNotEmpty)
                      _arranging
                          ? TextButton(
                              onPressed: () => setState(() => _arranging = false),
                              child: const Text('Fertig'),
                            )
                          : IconButton(
                              tooltip: 'Anordnen (Reihenfolge ändern)',
                              icon: const Icon(Icons.swap_horiz),
                              onPressed: () => setState(() {
                                _arranging = true;
                                _selected.clear();
                              }),
                            ),
                    if (!_arranging) const ConnectionChip(),
                  ],
          ),
          floatingActionButton: _arranging
              ? null
              : selecting
                  ? FloatingActionButton.extended(
                      icon: const Icon(Icons.tune),
                      label: Text('${chosen.length} steuern'),
                      onPressed: () => _open(chosen),
                    )
                  : app.fixtures.isEmpty
                      ? null
                      : FloatingActionButton(
                          tooltip: 'Gerät hinzufügen',
                          onPressed: () => _add(app),
                          child: const Icon(Icons.add),
                        ),
          body: body,
        );
      },
    );
  }
}

/// Kopf über den Universen: Hinweis, Alle an/aus, Gruppen.
class _Header extends StatelessWidget {
  const _Header({
    required this.app,
    required this.selecting,
    required this.chosen,
    required this.onGroupTap,
    required this.onGroupLongPress,
  });
  final AppState app;
  final bool selecting;
  final List<Fixture> chosen;
  final ValueChanged<FixtureGroup> onGroupTap;
  final ValueChanged<FixtureGroup> onGroupLongPress;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (app.announcement.isNotEmpty && !app.announcementDismissed) _Announcement(app: app),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.tonalIcon(
            icon: const Icon(Icons.light_mode_outlined, size: 18),
            label: Text(selecting ? 'Auswahl an' : 'Alle an'),
            onPressed: () => app.allOn(selecting ? chosen : null),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.dark_mode_outlined, size: 18),
            label: Text(selecting ? 'Auswahl aus' : 'Alle aus'),
            onPressed: () => app.allOff(selecting ? chosen : null),
          ),
        ]),
      ),
      if (app.groups.isNotEmpty)
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            children: [
              for (final g in app.groups)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onLongPress: () => onGroupLongPress(g),
                    child: ActionChip(
                      avatar: const Icon(Icons.workspaces_outline, size: 18),
                      label: Text('${g.name} (${g.fixtureIds.length})'),
                      onPressed: () => onGroupTap(g),
                    ),
                  ),
                ),
            ],
          ),
        ),
    ]);
  }
}

/// Überschrift eines Universe mit Menü (an/aus, nach Adresse sortieren).
class _UniverseTitle extends StatelessWidget {
  const _UniverseTitle({required this.app, required this.universe, required this.onAdd});
  final AppState app;
  final int universe;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final list = app.fixturesIn(universe);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
      child: Row(children: [
        Text('UNIVERSUM ${universe + 1}',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: s.primary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                )),
        const SizedBox(width: 8),
        Text('${list.length} Lampen', style: TextStyle(color: s.onSurfaceVariant, fontSize: 13)),
        const Spacer(),
        _UniverseMenu(app: app, universe: universe, onAdd: onAdd),
      ]),
    );
  }
}

class _UniverseMenu extends StatelessWidget {
  const _UniverseMenu({required this.app, required this.universe, required this.onAdd});
  final AppState app;
  final int universe;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final list = app.fixturesIn(universe);
    return PopupMenuButton<String>(
      tooltip: 'Universum ${universe + 1}',
      onSelected: (v) {
        switch (v) {
          case 'on':
            app.allOn(list);
          case 'off':
            app.allOff(list);
          case 'sort':
            app.sortByAddress(universe);
          case 'add':
            onAdd();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'add', child: Text('Lampe hinzufügen')),
        PopupMenuItem(value: 'on', enabled: list.isNotEmpty, child: const Text('Alle in diesem Universum an')),
        PopupMenuItem(value: 'off', enabled: list.isNotEmpty, child: const Text('Alle in diesem Universum aus')),
        PopupMenuItem(value: 'sort', enabled: list.length > 1, child: const Text('Nach DMX-Adresse sortieren')),
      ],
    );
  }
}

/// Kachelraster eines Universe (eigene Scrollfläche oder als Sliver).
class _UniverseGrid extends StatelessWidget {
  const _UniverseGrid({
    required this.app,
    required this.universe,
    required this.selected,
    required this.arranging,
    required this.onTap,
    required this.onLongPress,
    required this.onAdd,
    this.compact = false,
  });

  final AppState app;
  final int universe;
  final Set<String> selected;
  final bool arranging;
  final bool compact;
  final ValueChanged<Fixture> onTap;
  final ValueChanged<Fixture> onLongPress;
  final VoidCallback onAdd;

  static Widget sliver({
    required AppState app,
    required int universe,
    required Set<String> selected,
    required bool arranging,
    required ValueChanged<Fixture> onTap,
    required ValueChanged<Fixture> onLongPress,
    double bottom = 8,
  }) {
    final list = app.fixturesIn(universe);
    if (list.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text('Keine Lampen in diesem Universum.'),
        ),
      );
    }
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, bottom),
      sliver: SliverGrid.builder(
        gridDelegate: _gridDelegate(false),
        itemCount: list.length,
        itemBuilder: (context, i) => _tile(app, list[i], selected, arranging, onTap, onLongPress),
      ),
    );
  }

  static SliverGridDelegate _gridDelegate(bool compact) => SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: compact ? 190 : 220,
        mainAxisExtent: compact ? 136 : 150,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      );

  static Widget _tile(AppState app, Fixture f, Set<String> selected, bool arranging,
      ValueChanged<Fixture> onTap, ValueChanged<Fixture> onLongPress) {
    final tile = _FixtureTile(
      fixture: f,
      app: app,
      selected: selected.contains(f.id),
      arranging: arranging,
      onTap: arranging ? null : () => onTap(f),
      onLongPress: arranging ? null : () => onLongPress(f),
    );
    return arranging ? _ReorderTile(app: app, fixture: f, child: tile) : tile;
  }

  @override
  Widget build(BuildContext context) {
    final list = app.fixturesIn(universe);
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Keine Lampen in Universum ${universe + 1}.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Lampe hinzufügen')),
          ]),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      gridDelegate: _gridDelegate(compact),
      itemCount: list.length,
      itemBuilder: (context, i) => _tile(app, list[i], selected, arranging, onTap, onLongPress),
    );
  }
}

/// Kachel im Anordnen-Modus: gedrückt halten und auf eine andere Kachel ziehen.
class _ReorderTile extends StatelessWidget {
  const _ReorderTile({required this.app, required this.fixture, required this.child});
  final AppState app;
  final Fixture fixture;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) {
        final other = app.fixtureById(d.data);
        return other != null && other.id != fixture.id && other.universe == fixture.universe;
      },
      onAcceptWithDetails: (d) {
        final from = app.fixtures.indexWhere((f) => f.id == d.data);
        final to = app.fixtures.indexOf(fixture);
        app.moveFixture(d.data, fixture.id, after: from < to);
      },
      builder: (context, candidates, _) {
        final hover = candidates.isNotEmpty;
        return LayoutBuilder(
          builder: (context, c) => LongPressDraggable<String>(
            data: fixture.id,
            delay: const Duration(milliseconds: 150),
            feedback: Material(
              color: Colors.transparent,
              child: SizedBox(
                width: c.maxWidth,
                height: c.maxHeight,
                child: Opacity(opacity: 0.9, child: child),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.3, child: child),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: hover ? s.primary : Colors.transparent, width: 3),
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Hinweis an alle, gepflegt im Admin-Bereich.
class _Announcement extends StatelessWidget {
  const _Announcement({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Card(
        color: s.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(children: [
            Icon(Icons.campaign_outlined, color: s.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(child: Text(app.announcement, style: TextStyle(color: s.onSecondaryContainer))),
            IconButton(
              tooltip: 'Ausblenden',
              icon: Icon(Icons.close, color: s.onSecondaryContainer),
              onPressed: app.dismissAnnouncement,
            ),
          ]),
        ),
      ),
    );
  }
}

class _FixtureTile extends StatelessWidget {
  const _FixtureTile({
    required this.fixture,
    required this.app,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    this.arranging = false,
  });

  final Fixture fixture;
  final AppState app;
  final bool selected;
  final bool arranging;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final p = app.profileOf(fixture);

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected ? s.primary : s.outlineVariant.withValues(alpha: 0.6),
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(14),
          // Farbe und Helligkeit live: zeigt auch Effekte, Grandmaster, Blackout
          child: ValueListenableBuilder<int>(
            valueListenable: app.engine.live,
            builder: (context, _, __) {
              final level = app.fixtureLevel(fixture, live: true);
              final color = app.fixtureColor(fixture, live: true);
              final fx = app.fixtureHasEffect(fixture);
              final on = level > 0.01;
              final lamp = color ?? Color.lerp(s.surfaceContainerHighest, const Color(0xFFFFC94D), level)!;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: on ? lamp : s.surfaceContainerHighest,
                      boxShadow: on
                          ? [BoxShadow(color: lamp.withValues(alpha: 0.55), blurRadius: 16, spreadRadius: 1)]
                          : null,
                    ),
                    child: Icon(Icons.lightbulb_outline,
                        size: 18, color: on ? Colors.black.withValues(alpha: 0.55) : s.onSurfaceVariant),
                  ),
                  const SizedBox(width: 8),
                  if (fx)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFB020).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('FX',
                          style: TextStyle(color: Color(0xFFB26A00), fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                  const Spacer(),
                  if (arranging) Icon(Icons.drag_indicator, color: s.onSurfaceVariant),
                  if (selected && !arranging) Icon(Icons.check_circle, color: s.primary),
                ]),
                const Spacer(),
                Text(fixture.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text(
                  '${p?.name ?? 'Unbekannt'} · U${fixture.universe + 1}.${fixture.address}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: s.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: level,
                    minHeight: 5,
                    color: fx ? const Color(0xFFFFB020) : null,
                    backgroundColor: s.surfaceContainerHighest,
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(color: s.primaryContainer, shape: BoxShape.circle),
            child: Icon(Icons.lightbulb_outline, size: 44, color: s.onPrimaryContainer),
          ),
          const SizedBox(height: 20),
          Text('Noch keine Lampen', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Füge deine Lampen mit ihrer DMX-Adresse hinzu. Danach steuerst du sie hier mit einem Tipp.',
            textAlign: TextAlign.center,
            style: TextStyle(color: s.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Lampe hinzufügen')),
        ]),
      ),
    );
  }
}

// ---------------- Hinzufügen ----------------

class AddFixtureSheet extends StatefulWidget {
  const AddFixtureSheet({super.key, required this.app, this.initialUniverse = 0});
  final AppState app;
  final int initialUniverse;

  @override
  State<AddFixtureSheet> createState() => _AddFixtureSheetState();
}

class _AddFixtureSheetState extends State<AddFixtureSheet> {
  late FixtureProfile _profile = widget.app.profiles[1];
  late int _universe = widget.initialUniverse.clamp(0, widget.app.engine.universeCount - 1);
  int _count = 1;
  final _name = TextEditingController(text: 'Spot');
  final _address = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _suggestAddress();
  }

  void _suggestAddress() {
    final a = widget.app.nextFreeAddress(_universe, _profile.footprint);
    _address.text = a?.toString() ?? '';
  }

  void _submit() {
    final addr = int.tryParse(_address.text);
    final total = _profile.footprint * _count;
    if (addr == null || addr < 1 || addr + total - 1 > 512) {
      setState(() => _error = 'Startadresse muss zwischen 1 und ${513 - total} liegen.');
      return;
    }
    final clash = widget.app.overlapping(_universe, addr, total);
    if (clash != null) {
      setState(() => _error = 'Adressen überschneiden sich mit „${clash.name}“.');
      return;
    }
    widget.app.addFixtures(
        _profile, _name.text.trim().isEmpty ? _profile.name : _name.text.trim(), _universe, addr, _count);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final s = Theme.of(context).colorScheme;
    final locked = !app.isUnlocked(_profile);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text('Lampe hinzufügen', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          DropdownButtonFormField<FixtureProfile>(
            initialValue: _profile,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Gerätetyp'),
            items: [
              for (final p in app.profiles)
                DropdownMenuItem(
                  value: p,
                  child: Row(children: [
                    Expanded(child: Text(p.label, overflow: TextOverflow.ellipsis)),
                    if (!app.isUnlocked(p)) Icon(Icons.lock_outline, size: 18, color: s.outline),
                  ]),
                ),
            ],
            onChanged: (p) => setState(() {
              _profile = p!;
              _error = null;
              _suggestAddress();
            }),
          ),
          if (locked) ...[
            const SizedBox(height: 12),
            Card(
              color: s.tertiaryContainer,
              child: ListTile(
                leading: Icon(Icons.lock_outline, color: s.onTertiaryContainer),
                title: Text('Gehört zum Paket „Pro-Geräte“',
                    style: TextStyle(color: s.onTertiaryContainer, fontWeight: FontWeight.w600)),
                subtitle: Text('Mit Konto und Freischaltcode verfügbar.',
                    style: TextStyle(color: s.onTertiaryContainer)),
                trailing: TextButton(
                  onPressed: () {
                    final nav = Navigator.of(context);
                    nav.pop();
                    nav.push(MaterialPageRoute(builder: (_) => const UnlockScreen()));
                  },
                  child: const Text('Freischalten'),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _universe,
                decoration: const InputDecoration(labelText: 'Universe'),
                items: [
                  for (var i = 0; i < app.engine.universeCount; i++)
                    DropdownMenuItem(value: i, child: Text('${i + 1}')),
                ],
                onChanged: (v) => setState(() {
                  _universe = v ?? 0;
                  _suggestAddress();
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _address,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Startadresse'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            const Text('Anzahl'),
            const SizedBox(width: 8),
            IconButton.filledTonal(
                onPressed: _count > 1 ? () => setState(() => _count--) : null, icon: const Icon(Icons.remove)),
            SizedBox(width: 36, child: Text('$_count', textAlign: TextAlign.center)),
            IconButton.filledTonal(onPressed: () => setState(() => _count++), icon: const Icon(Icons.add)),
            const Spacer(),
            Text('${_profile.footprint * _count} Kanäle', style: TextStyle(color: s.onSurfaceVariant)),
          ]),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: s.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: locked ? null : _submit,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(_count > 1 ? '$_count Lampen hinzufügen' : 'Hinzufügen'),
          ),
        ]),
      ),
    );
  }
}

class EditFixtureDialog extends StatefulWidget {
  const EditFixtureDialog({super.key, required this.app, required this.fixture});
  final AppState app;
  final Fixture fixture;

  @override
  State<EditFixtureDialog> createState() => _EditFixtureDialogState();
}

class _EditFixtureDialogState extends State<EditFixtureDialog> {
  late final _name = TextEditingController(text: widget.fixture.name);
  late final _address = TextEditingController(text: '${widget.fixture.address}');
  late int _universe = widget.fixture.universe;
  String? _error;

  void _save() {
    final f = widget.fixture;
    final n = widget.app.profileOf(f)?.footprint ?? 1;
    final addr = int.tryParse(_address.text);
    if (addr == null || addr < 1 || addr + n - 1 > 512) {
      setState(() => _error = 'Startadresse muss zwischen 1 und ${513 - n} liegen.');
      return;
    }
    final clash = widget.app.overlapping(_universe, addr, n, ignoreId: f.id);
    if (clash != null) {
      setState(() => _error = 'Adressen überschneiden sich mit „${clash.name}“.');
      return;
    }
    widget.app.updateFixture(f, name: _name.text.trim(), universe: _universe, address: addr);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Lampe bearbeiten'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _universe,
          decoration: const InputDecoration(labelText: 'Universe'),
          items: [
            for (var i = 0; i < widget.app.engine.universeCount; i++)
              DropdownMenuItem(value: i, child: Text('${i + 1}')),
          ],
          onChanged: (v) => setState(() => _universe = v ?? 0),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _address,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Startadresse'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(onPressed: _save, child: const Text('Speichern')),
      ],
    );
  }
}
