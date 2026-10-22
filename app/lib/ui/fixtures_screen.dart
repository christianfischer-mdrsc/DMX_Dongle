import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import 'app_scope.dart';
import 'fixture_control_screen.dart';

/// Patch-Liste. Tippen = steuern, langes Drücken = Mehrfachauswahl.
class FixturesScreen extends StatefulWidget {
  const FixturesScreen({super.key});

  @override
  State<FixturesScreen> createState() => _FixturesScreenState();
}

class _FixturesScreenState extends State<FixturesScreen> {
  final Set<String> _selected = {};

  void _open(AppState app, List<Fixture> list) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FixtureControlScreen(fixtures: list),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AppListener(
      engine: false,
      builder: (context, app) {
        _selected.removeWhere((id) => !app.fixtures.any((f) => f.id == id));
        final selecting = _selected.isNotEmpty;
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Text(selecting ? '${_selected.length} ausgewählt' : 'Geräte'),
            leading: selecting
                ? IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(_selected.clear))
                : null,
            actions: [
              if (selecting)
                IconButton(
                  tooltip: 'Alle wählen',
                  icon: const Icon(Icons.select_all),
                  onPressed: () => setState(
                      () => _selected.addAll(app.fixtures.map((f) => f.id))),
                ),
            ],
          ),
          floatingActionButton: selecting
              ? FloatingActionButton.extended(
                  icon: const Icon(Icons.tune),
                  label: const Text('Steuern'),
                  onPressed: () => _open(app,
                      app.fixtures.where((f) => _selected.contains(f.id)).toList()),
                )
              : FloatingActionButton(
                  child: const Icon(Icons.add),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => AddFixtureDialog(app: app),
                  ),
                ),
          body: app.fixtures.isEmpty
              ? const _EmptyHint()
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: app.fixtures.length,
                  itemBuilder: (context, i) {
                    final f = app.fixtures[i];
                    final p = app.profileOf(f);
                    final sel = _selected.contains(f.id);
                    final end = f.address + (p?.footprint ?? 1) - 1;
                    return ListTile(
                      selected: sel,
                      leading: CircleAvatar(child: Text('U${f.universe + 1}')),
                      title: Text(f.name),
                      subtitle: Text('${p?.label ?? 'Unbekanntes Profil'} · '
                          'Kanal ${f.address}–$end'),
                      trailing: selecting
                          ? Checkbox(
                              value: sel,
                              onChanged: (_) => setState(() =>
                                  sel ? _selected.remove(f.id) : _selected.add(f.id)))
                          : PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'edit') {
                                  showDialog(
                                      context: context,
                                      builder: (_) => EditFixtureDialog(app: app, fixture: f));
                                } else if (v == 'delete') {
                                  app.removeFixture(f);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'edit', child: Text('Bearbeiten')),
                                PopupMenuItem(value: 'delete', child: Text('Entfernen')),
                              ],
                            ),
                      onTap: selecting
                          ? () => setState(() =>
                              sel ? _selected.remove(f.id) : _selected.add(f.id))
                          : () => _open(app, [f]),
                      onLongPress: () => setState(() => _selected.add(f.id)),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Noch keine Geräte gepatcht.\nMit + ein Gerät hinzufügen.',
            textAlign: TextAlign.center,
          ),
        ),
      );
}

class AddFixtureDialog extends StatefulWidget {
  const AddFixtureDialog({super.key, required this.app});
  final AppState app;

  @override
  State<AddFixtureDialog> createState() => _AddFixtureDialogState();
}

class _AddFixtureDialogState extends State<AddFixtureDialog> {
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
      setState(() => _error = 'Adresse 1–${513 - total} erforderlich');
      return;
    }
    final clash = widget.app.overlapping(_universe, addr, total);
    if (clash != null) {
      setState(() => _error = 'Überschneidung mit „${clash.name}“');
      return;
    }
    widget.app.addFixtures(_profile, _name.text.trim().isEmpty ? _profile.name : _name.text.trim(),
        _universe, addr, _count);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return AlertDialog(
      title: const Text('Gerät hinzufügen'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<FixtureProfile>(
              initialValue: _profile,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Profil'),
              items: [
                for (final p in app.profiles)
                  DropdownMenuItem(value: p, child: Text(p.label, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (p) => setState(() {
                _profile = p!;
                _suggestAddress();
              }),
            ),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
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
              IconButton(
                  onPressed: _count > 1 ? () => setState(() => _count--) : null,
                  icon: const Icon(Icons.remove)),
              Text('$_count'),
              IconButton(
                  onPressed: () => setState(() => _count++),
                  icon: const Icon(Icons.add)),
              const Spacer(),
              Text('${_profile.footprint * _count} Kan.'),
            ]),
            if (_error != null)
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(onPressed: _submit, child: const Text('Hinzufügen')),
      ],
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
      setState(() => _error = 'Ungültige Adresse');
      return;
    }
    final clash = widget.app.overlapping(_universe, addr, n, ignoreId: f.id);
    if (clash != null) {
      setState(() => _error = 'Überschneidung mit „${clash.name}“');
      return;
    }
    widget.app.updateFixture(f, name: _name.text.trim(), universe: _universe, address: addr);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Gerät bearbeiten'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
        DropdownButtonFormField<int>(
          initialValue: _universe,
          decoration: const InputDecoration(labelText: 'Universe'),
          items: [
            for (var i = 0; i < widget.app.engine.universeCount; i++)
              DropdownMenuItem(value: i, child: Text('${i + 1}')),
          ],
          onChanged: (v) => setState(() => _universe = v ?? 0),
        ),
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
