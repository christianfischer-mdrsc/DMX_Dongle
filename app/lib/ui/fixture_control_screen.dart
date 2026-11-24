import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import 'app_scope.dart';
import 'effect_editor.dart';
import 'fixtures_screen.dart';

/// Steuert ein oder mehrere Geräte gleichzeitig. Werte werden vom ersten
/// Gerät angezeigt und auf alle gewählten übertragen.
class FixtureControlScreen extends StatelessWidget {
  const FixtureControlScreen({super.key, required this.fixtures});
  final List<Fixture> fixtures;

  @override
  Widget build(BuildContext context) {
    return AppListener(builder: (context, app) {
      final first = fixtures.first;
      final profiles = fixtures.map(app.profileOf).whereType<FixtureProfile>().toList();
      final ref = app.profileOf(first);
      final sameProfile = profiles.every((p) => p.id == ref?.id);
      bool any(bool Function(FixtureProfile) t) => profiles.any(t);
      // Lichtquellen aller gewählten Lampen (z. B. „Strobe“ und „Ambient“)
      final parts = <String>[
        for (final p in profiles)
          for (final x in p.parts) x,
      ].toSet().toList();
      if (parts.isEmpty) parts.add('');
      final multi = parts.length > 1 || parts.first.isNotEmpty;

      return Scaffold(
        appBar: AppBar(
          title: Text(fixtures.length == 1 ? first.name : '${fixtures.length} Lampen'),
          actions: [
            IconButton(
              tooltip: 'Finden (blinken lassen)',
              icon: const Icon(Icons.flare),
              onPressed: () => app.identify(fixtures),
            ),
            IconButton(
              tooltip: 'Effekt starten',
              icon: const Icon(Icons.auto_awesome_motion),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => EffectEditor(fixtureIds: fixtures.map((f) => f.id).toList()))),
            ),
            IconButton(
              tooltip: 'Einschalten',
              icon: const Icon(Icons.light_mode_outlined),
              onPressed: () => app.allOn(fixtures),
            ),
            IconButton(
              tooltip: 'Ausschalten',
              icon: const Icon(Icons.power_settings_new),
              onPressed: () => app.allOff(fixtures),
            ),
            if (fixtures.length == 1)
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') {
                    showDialog(context: context, builder: (_) => EditFixtureDialog(app: app, fixture: first));
                  } else if (v == 'delete') {
                    app.removeFixture(first);
                    Navigator.pop(context);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Name & Adresse ändern')),
                  PopupMenuItem(value: 'delete', child: Text('Lampe entfernen')),
                ],
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            for (final part in parts) ..._partSections(app, fixtures, profiles, part, multi),
            if (any((p) => p.hasPanTilt))
              _Section(
                title: 'Position',
                child: _PanTiltPad(
                  pan: app.fixtureValue(first, ChannelType.pan) ?? 128,
                  tilt: app.fixtureValue(first, ChannelType.tilt) ?? 128,
                  onChanged: (pan, tilt) => app.setFixtureValues(fixtures, {
                    ChannelType.pan: pan,
                    ChannelType.tilt: tilt,
                  }),
                ),
              ),
            if (sameProfile && ref != null)
              _Section(
                title: 'Alle Kanäle',
                collapsible: true,
                child: Column(children: [
                  for (var i = 0; i < ref.channels.length; i++)
                    _ChannelRow(
                      number: i + 1,
                      def: ref.channels[i],
                      value: app.engine.getChannel(first.universe, first.address - 1 + i),
                      onChanged: (v) => app.setFixtureChannel(fixtures, i, v),
                    ),
                ]),
              ),
          ],
        ),
      );
    });
  }
}

/// Bedienelemente einer Lichtquelle: Dimmer, Farbe, Strobe, Geschwindigkeit.
/// Hat die Lampe mehrere Lichtquellen, bekommt jede eine eigene Karte.
List<Widget> _partSections(
    AppState app, List<Fixture> fixtures, List<FixtureProfile> profiles, String part, bool multi) {
  final first = fixtures.first;
  bool any(ChannelType t) => profiles.any((p) => p.has(t, part: part));
  ChannelDef? defOf(ChannelType t) {
    for (final p in profiles) {
      final o = p.offsetOf(t, part: part);
      if (o != null) return p.channels[o];
    }
    return null;
  }

  // Wert vom ersten Gerät, das diese Funktion in der Lichtquelle hat
  int valueOf(ChannelType t) {
    for (final f in fixtures) {
      final v = app.fixtureValue(f, t, part: part);
      if (v != null) return v;
    }
    return 0;
  }

  _LabeledSlider slider(String label, ChannelType t) => _LabeledSlider(
        label: label,
        def: defOf(t),
        value: valueOf(t),
        onChanged: (v) => app.setFixtureValues(fixtures, {t: v}, part: part),
      );

  final hasColor = profiles.any((p) => p.partHasColor(part));
  final sliders = <_LabeledSlider>[
    if (any(ChannelType.dimmer)) slider('Dimmer', ChannelType.dimmer),
    if (any(ChannelType.strobe)) slider('Strobe', ChannelType.strobe),
    if (any(ChannelType.speed)) slider('Geschwindigkeit', ChannelType.speed),
  ];
  if (sliders.isEmpty && !hasColor) return const [];
  final color = hasColor ? _ColorControls(app: app, fixtures: fixtures, part: part, ref: first) : null;

  if (multi) {
    return [
      _Section(
        title: part.isEmpty ? 'Licht' : part,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (sliders.isNotEmpty && sliders.first.label == 'Dimmer') sliders.first,
          if (color != null) color,
          for (final w in sliders)
            if (w.label != 'Dimmer') w,
        ]),
      ),
    ];
  }
  // Eine Lichtquelle: wie gewohnt je Funktion eine Karte
  return [
    for (final w in sliders)
      if (w.label == 'Dimmer') _Section(title: 'Dimmer', child: w.withoutLabel()),
    if (color != null) _Section(title: 'Farbe', child: color),
    for (final w in sliders)
      if (w.label != 'Dimmer') _Section(title: w.label!, child: w.withoutLabel()),
  ];
}

/// Schieber mit optionaler Überschrift und den Wertebereichen aus dem Profil.
class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({this.label, this.def, required this.value, required this.onChanged});
  final String? label;
  final ChannelDef? def;
  final int value;
  final ValueChanged<int> onChanged;

  _LabeledSlider withoutLabel() => _LabeledSlider(def: def, value: value, onChanged: onChanged);

  @override
  Widget build(BuildContext context) {
    final ranges = def?.ranges ?? const <ChannelRange>[];
    final s = Theme.of(context).colorScheme;
    final current = def?.rangeLabel(value);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (label != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(label!, style: Theme.of(context).textTheme.labelLarge),
        ),
      _ValueSlider(value: value, onChanged: onChanged),
      if (current != null && ranges.length < 2)
        Text(current, style: TextStyle(color: s.onSurfaceVariant, fontSize: 12)),
      if (ranges.length >= 2)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Wrap(spacing: 6, runSpacing: 4, children: [
            for (final r in ranges)
              ChoiceChip(
                label: Text(r.label.isEmpty ? '${r.from}–${r.to}' : r.label),
                selected: r.contains(value),
                visualDensity: VisualDensity.compact,
                // Tippen springt an den Anfang des Bereichs
                onSelected: (_) {
                  if (!r.contains(value)) onChanged(r.from);
                },
              ),
          ]),
        ),
    ]);
  }
}

/// Zeile in „Alle Kanäle“: Nummer, Name (mit Lichtquelle), Schieber, Bereich.
class _ChannelRow extends StatelessWidget {
  const _ChannelRow({required this.number, required this.def, required this.value, required this.onChanged});
  final int number;
  final ChannelDef def;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final range = def.rangeLabel(value);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        SizedBox(
          width: 110,
          child: Text(
            '$number ${def.part.isEmpty ? def.name : '${def.part} · ${def.name}'}',
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
        Expanded(child: _ValueSlider(value: value, onChanged: onChanged)),
      ]),
      if (range != null)
        Padding(
          padding: const EdgeInsets.only(left: 110, bottom: 4),
          child: Text(range, style: TextStyle(color: s.onSurfaceVariant, fontSize: 12)),
        ),
    ]);
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.collapsible = false});
  final String title;
  final Widget child;
  final bool collapsible;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: collapsible
            ? ExpansionTile(
                title: Text(title, style: style),
                shape: const Border(),
                collapsedShape: const Border(),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [child],
              )
            : Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: style),
                  const SizedBox(height: 6),
                  child,
                ]),
              ),
      ),
    );
  }
}

class _ValueSlider extends StatelessWidget {
  const _ValueSlider({required this.value, required this.onChanged, this.color});
  final int value;
  final ValueChanged<int> onChanged;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: Slider(
            value: value.toDouble(),
            max: 255,
            activeColor: color,
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        SizedBox(width: 36, child: Text('$value', textAlign: TextAlign.right)),
      ]);
}

class _ColorControls extends StatelessWidget {
  const _ColorControls({required this.app, required this.fixtures, required this.part, required this.ref});
  final AppState app;
  final List<Fixture> fixtures;
  final String part;
  final Fixture ref;

  static const _presets = <Color>[
    Color(0xFFFF0000), Color(0xFFFF8000), Color(0xFFFFFF00), Color(0xFF00FF00),
    Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFF8000FF), Color(0xFFFF00FF),
    Color(0xFFFFFFFF), Color(0xFFFFC080),
  ];

  static int _c(double ch) => (ch * 255).round();

  @override
  Widget build(BuildContext context) {
    final f = fixtures.firstWhere((x) => app.profileOf(x)?.partHasColor(part) ?? false, orElse: () => ref);
    int v(ChannelType t) => app.fixtureValue(f, t, part: part) ?? 0;
    final w = v(ChannelType.white);
    final r = (v(ChannelType.red) + w).clamp(0, 255).toInt();
    final g = (v(ChannelType.green) + w).clamp(0, 255).toInt();
    final b = (v(ChannelType.blue) + w).clamp(0, 255).toInt();
    void set(int r, int g, int b) => app.setFixtureColor(fixtures, r, g, b, part: part);

    return Column(children: [
      const SizedBox(height: 6),
      Container(
        height: 36,
        decoration: BoxDecoration(
          color: Color.fromARGB(255, r, g, b),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [
        for (final c in _presets)
          InkWell(
            customBorder: const CircleBorder(),
            onTap: () => set(_c(c.r), _c(c.g), _c(c.b)),
            child: CircleAvatar(radius: 18, backgroundColor: c),
          ),
      ]),
      const SizedBox(height: 8),
      _ValueSlider(value: r, color: Colors.red, onChanged: (x) => set(x, g, b)),
      _ValueSlider(value: g, color: Colors.green, onChanged: (x) => set(r, x, b)),
      _ValueSlider(value: b, color: Colors.blue, onChanged: (x) => set(r, g, x)),
    ]);
  }
}

/// XY-Feld für Pan/Tilt (8 Bit).
class _PanTiltPad extends StatelessWidget {
  const _PanTiltPad({required this.pan, required this.tilt, required this.onChanged});
  final int pan;
  final int tilt;
  final void Function(int pan, int tilt) onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 1.6,
      child: LayoutBuilder(builder: (context, c) {
        void handle(Offset p) {
          final x = (p.dx / c.maxWidth).clamp(0.0, 1.0);
          final y = (p.dy / c.maxHeight).clamp(0.0, 1.0);
          onChanged((x * 255).round(), (y * 255).round());
        }

        return GestureDetector(
          onPanDown: (d) => handle(d.localPosition),
          onPanUpdate: (d) => handle(d.localPosition),
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(children: [
              Center(child: Container(width: 1, color: scheme.outlineVariant)),
              Center(child: Container(height: 1, color: scheme.outlineVariant)),
              Positioned(
                left: pan / 255 * c.maxWidth - 12,
                top: tilt / 255 * c.maxHeight - 12,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.primary,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                bottom: 6,
                child: Text('Pan $pan · Tilt $tilt',
                    style: Theme.of(context).textTheme.labelSmall),
              ),
            ]),
          ),
        );
      }),
    );
  }
}
