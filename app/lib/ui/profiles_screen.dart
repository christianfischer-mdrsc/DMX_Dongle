import 'package:flutter/material.dart';

import '../models/models.dart';
import 'app_scope.dart';

const channelTypeLabels = <ChannelType, String>{
  ChannelType.dimmer: 'Dimmer',
  ChannelType.red: 'Rot',
  ChannelType.green: 'Grün',
  ChannelType.blue: 'Blau',
  ChannelType.white: 'Weiß',
  ChannelType.amber: 'Amber',
  ChannelType.uv: 'UV',
  ChannelType.pan: 'Pan',
  ChannelType.panFine: 'Pan fein',
  ChannelType.tilt: 'Tilt',
  ChannelType.tiltFine: 'Tilt fein',
  ChannelType.speed: 'Geschwindigkeit',
  ChannelType.strobe: 'Strobe',
  ChannelType.colorWheel: 'Farbrad',
  ChannelType.gobo: 'Gobo',
  ChannelType.generic: 'Sonstiges',
};

/// Liste der Geräteprofile: eingebaute (zum Kopieren) und eigene.
class ProfilesScreen extends StatelessWidget {
  const ProfilesScreen({super.key});

  void _edit(BuildContext context, FixtureProfile? p, {bool copy = false}) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileEditor(profile: p, copy: copy)));
  }

  @override
  Widget build(BuildContext context) {
    return AppListener(
      engine: false,
      builder: (context, app) {
        final s = Theme.of(context).colorScheme;
        final builtin = app.profiles.where((p) => p.builtIn).toList();
        return Scaffold(
          appBar: AppBar(title: const Text('Geräteprofile')),
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: const Text('Neues Profil'),
            onPressed: () => _edit(context, null),
          ),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 96), children: [
            Text(
              'Ein Profil beschreibt, welcher Kanal einer Lampe was tut. Die Belegung steht in der '
              'Anleitung der Lampe (DMX-Kanaltabelle bzw. „DMX chart“).',
              style: TextStyle(color: s.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Text('Eigene Profile', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (app.customProfiles.isEmpty)
              Text('Noch keine. Lege eins an oder kopiere ein eingebautes.',
                  style: TextStyle(color: s.onSurfaceVariant))
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  for (final p in app.customProfiles)
                    ListTile(
                      leading: const Icon(Icons.lightbulb_outline),
                      title: Text(p.label),
                      subtitle: Text('${p.footprint} Kanäle'
                          '${app.profileInUse(p) ? ' · in Benutzung' : ''}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _edit(context, p),
                    ),
                ]),
              ),
            const SizedBox(height: 20),
            Text('Eingebaut', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (final p in builtin)
                  ListTile(
                    leading: Icon(app.isUnlocked(p) ? Icons.lightbulb_outline : Icons.lock_outline),
                    title: Text(p.label),
                    subtitle: Text('${p.footprint} Kanäle'),
                    trailing: TextButton(
                      onPressed: app.isUnlocked(p) ? () => _edit(context, p, copy: true) : null,
                      child: const Text('Kopieren'),
                    ),
                  ),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

class _Range {
  _Range(int from, int to, String label)
      : from = TextEditingController(text: '$from'),
        to = TextEditingController(text: '$to'),
        label = TextEditingController(text: label);
  final TextEditingController from, to, label;

  ChannelRange? get value {
    final a = int.tryParse(from.text.trim()), b = int.tryParse(to.text.trim());
    if (a == null || b == null) return null;
    final lo = a.clamp(0, 255), hi = b.clamp(0, 255);
    return ChannelRange(lo < hi ? lo : hi, lo < hi ? hi : lo, label.text.trim());
  }

  void dispose() {
    from.dispose();
    to.dispose();
    label.dispose();
  }
}

class _Ch {
  _Ch(this.name, this.type, this.def, {this.part = '', List<ChannelRange> ranges = const []})
      : key = UniqueKey(),
        ranges = [for (final r in ranges) (r.from, r.to, r.label)];
  final Key key;
  final TextEditingController name;
  ChannelType type;
  int def;

  /// Lichtquelle, z. B. „Strobe“ oder „Ambient“ ('' = keine eigene)
  String part;
  List<(int, int, String)> ranges;
}

class ProfileEditor extends StatefulWidget {
  const ProfileEditor({super.key, this.profile, this.copy = false});
  final FixtureProfile? profile;

  /// true = eingebautes Profil als Vorlage für ein neues
  final bool copy;

  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  late final _manufacturer = TextEditingController(text: widget.profile?.manufacturer ?? '');
  late final _name = TextEditingController(
      text: widget.profile == null ? '' : '${widget.profile!.name}${widget.copy ? ' (Kopie)' : ''}');
  late final List<_Ch> _channels = [
    for (final c in widget.profile?.channels ?? const <ChannelDef>[])
      _Ch(TextEditingController(text: c.name), c.type, c.defaultValue, part: c.part, ranges: c.ranges),
  ];
  final List<_Ch> _removed = [];
  String? _error;

  bool get _isEdit => widget.profile != null && !widget.copy;

  /// Alle bisher vergebenen Lichtquellen, in Reihenfolge.
  List<String> get _parts => [
        for (final c in _channels)
          if (c.part.isNotEmpty) c.part,
      ].toSet().toList();

  void _addChannel() => setState(() => _channels.add(_Ch(
        TextEditingController(text: 'Kanal ${_channels.length + 1}'),
        ChannelType.generic,
        0,
        // Neue Kanäle gehören erst mal zur selben Lichtquelle wie der letzte
        part: _channels.isEmpty ? '' : _channels.last.part,
      )));

  /// Gleiche Funktion zweimal in derselben Lichtquelle? (z. B. zwei Dimmer ohne Lichtquelle)
  String? _clash(int i) {
    final c = _channels[i];
    if (c.type == ChannelType.generic) return null;
    for (var j = 0; j < i; j++) {
      final o = _channels[j];
      if (o.type == c.type && o.part == c.part) {
        return 'Wie Kanal ${j + 1}: Hat die Lampe zwei getrennte Lichter, '
            'gib beiden Kanälen eine eigene Lichtquelle.';
      }
    }
    return null;
  }

  Future<String?> _askPartName({String initial = ''}) async {
    final ctl = TextEditingController(text: initial);
    final r = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lichtquelle'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Ein eigenständig steuerbares Licht in der Lampe, z. B. „Strobe“, „Ambient“, „Laser“ oder „Ring außen“.'),
          const SizedBox(height: 12),
          TextField(
            controller: ctl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
            onSubmitted: (v) => Navigator.pop(context, v.trim()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(context, ctl.text.trim()), child: const Text('OK')),
        ],
      ),
    );
    ctl.dispose();
    return (r == null || r.isEmpty) ? null : r;
  }

  Future<void> _editRanges(_Ch c) async {
    final rows = [for (final r in c.ranges) _Range(r.$1, r.$2, r.$3)];
    final result = await showDialog<List<ChannelRange>>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setD) {
        return AlertDialog(
          title: Text('Wertebereiche: ${c.name.text}'),
          scrollable: true,
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Aus der DMX-Tabelle der Anleitung, z. B. 0–8 „Aus“, 9–255 „Strobe langsam → schnell“. '
                'Die App zeigt die Bereiche dann als Tasten am Schieber.'),
            const SizedBox(height: 12),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  SizedBox(
                    width: 52,
                    child: TextField(
                      controller: r.from,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(isDense: true, labelText: 'von'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 52,
                    child: TextField(
                      controller: r.to,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(isDense: true, labelText: 'bis'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: r.label,
                      decoration: const InputDecoration(isDense: true, labelText: 'Bedeutung'),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Entfernen',
                    icon: const Icon(Icons.close),
                    onPressed: () => setD(() => rows.remove(r)),
                  ),
                ]),
              ),
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Bereich'),
              onPressed: () => setD(() {
                // schließt an den letzten Bereich an
                final last = rows.isEmpty ? null : rows.last.value;
                final from = last == null ? 0 : (last.to + 1).clamp(0, 255);
                rows.add(_Range(from, 255, ''));
              }),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
            FilledButton(
              onPressed: () => Navigator.pop(context, [
                for (final r in rows)
                  if (r.value case final v?) v,
              ]..sort((a, b) => a.from.compareTo(b.from))),
              child: const Text('Übernehmen'),
            ),
          ],
        );
      }),
    );
    for (final r in rows) {
      r.dispose();
    }
    if (result != null) setState(() => c.ranges = [for (final r in result) (r.from, r.to, r.label)]);
  }

  void _save() {
    final app = AppScope.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) return setState(() => _error = 'Bitte einen Namen eingeben.');
    if (_channels.isEmpty) return setState(() => _error = 'Mindestens ein Kanal ist nötig.');
    final p = FixtureProfile(
      id: _isEdit ? widget.profile!.id : 'custom-${newId()}',
      manufacturer: _manufacturer.text.trim(),
      name: name,
      channels: [
        for (final c in _channels)
          ChannelDef(
            c.name.text.trim().isEmpty ? channelTypeLabels[c.type]! : c.name.text.trim(),
            c.type,
            c.def,
            c.part,
            [for (final r in c.ranges) ChannelRange(r.$1, r.$2, r.$3)],
          ),
      ],
    );
    if (_isEdit && app.profileInUse(widget.profile!) && p.footprint != widget.profile!.footprint) {
      // Kanalzahl geändert: Adressen könnten sich überschneiden
      for (final f in app.fixtures.where((f) => f.profileId == p.id)) {
        if (app.overlapping(f.universe, f.address, p.footprint, ignoreId: f.id) != null ||
            f.address + p.footprint - 1 > 512) {
          return setState(() => _error =
              'Mit ${p.footprint} Kanälen überschneidet sich „${f.name}“ mit einer anderen Lampe. '
              'Erst die Adressen anpassen.');
        }
      }
    }
    app.saveProfile(p);
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _manufacturer.dispose();
    _name.dispose();
    for (final c in [..._channels, ..._removed]) {
      c.name.dispose();
    }
    super.dispose();
  }

  Widget _partPicker(_Ch c) {
    const none = '\u0000keine', add = '\u0000neu';
    final parts = _parts;
    return DropdownButtonFormField<String>(
      key: ValueKey('part-${c.key}-${c.part}-${parts.length}'),
      initialValue: c.part.isEmpty ? none : c.part,
      isDense: true,
      isExpanded: true,
      decoration: const InputDecoration(isDense: true, labelText: 'Lichtquelle'),
      items: [
        const DropdownMenuItem(value: none, child: Text('– (ganze Lampe)')),
        for (final p in parts) DropdownMenuItem(value: p, child: Text(p, overflow: TextOverflow.ellipsis)),
        const DropdownMenuItem(value: add, child: Text('Neue Lichtquelle …')),
      ],
      onChanged: (v) async {
        if (v == add) {
          final n = await _askPartName();
          setState(() => c.part = n ?? c.part);
        } else {
          setState(() => c.part = v == none || v == null ? '' : v);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = Theme.of(context).colorScheme;
    final inUse = _isEdit && app.profileInUse(widget.profile!);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Profil bearbeiten' : 'Neues Profil'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: inUse ? 'In Benutzung – erst die Lampen entfernen' : 'Löschen',
              icon: const Icon(Icons.delete_outline),
              onPressed: inUse
                  ? null
                  : () {
                      app.deleteProfile(widget.profile!);
                      Navigator.pop(context);
                    },
            ),
          TextButton(onPressed: _save, child: const Text('Speichern')),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Kanal'),
        onPressed: _addChannel,
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: _manufacturer, decoration: const InputDecoration(labelText: 'Hersteller (optional)')),
            const SizedBox(height: 12),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name, z. B. „PAR 64 7-Kanal“')),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: s.error)),
            ],
            const SizedBox(height: 8),
            Text(
              'Hat die Lampe mehrere getrennte Lichter (z. B. Strobe und Ambient), gib jedem Kanal seine '
              'Lichtquelle. Jede bekommt dann eigene Regler für Dimmer, Farbe und Strobe.',
              style: TextStyle(color: s.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Text('Kanäle (${_channels.length})', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              Text('Ziehen zum Sortieren', style: TextStyle(color: s.onSurfaceVariant, fontSize: 12)),
            ]),
          ]),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: _channels.length,
            onReorder: (a, b) => setState(() {
              if (b > a) b--;
              _channels.insert(b, _channels.removeAt(a));
            }),
            itemBuilder: (context, i) {
              final c = _channels[i];
              final clash = _clash(i);
              return Card(
                key: c.key,
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: CircleAvatar(radius: 14, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        TextField(
                          controller: c.name,
                          decoration: const InputDecoration(isDense: true, labelText: 'Bezeichnung'),
                        ),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                            child: DropdownButtonFormField<ChannelType>(
                              initialValue: c.type,
                              isDense: true,
                              isExpanded: true,
                              decoration: const InputDecoration(isDense: true, labelText: 'Funktion'),
                              items: [
                                for (final t in ChannelType.values)
                                  DropdownMenuItem(value: t, child: Text(channelTypeLabels[t]!)),
                              ],
                              onChanged: (t) => setState(() {
                                final old = c.type;
                                c.type = t ?? ChannelType.generic;
                                // Bezeichnung mitziehen, solange sie noch die alte Vorgabe ist
                                if (c.name.text == channelTypeLabels[old] || c.name.text.startsWith('Kanal ')) {
                                  c.name.text = channelTypeLabels[c.type]!;
                                }
                                if ((c.type == ChannelType.pan || c.type == ChannelType.tilt) && c.def == 0) {
                                  c.def = 128;
                                }
                              }),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 72,
                            child: TextFormField(
                              key: ValueKey(c.type),
                              initialValue: '${c.def}',
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(isDense: true, labelText: 'Start'),
                              onChanged: (v) => c.def = (int.tryParse(v) ?? 0).clamp(0, 255),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(child: _partPicker(c)),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            icon: const Icon(Icons.tune, size: 18),
                            label: Text(c.ranges.isEmpty ? 'Bereiche' : 'Bereiche (${c.ranges.length})'),
                            onPressed: () => _editRanges(c),
                          ),
                        ]),
                        if (clash != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(clash, style: TextStyle(color: s.error, fontSize: 12)),
                          ),
                      ]),
                    ),
                    IconButton(
                      tooltip: 'Kanal entfernen',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _removed.add(_channels.removeAt(i))),
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
