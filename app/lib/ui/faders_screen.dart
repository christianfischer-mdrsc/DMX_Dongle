import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'app_scope.dart';
import 'home_screen.dart';

/// Rohe Kanal-Fader, 512 pro Universe, horizontal scrollbar.
class FadersScreen extends StatefulWidget {
  const FadersScreen({super.key});

  @override
  State<FadersScreen> createState() => _FadersScreenState();
}

class _FadersScreenState extends State<FadersScreen> {
  int _universe = 0;
  final _scroll = ScrollController();
  static const _faderWidth = 56.0;

  void _jumpTo(int ch) => _scroll.animateTo(
        (ch * _faderWidth).clamp(0.0, _scroll.position.maxScrollExtent).toDouble(),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Fader'), actions: const [ConnectionChip()]),
      body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              ListenableBuilder(
                listenable: app,
                builder: (_, __) {
                  final n = app.engine.universeCount;
                  if (_universe >= n) _universe = 0;
                  return DropdownButton<int>(
                    value: _universe,
                    items: [
                      for (var i = 0; i < n; i++)
                        DropdownMenuItem(value: i, child: Text('Universe ${i + 1}')),
                    ],
                    onChanged: (v) => setState(() => _universe = v ?? 0),
                  );
                },
              ),
              const Spacer(),
              PopupMenuButton<int>(
                tooltip: 'Springen',
                icon: const Icon(Icons.low_priority),
                itemBuilder: (_) => [
                  for (var c = 0; c < 512; c += 64)
                    PopupMenuItem(value: c, child: Text('Kanal ${c + 1}')),
                ],
                onSelected: _jumpTo,
              ),
              IconButton(
                tooltip: 'Alles auf 0',
                icon: const Icon(Icons.restart_alt),
                onPressed: () => app.engine.clearAll(),
              ),
            ],
          ),
        ),
        Expanded(
          child: AppListener(
            builder: (context, app) => ListView.builder(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              itemExtent: _faderWidth,
              itemCount: 512,
              itemBuilder: (context, ch) {
                final owner = app.channelOwner(_universe, ch);
                return _Fader(
                  app: app,
                  universe: _universe,
                  channel: ch,
                  value: app.engine.getChannel(_universe, ch),
                  label: owner == null ? null : '${owner.$1.name}\n${owner.$2.name}',
                  onChanged: (v) => app.engine.setChannel(_universe, ch, v),
                );
              },
            ),
          ),
        ),
      ],
    ),
    );
  }
}

/// Ein Kanal: Schieber = eingestellter Wert. Daneben der Live-Pegel, also was
/// wirklich rausgeht (mit Effekten, Grandmaster, Gruppen-Mastern). Steuert ein
/// Effekt den Kanal, ist der Pegel bernsteinfarben und „FX“ steht darüber.
class _Fader extends StatelessWidget {
  const _Fader({
    required this.app,
    required this.universe,
    required this.channel,
    required this.value,
    required this.onChanged,
    this.label,
  });

  final AppState app;
  final int universe;
  final int channel;
  final int value;
  final String? label;
  final ValueChanged<int> onChanged;

  static const fxColor = Color(0xFFFFB020);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.labelSmall;
    final e = app.engine;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ValueListenableBuilder<int>(
        valueListenable: e.live,
        builder: (context, _, __) {
          final out = e.liveValue(universe, channel);
          final fx = e.isEffectChannel(universe, channel);
          final shown = fx || out != value ? out : value;
          return Column(
            children: [
              SizedBox(
                height: 12,
                child: fx
                    ? Text('FX', style: small?.copyWith(color: fxColor, fontWeight: FontWeight.w800, fontSize: 9))
                    : null,
              ),
              Text('$shown',
                  style: TextStyle(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: fx ? fxColor : (shown > 0 ? scheme.primary : scheme.onSurfaceVariant),
                    fontWeight: FontWeight.w600,
                  )),
              Expanded(
                child: Row(children: [
                  // Live-Pegel
                  Container(
                    width: 4,
                    margin: const EdgeInsets.only(left: 3, top: 14, bottom: 14),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: out / 255,
                      child: Container(
                        decoration: BoxDecoration(
                          color: fx ? fxColor : scheme.primary.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) => RotatedBox(
                        quarterTurns: 3,
                        child: SizedBox(
                          width: c.maxHeight,
                          child: Slider(
                            value: value.toDouble(),
                            max: 255,
                            onChanged: (v) => onChanged(v.round()),
                          ),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
              GestureDetector(
                onTap: () => onChanged(value == 255 ? 0 : 255),
                child: Text('${channel + 1}', style: small?.copyWith(fontWeight: FontWeight.bold)),
              ),
              SizedBox(
                height: 28,
                child: Text(
                  label ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: small?.copyWith(color: scheme.onSurfaceVariant, fontSize: 9),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
