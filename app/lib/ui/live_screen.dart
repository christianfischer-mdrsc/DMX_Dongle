import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import 'app_scope.dart';
import 'effect_editor.dart';
import 'home_screen.dart';

/// Bühnen-Ansicht: große Tasten für Effekte, Szenen und Abläufe,
/// Tap-Tempo oben. Solange sie offen ist, bleibt der Bildschirm an.
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key, required this.active});

  /// true, wenn dieser Reiter gerade sichtbar ist.
  final bool active;

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  @override
  void initState() {
    super.initState();
    _wake(widget.active);
  }

  @override
  void didUpdateWidget(covariant LiveScreen old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _wake(widget.active);
  }

  @override
  void dispose() {
    _wake(false);
    super.dispose();
  }

  void _wake(bool on) {
    WakelockPlus.toggle(enable: on).catchError((_) {});
  }

  void _editEffect(Effect? e) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => EffectEditor(effect: e)),
      );

  @override
  Widget build(BuildContext context) {
    return AppListener(builder: (context, app) {
      final e = app.engine;
      final anyEffect = app.effects.any(app.isEffectRunning);
      return Scaffold(
        appBar: AppBar(
          title: const Text('Live'),
          actions: [
            if (anyEffect)
              TextButton.icon(
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Effekte aus'),
                onPressed: e.stopAllEffects,
              ),
            const ConnectionChip(),
          ],
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
          const _TempoCard(),
          _Header('Effekte', action: TextButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Neu'),
            onPressed: () => _editEffect(null),
          )),
          if (app.effects.isEmpty)
            _Hint('Effekte wie Regenbogen, Lauflicht oder Strobe legst du mit „Neu“ an.')
          else
            _ButtonGrid(children: [
              for (final ef in app.effects)
                _LiveButton(
                  icon: effectIcons[ef.type]!,
                  label: ef.name,
                  sub: '${ef.fixtureIds.length} Lampen',
                  active: app.isEffectRunning(ef),
                  onTap: () => app.toggleEffect(ef),
                  onLongPress: () => _editEffect(ef),
                ),
            ]),
          const _Header('Szenen'),
          if (app.scenes.isEmpty)
            _Hint('Szenen speicherst du im Reiter „Szenen“.')
          else
            _ButtonGrid(children: [
              for (final sc in app.scenes)
                _LiveButton(
                  icon: Icons.auto_awesome_outlined,
                  label: sc.name,
                  sub: '${(sc.fadeMs / 1000).toStringAsFixed(1)} s',
                  active: false,
                  onTap: () => e.recallScene(sc),
                  onLongPress: () => e.recallScene(sc, fadeMs: 0),
                ),
            ]),
          const _Header('Abläufe'),
          if (app.chases.isEmpty)
            _Hint('Abläufe legst du im Reiter „Szenen“ unter „Abläufe“ an.')
          else
            _ButtonGrid(children: [
              for (final c in app.chases)
                _LiveButton(
                  icon: c.bpmSync ? Icons.music_note_outlined : Icons.repeat,
                  label: c.name,
                  sub: c.bpmSync ? 'im Takt' : '${c.steps.length} Schritte',
                  active: e.activeChaseId == c.id,
                  onTap: () => e.activeChaseId == c.id ? e.stopChase() : app.playChase(c),
                ),
            ]),
          const SizedBox(height: 8),
          _Hint('Tippen schaltet, lang drücken bearbeitet einen Effekt bzw. ruft eine Szene ohne Überblendung ab.'),
        ]),
      );
    });
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text, {this.action});
  final String text;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 0, 8),
        child: Row(children: [
          Expanded(
            child: Text(text.toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    )),
          ),
          if (action != null) action!,
        ]),
      );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

class _ButtonGrid extends StatelessWidget {
  const _ButtonGrid({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 170,
          mainAxisExtent: 96,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
        ),
        children: children,
      );
}

class _LiveButton extends StatelessWidget {
  const _LiveButton({
    required this.icon,
    required this.label,
    required this.sub,
    required this.active,
    required this.onTap,
    this.onLongPress,
  });
  final IconData icon;
  final String label, sub;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final fg = active ? s.onPrimary : s.onSurface;
    return Material(
      color: active ? s.primary : s.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: active ? s.primary : s.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        onLongPress: onLongPress == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                onLongPress!();
              },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: active ? s.onPrimary : s.primary),
            const Spacer(),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
            Text(sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg.withValues(alpha: 0.75), fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}

/// Tempo: große BPM-Zahl, blinkender Schlag, TAP-Taste, ±.
class _TempoCard extends StatefulWidget {
  const _TempoCard();
  @override
  State<_TempoCard> createState() => _TempoCardState();
}

class _TempoCardState extends State<_TempoCard> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _beat = 0;
  late AppState _app;

  @override
  void initState() {
    super.initState();
    _app = AppScope.of(context);
    _ticker = createTicker((_) {
      final b = _app.engine.beatPhase;
      if ((b < 0.15) != (_beat < 0.15)) setState(() => _beat = b);
      _beat = b;
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final e = _app.engine;
    final flash = _beat < 0.15;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 60),
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: flash ? const Color(0xFFFFB020) : s.surfaceContainerHighest,
            ),
          ),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${e.bpm.round()}',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()])),
            Text('BPM', style: TextStyle(color: s.onSurfaceVariant, fontSize: 12)),
          ]),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Langsamer',
            icon: const Icon(Icons.remove),
            onPressed: () => e.bpm = e.bpm - 1,
          ),
          IconButton(
            tooltip: 'Schneller',
            icon: const Icon(Icons.add),
            onPressed: () => e.bpm = e.bpm + 1,
          ),
          const Spacer(),
          SizedBox(
            width: 104,
            height: 64,
            child: FilledButton(
              style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
              onPressed: () {
                HapticFeedback.lightImpact();
                e.tap();
              },
              child: const Text('TAP', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 2)),
            ),
          ),
        ]),
      ),
    );
  }
}
