import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import 'app_scope.dart';
import 'fixture_control_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

/// Startseite: alle Geräte als Kacheln. Tippen = steuern,
/// lang drücken = mehrere auswählen.
class FixturesScreen extends StatefulWidget {
  const FixturesScreen({super.key});

  @override
  State<FixturesScreen> createState() => _FixturesScreenState();
}

class _FixturesScreenState extends State<FixturesScreen> {
  final Set<String> _selected = {};

  void _open(List<Fixture> list) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => FixtureControlScreen(fixtures: list)),
      );

  void _toggle(String id) =>
      setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));

  void _add(AppState app) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => AddFixtureSheet(app: app),
      );

  @override
  Widget build(BuildContext context) {
    return AppListener(builder: (context, app) {
      _selected.removeWhere((id) => !app.fixtures.any((f) => f.id == id));
      final selecting = _selected.isNotEmpty;
      final chosen = app.fixtures.where((f) => _selected.contains(f.id)).toList();

      return Scaffold(
        appBar: AppBar(
          title: Text(selecting ? '${_selected.length} ausgewählt' : 'Steuern'),
          leading: selecting
              ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_selected.clear))
              : null,
          actions: selecting
              ? [
                  IconButton(
                    tooltip: 'Alle wählen',
                    icon: const Icon(Icons.select_all),
                    onPressed: () => setState(() => _selected.addAll(app.fixtures.map((f) => f.id))),
                  ),
                ]
              : const [ConnectionChip()],
        ),
        floatingActionButton: selecting
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
        body: app.fixtures.isEmpty
            ? _EmptyState(onAdd: () => _add(app))
            : CustomScrollView(slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
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
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                  sliver: SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220,
                      mainAxisExtent: 150,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                    ),
                    itemCount: app.fixtures.length,
                    itemBuilder: (context, i) {
                      final f = app.fixtures[i];
                      return _FixtureTile(
                        fixture: f,
                        app: app,
                        selected: _selected.contains(f.id),
                        onTap: selecting ? () => _toggle(f.id) : () => _open([f]),
                        onLongPress: () => _toggle(f.id),
                      );
                    },
                  ),
                ),
              ]),
      );
    });
  }
}

class _FixtureTile extends StatelessWidget {
  const _FixtureTile({
    required this.fixture,
    required this.app,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final Fixture fixture;
  final AppState app;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final p = app.profileOf(fixture);
    final level = app.fixtureLevel(fixture);
    final color = app.fixtureColor(fixture);
    final on = level > 0.01;
    final lamp = color ?? Color.lerp(s.surfaceContainerHighest, const Color(0xFFFFC94D), level)!;

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
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? lamp : s.surfaceContainerHighest,
                  boxShadow: on
                      ? [BoxShadow(color: lamp.withValues(alpha: 0.55), blurRadius: 16, spreadRadius: 1)]
                      : null,
                ),
                child: Icon(Icons.lightbulb_outline, size: 18,
                    color: on ? Colors.black.withValues(alpha: 0.55) : s.onSurfaceVariant),
              ),
              const Spacer(),
              if (selected) Icon(Icons.check_circle, color: s.primary),
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
                backgroundColor: s.surfaceContainerHighest,
              ),
            ),
          ]),
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
  const AddFixtureSheet({super.key, required this.app});
  final AppState app;

  @override
  State<AddFixtureSheet> createState() => _AddFixtureSheetState();
}

class _AddFixtureSheetState extends State<AddFixtureSheet> {
  late FixtureProfile _profile = widget.app.profiles[1];
  int _universe = 0;
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
