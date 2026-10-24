import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/account_service.dart';
import '../services/admin_api.dart';
import 'app_scope.dart';

/// Admin-Bereich: Übersicht & Einstellungen, Codes, Nutzer, Protokoll.
/// Nur sichtbar für Konten in der Tabelle `admins`. Jede Aktion wird auf
/// dem Server nochmals geprüft.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).account.admin;
    if (api == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin')),
        body: const Center(child: Text('Im Testmodus gibt es keinen Admin-Bereich.')),
      );
    }
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Übersicht'),
              Tab(text: 'Codes'),
              Tab(text: 'Nutzer'),
              Tab(text: 'Protokoll'),
            ],
          ),
        ),
        body: TabBarView(children: [
          _OverviewTab(api: api),
          _CodesTab(api: api),
          _UsersTab(api: api),
          _LogTab(api: api),
        ]),
      ),
    );
  }
}

// ======================================================================
// Hilfen
// ======================================================================

String fmtDate(DateTime d, {bool time = true}) {
  String two(int n) => n.toString().padLeft(2, '0');
  final day = '${two(d.day)}.${two(d.month)}.${d.year}';
  return time ? '$day ${two(d.hour)}:${two(d.minute)}' : day;
}

void _snack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

Future<void> _copy(BuildContext context, String text, String what) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) _snack(context, '$what kopiert');
}

/// Lädt Daten, zeigt Laden/Fehler/Inhalt, Ziehen zum Aktualisieren.
class _Loader<T> extends StatefulWidget {
  const _Loader({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext, T, Future<void> Function() reload) builder;

  @override
  State<_Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<_Loader<T>> {
  late Future<T> _f = widget.load();

  Future<void> _reload() async {
    final f = widget.load();
    setState(() => _f = f);
    try {
      await f;
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant _Loader<T> old) {
    super.didUpdateWidget(old);
    if (old.key != widget.key) _f = widget.load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _f,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          final msg = snap.error is AccountException ? snap.error.toString() : 'Fehler: ${snap.error}';
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.cloud_off_outlined, size: 40, color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 12),
                Text(msg, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.tonal(onPressed: _reload, child: const Text('Erneut versuchen')),
              ]),
            ),
          );
        }
        return RefreshIndicator(onRefresh: _reload, child: widget.builder(context, snap.data as T, _reload));
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(text.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                )),
      );
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color);
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

// ======================================================================
// Übersicht & Einstellungen
// ======================================================================

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.api});
  final AdminApi api;

  @override
  Widget build(BuildContext context) {
    return _Loader<(AdminStats, List<PackInfo>)>(
      load: () async => (await api.stats(), await api.packs()),
      builder: (context, data, reload) {
        final (st, packs) = data;
        final s = Theme.of(context).colorScheme;
        Widget tile(String value, String label, IconData icon) => Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon, size: 20, color: s.primary),
                  const SizedBox(height: 10),
                  Text(value,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                  Text(label, style: TextStyle(color: s.onSurfaceVariant, fontSize: 13)),
                ]),
              ),
            );
        return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          const _SectionTitle('Zahlen'),
          GridView.count(
            crossAxisCount: MediaQuery.sizeOf(context).width > 600 ? 3 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.45,
            children: [
              tile('${st.users}', 'Konten, ${st.usersConfirmed} bestätigt', Icons.people_outline),
              tile('+${st.users7d}', 'neue Konten in 7 Tagen', Icons.person_add_alt),
              tile('${st.codesOpen}', 'Codes einlösbar, ${st.codes} gesamt', Icons.key_outlined),
              tile('${st.redemptions}', 'Einlösungen, ${st.redemptions7d} in 7 Tagen', Icons.redeem),
            ],
          ),
          const _SectionTitle('Pakete'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final p in packs)
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(p.name),
                  subtitle: Text(
                      '${p.id} · ${st.packs.where((x) => x.id == p.id).map((x) => x.owners).firstOrNull ?? 0} Besitzer'
                      '${p.description.isEmpty ? '' : '\n${p.description}'}'),
                  isThreeLine: p.description.isNotEmpty,
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () async {
                    final changed = await showDialog<bool>(
                        context: context, builder: (_) => _PackDialog(api: api, pack: p));
                    if (changed == true) reload();
                  },
                ),
            ]),
          ),
          const _SectionTitle('Hinweis an alle'),
          _SettingsCard(api: api),
        ]);
      },
    );
  }
}

class _PackDialog extends StatefulWidget {
  const _PackDialog({required this.api, required this.pack});
  final AdminApi api;
  final PackInfo pack;
  @override
  State<_PackDialog> createState() => _PackDialogState();
}

class _PackDialogState extends State<_PackDialog> {
  late final _name = TextEditingController(text: widget.pack.name);
  late final _desc = TextEditingController(text: widget.pack.description);
  String? _error;
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await widget.api.updatePack(widget.pack.id, _name.text, _desc.text);
      if (mounted) Navigator.pop(context, true);
    } on AccountException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Paket ${widget.pack.id}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Beschreibung'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          FilledButton(onPressed: _busy ? null : _save, child: const Text('Speichern')),
        ],
      );
}

class _SettingsCard extends StatefulWidget {
  const _SettingsCard({required this.api});
  final AdminApi api;
  @override
  State<_SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends State<_SettingsCard> {
  late final TextEditingController _text;
  late final TextEditingController _email;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final app = AppScope.of(context);
    _text = TextEditingController(text: app.announcement);
    _email = TextEditingController(text: app.supportEmail);
  }

  @override
  void dispose() {
    _text.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save({bool clear = false}) async {
    final app = AppScope.of(context);
    setState(() => _busy = true);
    try {
      if (clear) _text.clear();
      final t = _text.text.trim();
      await widget.api.setSetting('announcement', t.isEmpty ? null : {'text': t});
      final e = _email.text.trim();
      await widget.api.setSetting('support_email', e.isEmpty ? null : e);
      await app.refreshAppSettings();
      if (mounted) _snack(context, t.isEmpty ? 'Hinweis entfernt' : 'Hinweis veröffentlicht');
    } on AccountException catch (e) {
      if (mounted) _snack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Erscheint bei allen Nutzern oben auf der Startseite, bis sie ihn wegtippen.',
              style: TextStyle(color: s.onSurfaceVariant)),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            minLines: 2,
            maxLines: 5,
            maxLength: 280,
            decoration: const InputDecoration(
              labelText: 'Hinweis',
              hintText: 'z. B. Neue Pro-Geräte verfügbar!',
            ),
          ),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Support-E-Mail (in den Einstellungen sichtbar)',
              prefixIcon: Icon(Icons.support_agent_outlined),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : () => _save(clear: true),
                child: const Text('Hinweis entfernen'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _busy ? null : _save,
                child: const Text('Speichern'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ======================================================================
// Codes
// ======================================================================

class _CodesTab extends StatefulWidget {
  const _CodesTab({required this.api});
  final AdminApi api;
  @override
  State<_CodesTab> createState() => _CodesTabState();
}

class _CodesTabState extends State<_CodesTab> {
  String _search = '';
  int _gen = 0;

  void _refresh() => setState(() => _gen++);

  Future<void> _create() async {
    final codes = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _GenerateSheet(api: widget.api),
    );
    if (codes == null || !mounted) return;
    _refresh();
    await showDialog(context: context, builder: (_) => _NewCodesDialog(codes: codes));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Codes erzeugen'),
        onPressed: _create,
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Code oder Notiz suchen',
            ),
            onSubmitted: (v) => setState(() {
              _search = v.trim();
              _gen++;
            }),
          ),
        ),
        Expanded(
          child: _Loader<List<AdminCode>>(
            key: ValueKey('codes-$_gen-$_search'),
            load: () => widget.api.codes(search: _search.isEmpty ? null : _search),
            builder: (context, codes, reload) {
              if (codes.isEmpty) {
                return ListView(children: const [
                  Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Keine Codes gefunden.', textAlign: TextAlign.center),
                  ),
                ]);
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: codes.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _CodeTile(
                  code: codes[i],
                  onTap: () async {
                    await showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => _CodeSheet(api: widget.api, code: codes[i]),
                    );
                    reload();
                  },
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

(String, Color) _stateLabel(BuildContext context, CodeState st) {
  final s = Theme.of(context).colorScheme;
  return switch (st) {
    CodeState.open => ('einlösbar', const Color(0xFF1E8E4E)),
    CodeState.usedUp => ('aufgebraucht', s.outline),
    CodeState.expired => ('abgelaufen', const Color(0xFFB26A00)),
    CodeState.blocked => ('gesperrt', s.error),
  };
}

class _CodeTile extends StatelessWidget {
  const _CodeTile({required this.code, required this.onTap});
  final AdminCode code;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final (label, color) = _stateLabel(context, code.state);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(code.code,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 1)),
              ),
              _Pill(label, color),
            ]),
            const SizedBox(height: 6),
            Text(
              '${code.redemptionCount} / ${code.maxRedemptions} eingelöst · ${code.packIds.join(', ')}'
              '${code.expiresAt == null ? '' : ' · bis ${fmtDate(code.expiresAt!, time: false)}'}',
              style: TextStyle(color: s.onSurfaceVariant, fontSize: 13),
            ),
            if ((code.note ?? '').isNotEmpty)
              Text(code.note!, style: TextStyle(color: s.onSurfaceVariant, fontSize: 13)),
          ]),
        ),
      ),
    );
  }
}

class _CodeSheet extends StatefulWidget {
  const _CodeSheet({required this.api, required this.code});
  final AdminApi api;
  final AdminCode code;
  @override
  State<_CodeSheet> createState() => _CodeSheetState();
}

class _CodeSheetState extends State<_CodeSheet> {
  late bool _active = widget.code.active;
  bool _busy = false;

  Future<void> _toggle() async {
    setState(() => _busy = true);
    try {
      await widget.api.setCodeActive(widget.code.id, !_active);
      setState(() => _active = !_active);
    } on AccountException catch (e) {
      if (mounted) _snack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.code;
    final s = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: SelectableText(c.code,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
            ),
            IconButton(
              tooltip: 'Kopieren',
              icon: const Icon(Icons.copy),
              onPressed: () => _copy(context, c.code, 'Code'),
            ),
          ]),
          const SizedBox(height: 8),
          Text('Pakete: ${c.packIds.join(', ')}'),
          Text('Eingelöst: ${c.redemptionCount} von ${c.maxRedemptions}'),
          Text('Gültig bis: ${c.expiresAt == null ? 'unbegrenzt' : fmtDate(c.expiresAt!)}'),
          Text('Erstellt: ${fmtDate(c.createdAt)}'),
          if ((c.note ?? '').isNotEmpty) Text('Notiz: ${c.note}'),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Code ist aktiv'),
            subtitle: Text(_active
                ? 'Kann eingelöst werden.'
                : 'Gesperrt: lässt sich nicht mehr einlösen. Bereits freigeschaltete Pakete bleiben.'),
            value: _active,
            onChanged: _busy ? null : (_) => _toggle(),
          ),
          const SizedBox(height: 8),
          Text('Eingelöst von', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          FutureBuilder<List<CodeRedemption>>(
            future: widget.api.codeRedemptions(c.id),
            builder: (context, snap) {
              if (!snap.hasData) {
                return snap.hasError
                    ? Text(snap.error.toString(), style: TextStyle(color: s.error))
                    : const LinearProgressIndicator();
              }
              if (snap.data!.isEmpty) {
                return Text('Noch von niemandem.', style: TextStyle(color: s.onSurfaceVariant));
              }
              return Column(children: [
                for (final r in snap.data!)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_outline),
                    title: Text(r.email),
                    trailing: Text(fmtDate(r.redeemedAt)),
                  ),
              ]);
            },
          ),
        ]),
      ),
    );
  }
}

class _GenerateSheet extends StatefulWidget {
  const _GenerateSheet({required this.api});
  final AdminApi api;
  @override
  State<_GenerateSheet> createState() => _GenerateSheetState();
}

class _GenerateSheetState extends State<_GenerateSheet> {
  final Set<String> _packs = {};
  final _count = TextEditingController(text: '10');
  final _max = TextEditingController(text: '1');
  final _note = TextEditingController();
  int? _validDays; // null = unbegrenzt
  bool _busy = false;
  String? _error;
  late final Future<List<PackInfo>> _packList = widget.api.packs();

  Future<void> _submit() async {
    final count = int.tryParse(_count.text) ?? 0;
    final max = int.tryParse(_max.text) ?? 0;
    if (_packs.isEmpty) return setState(() => _error = 'Mindestens ein Paket wählen.');
    if (count < 1 || count > 500) return setState(() => _error = 'Anzahl: 1 bis 500.');
    if (max < 1) return setState(() => _error = 'Einlösungen pro Code: mindestens 1.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final codes = await widget.api.generateCodes(
        packIds: _packs.toList(),
        count: count,
        maxRedemptions: max,
        expiresAt: _validDays == null ? null : DateTime.now().add(Duration(days: _validDays!)),
        note: _note.text,
      );
      if (mounted) Navigator.pop(context, codes);
    } on AccountException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Codes erzeugen', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          const Text('Schaltet frei'),
          FutureBuilder<List<PackInfo>>(
            future: _packList,
            builder: (context, snap) => snap.hasData
                ? Wrap(spacing: 8, children: [
                    for (final p in snap.data!)
                      FilterChip(
                        label: Text(p.name),
                        selected: _packs.contains(p.id),
                        onSelected: (v) => setState(() => v ? _packs.add(p.id) : _packs.remove(p.id)),
                      ),
                  ])
                : const LinearProgressIndicator(),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _count,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Anzahl Codes', helperText: '1 bis 500'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _max,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Einlösungen pro Code', helperText: '1 = Einmal-Code'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            initialValue: _validDays,
            decoration: const InputDecoration(labelText: 'Gültig'),
            items: const [
              DropdownMenuItem(value: null, child: Text('unbegrenzt')),
              DropdownMenuItem(value: 7, child: Text('7 Tage')),
              DropdownMenuItem(value: 30, child: Text('30 Tage')),
              DropdownMenuItem(value: 90, child: Text('90 Tage')),
              DropdownMenuItem(value: 365, child: Text('1 Jahr')),
            ],
            onChanged: (v) => setState(() => _validDays = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
              labelText: 'Notiz (nur für dich)',
              hintText: 'z. B. Kunde Müller, Messe 2026',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: s.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Text('Erzeugen'),
          ),
        ]),
      ),
    );
  }
}

class _NewCodesDialog extends StatelessWidget {
  const _NewCodesDialog({required this.codes});
  final List<String> codes;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(codes.length == 1 ? 'Neuer Code' : '${codes.length} neue Codes'),
        content: SizedBox(
          width: 320,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: SingleChildScrollView(
              child: SelectableText(
                codes.join('\n'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 16, height: 1.6, letterSpacing: 1),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Schließen')),
          FilledButton.icon(
            icon: const Icon(Icons.copy),
            label: Text(codes.length == 1 ? 'Kopieren' : 'Alle kopieren'),
            onPressed: () => _copy(context, codes.join('\n'), codes.length == 1 ? 'Code' : 'Codes'),
          ),
        ],
      );
}

// ======================================================================
// Nutzer
// ======================================================================

class _UsersTab extends StatefulWidget {
  const _UsersTab({required this.api});
  final AdminApi api;
  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  String _search = '';
  int _gen = 0;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'E-Mail oder Name suchen'),
          onSubmitted: (v) => setState(() {
            _search = v.trim();
            _gen++;
          }),
        ),
      ),
      Expanded(
        child: _Loader<List<AdminUser>>(
          key: ValueKey('users-$_gen-$_search'),
          load: () => widget.api.users(search: _search.isEmpty ? null : _search),
          builder: (context, users, reload) => ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: users.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final u = users[i];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                  title: Text(u.email, overflow: TextOverflow.ellipsis),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(spacing: 6, runSpacing: 6, children: [
                      if (u.isAdmin) _Pill('Admin', s.primary),
                      if (!u.confirmed) _Pill('nicht bestätigt', const Color(0xFFB26A00)),
                      for (final p in u.packs) _Pill(p, s.tertiary),
                      Text('seit ${fmtDate(u.createdAt, time: false)}',
                          style: TextStyle(color: s.onSurfaceVariant, fontSize: 12)),
                    ]),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => _UserSheet(api: widget.api, user: u),
                    );
                    reload();
                  },
                ),
              );
            },
          ),
        ),
      ),
    ]);
  }
}

class _UserSheet extends StatefulWidget {
  const _UserSheet({required this.api, required this.user});
  final AdminApi api;
  final AdminUser user;
  @override
  State<_UserSheet> createState() => _UserSheetState();
}

class _UserSheetState extends State<_UserSheet> {
  late final Set<String> _packs = widget.user.packs.toSet();
  late bool _admin = widget.user.isAdmin;
  late final Future<List<PackInfo>> _packList = widget.api.packs();
  bool _busy = false;

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } on AccountException catch (e) {
      if (mounted) _snack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ja')),
          ],
        ),
      ) ==
      true;

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final me = AppScope.of(context).user?.id == u.id;
    final s = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(u.email, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            if (u.displayName.isNotEmpty) Text(u.displayName),
            const SizedBox(height: 8),
            Text('Registriert: ${fmtDate(u.createdAt)}', style: TextStyle(color: s.onSurfaceVariant)),
            Text('Zuletzt angemeldet: ${u.lastSignInAt == null ? 'nie' : fmtDate(u.lastSignInAt!)}',
                style: TextStyle(color: s.onSurfaceVariant)),
            Text('E-Mail bestätigt: ${u.confirmed ? 'ja' : 'nein'}', style: TextStyle(color: s.onSurfaceVariant)),
            const SizedBox(height: 16),
            Text('Freischaltungen', style: Theme.of(context).textTheme.titleSmall),
            FutureBuilder<List<PackInfo>>(
              future: _packList,
              builder: (context, snap) => !snap.hasData
                  ? const LinearProgressIndicator()
                  : Column(children: [
                      for (final p in snap.data!)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(p.name),
                          subtitle: Text(p.id),
                          value: _packs.contains(p.id),
                          onChanged: _busy
                              ? null
                              : (v) => _run(() async {
                                    await widget.api.setEntitlement(u.id, p.id, v);
                                    setState(() => v ? _packs.add(p.id) : _packs.remove(p.id));
                                  }),
                        ),
                    ]),
            ),
            const Divider(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Admin'),
              subtitle: Text(me
                  ? 'Dein eigenes Konto – Admin-Rechte kann dir nur ein anderer Admin entziehen.'
                  : 'Darf Codes erzeugen, Nutzer verwalten und Hinweise veröffentlichen.'),
              value: _admin,
              onChanged: (_busy || me)
                  ? null
                  : (v) async {
                      final ok = await _confirm(
                        v ? 'Zum Admin machen?' : 'Admin-Rechte entziehen?',
                        v
                            ? '${u.email} bekommt vollen Zugriff auf den Admin-Bereich.'
                            : '${u.email} verliert den Zugriff auf den Admin-Bereich.',
                      );
                      if (!ok) return;
                      await _run(() async {
                        await widget.api.setAdmin(u.id, v);
                        setState(() => _admin = v);
                      });
                    },
            ),
          ]),
        ),
      ),
    );
  }
}

// ======================================================================
// Protokoll
// ======================================================================

const _actionLabels = {
  'codes_erzeugt': 'Codes erzeugt',
  'code_gesperrt': 'Code gesperrt',
  'code_aktiviert': 'Code aktiviert',
  'paket_vergeben': 'Paket vergeben',
  'paket_entzogen': 'Paket entzogen',
  'admin_ernannt': 'Admin ernannt',
  'admin_entzogen': 'Admin entzogen',
  'paket_geaendert': 'Paket geändert',
  'einstellung_geaendert': 'Einstellung geändert',
};

String _detailText(AdminLogEntry e) {
  final d = e.detail;
  switch (e.action) {
    case 'codes_erzeugt':
      return '${d['anzahl']}× ${(d['pakete'] as List?)?.join(', ')}, je ${d['einloesungen']}× einlösbar'
          '${d['notiz'] == null ? '' : ' · ${d['notiz']}'}';
    case 'code_gesperrt' || 'code_aktiviert':
      final c = d['code'] as String? ?? '';
      return c.length >= 12 ? '${c.substring(0, 4)}-${c.substring(4, 8)}-${c.substring(8)}' : c;
    case 'paket_vergeben' || 'paket_entzogen':
      return '${d['paket']} · ${d['nutzer']}';
    case 'admin_ernannt' || 'admin_entzogen':
      return '${d['nutzer']}';
    case 'einstellung_geaendert':
      final v = d['wert'];
      final text = v is Map ? v['text'] : v;
      return '${d['key']}: ${text ?? '(entfernt)'}';
    default:
      return d.entries.map((x) => '${x.key}: ${x.value}').join(', ');
  }
}

class _LogTab extends StatelessWidget {
  const _LogTab({required this.api});
  final AdminApi api;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return _Loader<List<AdminLogEntry>>(
      load: api.log,
      builder: (context, entries, _) => entries.isEmpty
          ? ListView(children: const [
              Padding(
                padding: EdgeInsets.all(32),
                child: Text('Noch keine Admin-Aktionen.', textAlign: TextAlign.center),
              ),
            ])
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 32),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (context, i) {
                final e = entries[i];
                return ListTile(
                  title: Text(_actionLabels[e.action] ?? e.action,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${_detailText(e)}\n${fmtDate(e.at)} · ${e.adminEmail ?? 'unbekannt'}'),
                  isThreeLine: true,
                  titleTextStyle: Theme.of(context).textTheme.bodyLarge,
                  subtitleTextStyle: TextStyle(color: s.onSurfaceVariant, fontSize: 13),
                );
              },
            ),
    );
  }
}
