import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/firmware_service.dart';
import '../state/app_state.dart';
import 'app_scope.dart';

/// Dongle-Firmware: Version anzeigen, Update installieren.
/// Admins können außerdem neue Versionen veröffentlichen und Dateien direkt flashen.
class FirmwareScreen extends StatefulWidget {
  const FirmwareScreen({super.key});

  @override
  State<FirmwareScreen> createState() => _FirmwareScreenState();
}

class _FirmwareScreenState extends State<FirmwareScreen> {
  DongleInfo? _info;
  String? _infoError;
  bool _infoLoaded = false;
  bool _loadingInfo = false;

  List<FirmwareRelease> _releases = const [];
  String? _relError;
  bool _loadingRel = false;

  // Laufende Aktion (Download/Upload) – blockiert die Knöpfe
  String? _busy;
  double? _progress;

  // Heruntergeladene Datei bleibt im Speicher: Download braucht Internet,
  // der Upload das Dongle-WLAN – dazwischen darf man das Netz wechseln.
  final Map<int, Uint8List> _downloaded = {};

  AppState get _app => AppScope.of(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInfo();
      _loadReleases();
    });
  }

  Future<void> _loadInfo() async {
    setState(() => _loadingInfo = true);
    try {
      final i = await DongleClient(_app.dongleIp).info();
      if (!mounted) return;
      setState(() {
        _info = i;
        _infoError = null;
        _infoLoaded = true;
      });
    } on FirmwareException catch (e) {
      if (mounted) setState(() => _infoError = e.message);
    } finally {
      if (mounted) setState(() => _loadingInfo = false);
    }
  }

  Future<void> _loadReleases() async {
    if (!_app.firmware.available) return;
    setState(() => _loadingRel = true);
    try {
      final r = await _app.firmware.releases();
      if (mounted) {
        setState(() {
          _releases = r;
          _relError = null;
        });
      }
    } on FirmwareException catch (e) {
      if (mounted) setState(() => _relError = e.message);
    } finally {
      if (mounted) setState(() => _loadingRel = false);
    }
  }

  /// Neueste Version für normale Nutzer: veröffentlicht und stabil.
  FirmwareRelease? get _latest {
    for (final r in _releases) {
      if (r.published && r.channel == 'stable') return r;
    }
    return null;
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<T?> _run<T>(String label, Future<T> Function() f) async {
    setState(() {
      _busy = label;
      _progress = null;
    });
    try {
      return await f();
    } on FirmwareException catch (e) {
      if (mounted) _toast(e.message);
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _busy = null;
          _progress = null;
        });
      }
    }
  }

  Future<bool> _confirm(String title, String text, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
          ],
        ),
      ) ??
      false;

  /// Datei zum Dongle schicken und auf den Neustart warten.
  Future<void> _flash(Uint8List bytes, String label) async {
    final ip = _app.dongleIp;
    final ok = await _run('Übertrage $label …', () async {
      await DongleClient(ip).upload(bytes, _app.otaKey,
          onProgress: (p) => mounted ? setState(() => _progress = p) : null);
      if (mounted) {
        setState(() {
          _busy = 'Dongle startet neu …';
          _progress = null;
        });
      }
      return DongleClient(ip).waitForRestart();
    });
    if (!mounted) return;
    if (ok != null) {
      setState(() {
        _info = ok;
        _infoError = null;
        _infoLoaded = true;
      });
      _toast('Update fertig: Firmware ${ok.firmware}');
    } else if (_busy == null) {
      _loadInfo();
    }
  }

  Future<void> _install(FirmwareRelease r) async {
    final installed = _info?.version;
    final target = r.parsed;
    if (installed != null && target != null && !(target > installed)) {
      final go = await _confirm(
        'Version ${r.version} installieren?',
        'Auf dem Dongle läuft schon ${installed.toString()}. Trotzdem installieren?',
        'Installieren',
      );
      if (!go) return;
    }
    var bytes = _downloaded[r.id];
    if (bytes == null) {
      bytes = await _run('Lade ${r.version} herunter …', () => _app.firmware.download(r));
      if (bytes == null || !mounted) return;
      _downloaded[r.id] = bytes;
    }
    await _flash(bytes, r.version);
  }

  Future<Uint8List?> _pickBin() async {
    final f = await FilePicker.pickFile(dialogTitle: 'firmware.bin wählen');
    if (f == null) return null;
    final bytes = await f.xFile.readAsBytes();
    try {
      checkFirmwareImage(bytes);
      return bytes;
    } on FirmwareException catch (e) {
      _toast(e.message);
      return null;
    }
  }

  Future<void> _flashLocalFile() async {
    final bytes = await _pickBin();
    if (bytes == null || !mounted) return;
    final go = await _confirm('Datei flashen?',
        '${(bytes.length / 1024).round()} KB direkt auf den Dongle unter ${_app.dongleIp} schreiben. '
            'Die Datei wird nicht veröffentlicht.', 'Flashen');
    if (go) await _flash(bytes, 'Datei');
  }

  Future<void> _publish() async {
    final created = await Navigator.of(context).push<FirmwareRelease>(
      MaterialPageRoute(builder: (_) => _PublishScreen(firmware: _app.firmware, pick: _pickBin)),
    );
    if (created != null) {
      _toast('Version ${created.version} ${created.published ? 'veröffentlicht' : 'als Entwurf gespeichert'}.');
      _loadReleases();
    }
  }

  Future<void> _editKey() async {
    final ctrl = TextEditingController(text: _app.otaKey);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update-Schlüssel'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Muss zum Schlüssel auf der Setup-Seite des Dongles passen. '
              'Ab Werk: das WLAN-Passwort des Dongles (dmxdongle).'),
          const SizedBox(height: 12),
          TextField(controller: ctrl, obscureText: true, decoration: const InputDecoration(labelText: 'Schlüssel')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Speichern')),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) setState(() => _app.otaKey = v);
  }

  @override
  Widget build(BuildContext context) {
    return AppListener(
      engine: false,
      builder: (context, app) {
        final s = Theme.of(context).colorScheme;
        final latest = _latest;
        final busy = _busy != null;
        return Scaffold(
          appBar: AppBar(title: const Text('Dongle-Firmware'), actions: [
            IconButton(
              tooltip: 'Aktualisieren',
              onPressed: busy ? null : () => [_loadInfo(), _loadReleases()],
              icon: const Icon(Icons.refresh),
            ),
          ]),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (busy)
                Card(
                  color: s.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_busy!, style: TextStyle(color: s.onSecondaryContainer, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(value: _progress),
                      const SizedBox(height: 8),
                      Text('App offen lassen und den Dongle nicht ausstecken.',
                          style: TextStyle(color: s.onSecondaryContainer)),
                    ]),
                  ),
                ),
              // ---------- Dongle ----------
              Card(
                child: Column(children: [
                  ListTile(
                    leading: const Icon(Icons.memory_outlined),
                    title: Text(_info?.name ?? 'Dongle'),
                    subtitle: Text(_loadingInfo
                        ? 'Frage ${app.dongleIp} …'
                        : _infoError ??
                            (_info != null
                                ? 'Firmware ${_info!.firmware} · ${_info!.mode == 'ap' ? 'eigenes WLAN' : 'Heim-WLAN'} · ${_info!.ip}'
                                : _infoLoaded
                                    ? 'Alte Firmware ohne Update-Funktion. Bitte einmal per USB flashen.'
                                    : app.dongleIp)),
                    trailing: _loadingInfo
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : IconButton(
                            onPressed: busy ? null : _loadInfo, icon: const Icon(Icons.refresh), tooltip: 'Neu prüfen'),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.password_outlined),
                    title: const Text('Update-Schlüssel'),
                    subtitle: const Text('Steht auf der Setup-Seite des Dongles'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: busy ? null : _editKey,
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              // ---------- Update ----------
              if (!app.firmware.available)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.cloud_off_outlined),
                    title: Text('Kein Update-Server'),
                    subtitle: Text('Im Testmodus gibt es keine veröffentlichten Updates.'),
                  ),
                )
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Neueste Version', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      if (_loadingRel)
                        const LinearProgressIndicator()
                      else if (_relError != null)
                        Text(_relError!, style: TextStyle(color: s.error))
                      else if (latest == null)
                        const Text('Noch keine Firmware veröffentlicht.')
                      else ...[
                        Text('${latest.version}  ·  ${(latest.sizeBytes / 1024).round()} KB',
                            style: Theme.of(context).textTheme.headlineSmall),
                        if (latest.notes.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(latest.notes),
                        ],
                        const SizedBox(height: 6),
                        Text(_statusText(latest), style: TextStyle(color: s.onSurfaceVariant)),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: busy || _info == null ? null : () => _install(latest),
                          icon: const Icon(Icons.system_update_alt),
                          label: const Text('Auf Dongle installieren'),
                        ),
                      ],
                    ]),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'So geht es: Das Handy lädt das Update aus dem Internet und schickt es dann '
                'übers WLAN an den Dongle. Im Dongle-WLAN gibt es kein Internet, dafür nutzt die App '
                'kurz die mobilen Daten.',
                style: TextStyle(color: s.onSurfaceVariant),
              ),
              // ---------- Admin ----------
              if (app.isAdmin) ...[
                const SizedBox(height: 24),
                Text('ADMIN',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: s.primary, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                const SizedBox(height: 8),
                Card(
                  child: Column(children: [
                    ListTile(
                      leading: const Icon(Icons.publish_outlined),
                      title: const Text('Neue Version veröffentlichen'),
                      subtitle: const Text('firmware.bin hochladen, Version und Hinweise eintragen'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: busy || !app.firmware.available ? null : _publish,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      leading: const Icon(Icons.usb_outlined),
                      title: const Text('Datei direkt flashen'),
                      subtitle: const Text('Zum Testen, ohne zu veröffentlichen'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: busy ? null : _flashLocalFile,
                    ),
                  ]),
                ),
                if (_releases.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: Column(children: [
                      for (var i = 0; i < _releases.length; i++) ...[
                        if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                        _ReleaseTile(
                          release: _releases[i],
                          enabled: !busy,
                          onInstall: _info == null ? null : () => _install(_releases[i]),
                          onPublished: (v) async {
                            await _run('Speichere …', () => app.firmware.setPublished(_releases[i], v));
                            _loadReleases();
                          },
                          onDelete: () async {
                            final r = _releases[i];
                            if (!await _confirm('Version ${r.version} löschen?',
                                'Eintrag und Datei werden vom Server entfernt.', 'Löschen')) {
                              return;
                            }
                            await _run('Lösche …', () => app.firmware.delete(r));
                            _loadReleases();
                          },
                        ),
                      ],
                    ]),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  String _statusText(FirmwareRelease r) {
    final installed = _info?.version;
    final v = r.parsed;
    if (_info == null) return 'Dongle nicht erreichbar – Version unbekannt.';
    if (installed == null || v == null) return 'Installiert: ${_info!.firmware}';
    if (v > installed) return 'Update verfügbar (installiert: $installed).';
    return 'Der Dongle ist aktuell.';
  }
}

class _ReleaseTile extends StatelessWidget {
  const _ReleaseTile({
    required this.release,
    required this.enabled,
    required this.onInstall,
    required this.onPublished,
    required this.onDelete,
  });

  final FirmwareRelease release;
  final bool enabled;
  final VoidCallback? onInstall;
  final ValueChanged<bool> onPublished;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final r = release;
    final d = r.createdAt.toLocal();
    return ListTile(
      title: Text('${r.version}${r.channel == 'beta' ? '  ·  Beta' : ''}'),
      subtitle: Text('${r.published ? 'Veröffentlicht' : 'Entwurf'} · ${(r.sizeBytes / 1024).round()} KB · '
          '${d.day}.${d.month}.${d.year}${r.notes.isEmpty ? '' : '\n${r.notes}'}'),
      isThreeLine: r.notes.isNotEmpty,
      trailing: PopupMenuButton<String>(
        enabled: enabled,
        onSelected: (v) {
          switch (v) {
            case 'install':
              onInstall?.call();
            case 'publish':
              onPublished(!r.published);
            case 'delete':
              onDelete();
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'install', enabled: onInstall != null, child: const Text('Auf Dongle installieren')),
          PopupMenuItem(value: 'publish', child: Text(r.published ? 'Zurückziehen' : 'Veröffentlichen')),
          const PopupMenuItem(value: 'delete', child: Text('Löschen')),
        ],
      ),
    );
  }
}

/// Admin: neue Firmware-Version hochladen.
class _PublishScreen extends StatefulWidget {
  const _PublishScreen({required this.firmware, required this.pick});
  final FirmwareRepository firmware;
  final Future<Uint8List?> Function() pick;

  @override
  State<_PublishScreen> createState() => _PublishScreenState();
}

class _PublishScreenState extends State<_PublishScreen> {
  final _version = TextEditingController();
  final _notes = TextEditingController();
  String _channel = 'stable';
  bool _published = true;
  Uint8List? _bytes;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _version.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final b = await widget.pick();
    if (b != null) setState(() => _bytes = b);
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.firmware.publish(
        bytes: _bytes!,
        version: _version.text.trim(),
        channel: _channel,
        notes: _notes.text,
        published: _published,
      );
      if (mounted) Navigator.pop(context, r);
    } on FirmwareException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final ready = _bytes != null && FwVersion.tryParse(_version.text) != null && !_busy;
    return Scaffold(
      appBar: AppBar(title: const Text('Version veröffentlichen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.attach_file),
            label: Text(_bytes == null ? 'firmware.bin wählen' : 'Datei: ${(_bytes!.length / 1024).round()} KB'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _version,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Version',
              hintText: '1.2.0',
              helperText: 'Muss zu FW_MAJOR/MINOR/PATCH in board_config.h passen',
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'stable', label: Text('Stabil')),
              ButtonSegment(value: 'beta', label: Text('Beta')),
            ],
            selected: {_channel},
            onSelectionChanged: _busy ? null : (v) => setState(() => _channel = v.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notes,
            enabled: !_busy,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Was ist neu?', alignLabelWithHint: true),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Sofort für alle sichtbar'),
            subtitle: const Text('Aus = Entwurf, nur Admins sehen ihn'),
            value: _published,
            onChanged: _busy ? null : (v) => setState(() => _published = v),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: s.error)),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: ready ? _submit : null,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_upload_outlined),
            label: const Text('Hochladen'),
          ),
        ],
      ),
    );
  }
}
