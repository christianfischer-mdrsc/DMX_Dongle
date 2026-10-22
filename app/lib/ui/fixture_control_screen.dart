import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import 'app_scope.dart';

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

      return Scaffold(
        appBar: AppBar(
          title: Text(fixtures.length == 1 ? first.name : '${fixtures.length} Geräte'),
          actions: [
            IconButton(
              tooltip: 'Geräte auf 0',
              icon: const Icon(Icons.power_settings_new),
              onPressed: () => app.engine.setMany([
                for (final f in fixtures)
                  for (var c = 0; c < (app.profileOf(f)?.footprint ?? 0); c++)
                    (f.universe, f.address - 1 + c, 0),
              ]),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (any((p) => p.has(ChannelType.dimmer)))
              _Section(
                title: 'Dimmer',
                child: _ValueSlider(
                  value: app.fixtureValue(first, ChannelType.dimmer) ?? 0,
                  onChanged: (v) => app.setFixtureValues(fixtures, {ChannelType.dimmer: v}),
                ),
              ),
            if (any((p) => p.hasColor)) _ColorSection(app: app, fixtures: fixtures),
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
            if (any((p) => p.has(ChannelType.strobe)))
              _Section(
                title: 'Strobe',
                child: _ValueSlider(
                  value: app.fixtureValue(first, ChannelType.strobe) ?? 0,
                  onChanged: (v) => app.setFixtureValues(fixtures, {ChannelType.strobe: v}),
                ),
              ),
            if (sameProfile && ref != null)
              _Section(
                title: 'Alle Kanäle',
                child: Column(children: [
                  for (var i = 0; i < ref.channels.length; i++)
                    Row(children: [
                      SizedBox(
                        width: 90,
                        child: Text('${i + 1} ${ref.channels[i].name}',
                            overflow: TextOverflow.ellipsis),
                      ),
                      Expanded(
                        child: _ValueSlider(
                          value: app.engine.getChannel(first.universe, first.address - 1 + i),
                          onChanged: (v) => app.setFixtureChannel(fixtures, i, v),
                        ),
                      ),
                    ]),
                ]),
              ),
          ],
        ),
      );
    });
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          child,
        ]),
      );
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

class _ColorSection extends StatelessWidget {
  const _ColorSection({required this.app, required this.fixtures});
  final AppState app;
  final List<Fixture> fixtures;

  static const _presets = <Color>[
    Color(0xFFFF0000), Color(0xFFFF8000), Color(0xFFFFFF00), Color(0xFF00FF00),
    Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFF8000FF), Color(0xFFFF00FF),
    Color(0xFFFFFFFF), Color(0xFFFFC080),
  ];

  static int _c(double ch) => (ch * 255).round();

  @override
  Widget build(BuildContext context) {
    final f = fixtures.first;
    int v(ChannelType t) => app.fixtureValue(f, t) ?? 0;
    final w = v(ChannelType.white);
    final r = (v(ChannelType.red) + w).clamp(0, 255).toInt();
    final g = (v(ChannelType.green) + w).clamp(0, 255).toInt();
    final b = (v(ChannelType.blue) + w).clamp(0, 255).toInt();

    return _Section(
      title: 'Farbe',
      child: Column(children: [
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
              onTap: () => app.setFixtureColor(fixtures, _c(c.r), _c(c.g), _c(c.b)),
              child: CircleAvatar(radius: 18, backgroundColor: c),
            ),
        ]),
        const SizedBox(height: 8),
        _ValueSlider(
            value: r,
            color: Colors.red,
            onChanged: (x) => app.setFixtureColor(fixtures, x, g, b)),
        _ValueSlider(
            value: g,
            color: Colors.green,
            onChanged: (x) => app.setFixtureColor(fixtures, r, x, b)),
        _ValueSlider(
            value: b,
            color: Colors.blue,
            onChanged: (x) => app.setFixtureColor(fixtures, r, g, x)),
      ]),
    );
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
