import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import 'app_scope.dart';

class ScenesScreen extends StatelessWidget {
  const ScenesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 2,
      child: Column(children: [
        TabBar(tabs: [Tab(text: 'Szenen'), Tab(text: 'Chaser')]),
        Expanded(child: TabBarView(children: [_SceneTab(), _ChaseTab()])),
      ]),
    );
  }
}

// ---------------- Szenen ----------------

class _SceneTab extends StatelessWidget {
  const _SceneTab();

  Future<void> _save(BuildContext context, AppState app) async {
    final name = await _askText(context, 'Szene speichern', 'Szene ${app.scenes.length + 1}');
    if (name != null) app.saveScene(name);
  }

  @override
  Widget build(BuildContext context) {
    return AppListener(
      engine: false,
      builder: (context, app) => Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.save_alt),
          label: const Text('Aktuellen Zustand speichern'),
          onPressed: () => _save(context, app),
        ),
        body: app.scenes.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('Stell Licht ein und speichere es als Szene.',
                      textAlign: TextAlign.center),
                ))
            : GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180,
                  childAspectRatio: 1.6,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                ),
                itemCount: app.scenes.length,
                itemBuilder: (context, i) {
                  final s = app.scenes[i];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => app.engine.recallScene(s),
                      onLongPress: () => _sceneMenu(context, app, s),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium),
                            const Spacer(),
                            Row(children: [
                              const Icon(Icons.timelapse, size: 14),
                              const SizedBox(width: 4),
                              Text('${(s.fadeMs / 1000).toStringAsFixed(1)} s',
                                  style: Theme.of(context).textTheme.labelSmall),
                            ]),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  void _sceneMenu(BuildContext context, AppState app, Scene s) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(s.name, style: Theme.of(ctx).textTheme.titleMedium)),
          ListTile(
            leading: const Icon(Icons.flash_on),
            title: const Text('Sofort abrufen (ohne Fade)'),
            onTap: () {
              app.engine.recallScene(s, fadeMs: 0);
              Navigator.pop(ctx);
            },
          ),
          ListTile(
            leading: const Icon(Icons.save),
            title: const Text('Mit aktuellem Zustand überschreiben'),
            onTap: () {
              app.overwriteScene(s);
              Navigator.pop(ctx);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Umbenennen'),
            onTap: () async {
              Navigator.pop(ctx);
              final n = await _askText(context, 'Umbenennen', s.name);
              if (n != null) app.updateScene(s, name: n);
            },
          ),
          ListTile(
            leading: const Icon(Icons.timelapse),
            title: Text('Fade-Zeit: ${(s.fadeMs / 1000).toStringAsFixed(1)} s'),
            onTap: () async {
              Navigator.pop(ctx);
              final ms = await _askMs(context, 'Fade-Zeit', s.fadeMs);
              if (ms != null) app.updateScene(s, fadeMs: ms);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Löschen'),
            onTap: () {
              app.deleteScene(s);
              Navigator.pop(ctx);
            },
          ),
        ]),
      ),
    );
  }
}

// ---------------- Chaser ----------------

class _ChaseTab extends StatelessWidget {
  const _ChaseTab();

  @override
  Widget build(BuildContext context) {
    return AppListener(
      builder: (context, app) => Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton(
          child: const Icon(Icons.add),
          onPressed: app.scenes.isEmpty
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ChaseEditor(
                      chase: Chase(id: newId(), name: 'Chaser ${app.chases.length + 1}', steps: []),
                    ),
                  )),
        ),
        body: app.chases.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    app.scenes.isEmpty
                        ? 'Erst Szenen anlegen – ein Chaser spielt Szenen nacheinander ab.'
                        : 'Noch keine Chaser. Mit + anlegen.',
                    textAlign: TextAlign.center,
                  ),
                ))
            : ListView(
                padding: const EdgeInsets.only(bottom: 88),
                children: [
                  for (final c in app.chases)
                    ListTile(
                      leading: IconButton.filledTonal(
                        icon: Icon(app.engine.activeChaseId == c.id
                            ? Icons.stop
                            : Icons.play_arrow),
                        onPressed: () => app.engine.activeChaseId == c.id
                            ? app.engine.stopChase()
                            : app.playChase(c),
                      ),
                      title: Text(c.name),
                      subtitle: Text('${c.steps.length} Schritte${c.loop ? ' · Schleife' : ''}'),
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => ChaseEditor(chase: c))),
                    ),
                ],
              ),
      ),
    );
  }
}

class ChaseEditor extends StatefulWidget {
  const ChaseEditor({super.key, required this.chase});
  final Chase chase;

  @override
  State<ChaseEditor> createState() => _ChaseEditorState();
}

class _ChaseEditorState extends State<ChaseEditor> {
  late final _name = TextEditingController(text: widget.chase.name);

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = widget.chase;
    final isNew = !app.chases.contains(c);
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'Neuer Chaser' : 'Chaser bearbeiten'),
        actions: [
          if (!isNew)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                app.deleteChase(c);
                Navigator.pop(context);
              },
            ),
          TextButton(
            onPressed: () {
              c.name = _name.text.trim().isEmpty ? c.name : _name.text.trim();
              app.saveChase(c);
              Navigator.pop(context);
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Schritt'),
        onPressed: () async {
          final s = await showModalBottomSheet<Scene>(
            context: context,
            builder: (ctx) => ListView(children: [
              for (final s in app.scenes)
                ListTile(title: Text(s.name), onTap: () => Navigator.pop(ctx, s)),
            ]),
          );
          if (s != null) setState(() => c.steps.add(ChaseStep(sceneId: s.id)));
        },
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
        ),
        SwitchListTile(
          title: const Text('Endlos wiederholen'),
          value: c.loop,
          onChanged: (v) => setState(() => c.loop = v),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: c.steps.length,
            onReorder: (a, b) => setState(() {
              if (b > a) b--;
              c.steps.insert(b, c.steps.removeAt(a));
            }),
            itemBuilder: (context, i) {
              final st = c.steps[i];
              final scene = app.sceneById(st.sceneId);
              return ListTile(
                key: ObjectKey(st),
                leading: CircleAvatar(child: Text('${i + 1}')),
                title: Text(scene?.name ?? '(gelöscht)'),
                subtitle: Text('Fade ${(st.fadeMs / 1000).toStringAsFixed(1)} s · '
                    'Halten ${(st.holdMs / 1000).toStringAsFixed(1)} s'),
                onTap: () async {
                  final fade = await _askMs(context, 'Fade-Zeit', st.fadeMs);
                  if (fade == null || !context.mounted) return;
                  final hold = await _askMs(context, 'Haltezeit', st.holdMs);
                  if (!mounted) return;
                  setState(() {
                    st.fadeMs = fade;
                    if (hold != null) st.holdMs = hold;
                  });
                },
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => c.steps.removeAt(i)),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ---------------- Dialog-Helfer ----------------

Future<String?> _askText(BuildContext context, String title, String initial) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: ctrl, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim().isEmpty ? null : ctrl.text.trim()),
            child: const Text('OK')),
      ],
    ),
  );
}

Future<int?> _askMs(BuildContext context, String title, int initialMs) {
  final ctrl = TextEditingController(text: (initialMs / 1000).toStringAsFixed(1));
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(suffixText: 'Sekunden'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: () {
            final s = double.tryParse(ctrl.text.replaceAll(',', '.'));
            Navigator.pop(ctx, s == null || s < 0 ? null : (s * 1000).round());
          },
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
