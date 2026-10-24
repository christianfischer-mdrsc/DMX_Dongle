import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import 'app_scope.dart';

/// Effekt anlegen oder bearbeiten. Läuft während der Bearbeitung als
/// Vorschau auf den gewählten Lampen.
class EffectEditor extends StatefulWidget {
  const EffectEditor({super.key, this.effect, this.fixtureIds = const []});

  /// null = neuer Effekt
  final Effect? effect;

  /// Vorauswahl bei neuem Effekt
  final List<String> fixtureIds;

  @override
  State<EffectEditor> createState() => _EffectEditorState();
}

const effectIcons = <EffectType, IconData>{
  EffectType.rainbow: Icons.looks_outlined,
  EffectType.pulse: Icons.favorite_border,
  EffectType.chase: Icons.double_arrow,
  EffectType.strobe: Icons.flash_on_outlined,
  EffectType.flicker: Icons.local_fire_department_outlined,
  EffectType.circle: Icons.all_inclusive,
};

const _colors = <int?>[null, 0xFFFFFF, 0xFF0000, 0xFF8000, 0xFFFF00, 0x00FF00, 0x00FFFF, 0x0000FF, 0xFF00FF, 0xFF7A1E];
const _beatChoices = <double>[0.25, 0.5, 1, 2, 4, 8, 16, 32];

String beatsLabel(double b) => switch (b) {
      0.25 => '¼ Schlag',
      0.5 => '½ Schlag',
      1.0 => '1 Schlag',
      _ => '${b.toInt()} Schläge',
    };

class _EffectEditorState extends State<EffectEditor> {
  late final bool _isNew = widget.effect == null;
  late Effect _e;
  late final TextEditingController _name;
  late final bool _wasRunning;
  late final AppState _app;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    final app = _app = AppScope.of(context);
    final src = widget.effect;
    _e = src == null
        ? Effect.preset(EffectType.rainbow, [...widget.fixtureIds])
        : Effect.fromJson(src.toJson()); // Kopie: Abbrechen lässt das Original unberührt
    _name = TextEditingController(text: _e.name);
    _wasRunning = app.engine.isEffectRunning(_e.id);
    WidgetsBinding.instance.addPostFrameCallback((_) => _preview());
  }

  void _preview() {
    if (!mounted) return;
    _app.previewEffect(_e);
  }

  void _change(void Function() f) {
    setState(f);
    _preview();
  }

  void _setType(EffectType t) => _change(() {
        final keepName = _name.text.trim().isNotEmpty && _name.text != _e.type.label;
        final d = t.defaults;
        _e
          ..type = t
          ..beats = d.beats
          ..size = d.size
          ..spread = d.spread
          ..color = d.color;
        if (!keepName) _name.text = t.label;
      });

  @override
  void dispose() {
    // Abgebrochen: Vorschau beenden bzw. Original wiederherstellen
    if (!_saved) {
      if (!_wasRunning) {
        _app.engine.stopEffect(_e.id);
      } else if (widget.effect != null) {
        _app.saveEffect(widget.effect!);
      }
    }
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final app = _app;
    _e.name = _name.text.trim().isEmpty ? _e.type.label : _name.text.trim();
    final target = widget.effect;
    if (target != null) {
      // Werte ins Original übernehmen (Liste hält das Objekt)
      final i = app.effects.indexOf(target);
      if (i >= 0) app.effects[i] = _e;
    }
    app.saveEffect(_e);
    _saved = true;
    // Läuft weiter, wenn er schon lief; neuer Effekt startet direkt
    if (!_wasRunning) {
      app.engine.stopEffect(_e.id);
      if (_isNew) app.toggleEffect(_e);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = Theme.of(context).colorScheme;
    final hasPanTilt = app.fixturesByIds(_e.fixtureIds).any((f) => app.profileOf(f)?.hasPanTilt ?? false);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Neuer Effekt' : 'Effekt bearbeiten'),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: 'Löschen',
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                app.deleteEffect(widget.effect!);
                _saved = true;
                Navigator.pop(context);
              },
            ),
          TextButton(onPressed: _e.fixtureIds.isEmpty ? null : _save, child: const Text('Speichern')),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        Text('Vorschau läuft auf den gewählten Lampen.', style: TextStyle(color: s.onSurfaceVariant)),
        const SizedBox(height: 12),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
        const SizedBox(height: 16),
        Text('Art', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in EffectType.values)
            ChoiceChip(
              avatar: Icon(effectIcons[t], size: 18),
              label: Text(t.label),
              selected: _e.type == t,
              onSelected: (_) => _setType(t),
            ),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(_e.type.hint, style: TextStyle(color: s.onSurfaceVariant, fontSize: 13)),
        ),
        if (_e.type == EffectType.circle && !hasPanTilt && _e.fixtureIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Keine der gewählten Lampen hat Pan/Tilt – der Kreis wirkt nur auf Moving Heads.',
                style: TextStyle(color: s.error, fontSize: 13)),
          ),
        const SizedBox(height: 20),
        _FixturePicker(
          selected: _e.fixtureIds,
          onChanged: (ids) => _change(() => _e.fixtureIds = ids),
        ),
        const SizedBox(height: 20),
        Text('Tempo', style: Theme.of(context).textTheme.titleSmall),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Im Takt'),
          subtitle: Text(_e.syncTempo
              ? 'Folgt dem Tempo (aktuell ${app.engine.bpm.round()} BPM, einstellbar auf der Live-Seite)'
              : 'Feste Geschwindigkeit'),
          value: _e.syncTempo,
          onChanged: (v) => _change(() => _e.syncTempo = v),
        ),
        if (_e.syncTempo)
          DropdownButtonFormField<double>(
            initialValue: _beatChoices.contains(_e.beats) ? _e.beats : 4,
            decoration: const InputDecoration(labelText: 'Ein Durchlauf dauert'),
            items: [for (final b in _beatChoices) DropdownMenuItem(value: b, child: Text(beatsLabel(b)))],
            onChanged: (v) => _change(() => _e.beats = v ?? 4),
          )
        else
          _LabeledSlider(
            label: 'Durchläufe pro Minute',
            value: _e.cyclesPerMinute,
            min: 2,
            max: 300,
            format: (v) => v.round().toString(),
            onChanged: (v) => _change(() => _e.cyclesPerMinute = v),
          ),
        const SizedBox(height: 12),
        _LabeledSlider(
          label: switch (_e.type) {
            EffectType.pulse => 'Hub',
            EffectType.chase => 'Schweif',
            EffectType.strobe => 'Blitzlänge (kurz ↔ lang)',
            EffectType.flicker => 'Stärke',
            EffectType.circle => 'Größe des Kreises',
            EffectType.rainbow => 'Stärke',
          },
          value: _e.type == EffectType.strobe ? 1 - _e.size : _e.size,
          format: (v) => '${(v * 100).round()} %',
          onChanged: (v) => _change(() => _e.size = _e.type == EffectType.strobe ? 1 - v : v),
        ),
        if (_e.type != EffectType.chase)
          _LabeledSlider(
            label: 'Versatz zwischen den Lampen',
            value: _e.spread,
            format: (v) => v == 0 ? 'alle gleich' : '${(v * 100).round()} %',
            onChanged: (v) => _change(() => _e.spread = v),
          ),
        if (_e.type != EffectType.rainbow && _e.type != EffectType.circle) ...[
          const SizedBox(height: 12),
          Text('Farbe', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final c in _colors)
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _change(() => _e.color = c),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c == null ? s.surfaceContainerHighest : Color(0xFF000000 | c),
                    border: Border.all(
                      color: _e.color == c ? s.primary : s.outlineVariant,
                      width: _e.color == c ? 3 : 1,
                    ),
                  ),
                  child: c == null
                      ? Icon(Icons.format_color_reset_outlined, size: 18, color: s.onSurfaceVariant)
                      : null,
                ),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Ohne Farbe bleibt die aktuelle Farbe der Lampen.',
                style: TextStyle(color: s.onSurfaceVariant, fontSize: 13)),
          ),
        ],
      ]),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.format,
    this.min = 0,
    this.max = 1,
  });
  final String label;
  final double value, min, max;
  final ValueChanged<double> onChanged;
  final String Function(double) format;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label)),
          Text(format(value), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
        Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
      ]);
}

/// Lampen wählen: Gruppen als Schnellwahl, darunter jede Lampe einzeln.
class _FixturePicker extends StatelessWidget {
  const _FixturePicker({required this.selected, required this.onChanged});
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = Theme.of(context).colorScheme;
    final all = app.fixtures.map((f) => f.id).toList();
    bool sameSet(List<String> ids) => ids.length == selected.length && ids.every(selected.contains);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Lampen', style: Theme.of(context).textTheme.titleSmall),
        const Spacer(),
        Text('${selected.length} gewählt', style: TextStyle(color: s.onSurfaceVariant)),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilterChip(
          label: const Text('Alle'),
          selected: all.isNotEmpty && sameSet(all),
          onSelected: (_) => onChanged([...all]),
        ),
        for (final g in app.groups)
          FilterChip(
            avatar: const Icon(Icons.workspaces_outline, size: 18),
            label: Text(g.name),
            selected: g.fixtureIds.isNotEmpty && sameSet(g.fixtureIds),
            onSelected: (_) => onChanged([...g.fixtureIds]),
          ),
      ]),
      const SizedBox(height: 4),
      if (app.fixtures.isEmpty)
        Text('Noch keine Lampen angelegt.', style: TextStyle(color: s.onSurfaceVariant))
      else
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (final f in app.fixtures)
              CheckboxListTile(
                dense: true,
                value: selected.contains(f.id),
                title: Text(f.name),
                subtitle: Text(app.profileOf(f)?.name ?? ''),
                onChanged: (v) => onChanged(v == true
                    ? [...selected, f.id]
                    : selected.where((x) => x != f.id).toList()),
              ),
          ]),
        ),
    ]);
  }
}
