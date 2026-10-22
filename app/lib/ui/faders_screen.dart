import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import 'app_scope.dart';

/// Rohe Kanal-Fader, 512 pro Universe, horizontal scrollbar.
class FadersScreen extends StatefulWidget {
  const FadersScreen({super.key});

  @override
  State<FadersScreen> createState() => _FadersScreenState();
}

class _FadersScreenState extends State<FadersScreen> {
  int _universe = 0;
  final _scroll = ScrollController();
  static const _faderWidth = 52.0;

  void _jumpTo(int ch) => _scroll.animateTo(
        (ch * _faderWidth).clamp(0.0, _scroll.position.maxScrollExtent).toDouble(),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Column(
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
    );
  }
}

class _Fader extends StatelessWidget {
  const _Fader({
    required this.channel,
    required this.value,
    required this.onChanged,
    this.label,
  });

  final int channel;
  final int value;
  final String? label;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.labelSmall;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Text('$value',
              style: TextStyle(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: value > 0 ? scheme.primary : scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              )),
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
          GestureDetector(
            onTap: () => onChanged(value == 255 ? 0 : 255),
            child: Text('${channel + 1}',
                style: small?.copyWith(fontWeight: FontWeight.bold)),
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
      ),
    );
  }
}
