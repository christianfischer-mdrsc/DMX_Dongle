import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../state/app_state.dart';

String _stamp(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}_${two(d.hour)}${two(d.minute)}';
}

/// Show als Datei teilen (Drive, Mail, Messenger, „In Dateien speichern“ …).
Future<void> exportShowFile(BuildContext context, AppState app) async {
  final json = const JsonEncoder.withIndent('  ').convert(app.exportShow());
  final name = 'DMX-Master-Show_${_stamp(DateTime.now())}.json';
  try {
    await SharePlus.instance.share(ShareParams(
      subject: 'DMX Master Show',
      files: [XFile.fromData(utf8.encode(json), mimeType: 'application/json')],
      fileNameOverrides: [name],
    ));
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Teilen fehlgeschlagen: $e')));
    }
  }
}

/// Sicherung auswählen, Inhalt zeigen, nach Bestätigung laden.
Future<void> importShowFile(BuildContext context, AppState app) async {
  void snack(String t) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  final Map<String, dynamic> data;
  try {
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty) return;
    final bytes = await files.first.readAsBytes();
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic> || decoded['format'] != AppState.backupFormat) {
      return snack('Diese Datei ist keine DMX-Master-Sicherung.');
    }
    data = decoded;
  } catch (e) {
    return snack('Datei konnte nicht gelesen werden.');
  }
  if (!context.mounted) return;

  int n(String k) => (data[k] as List?)?.length ?? 0;
  var withNetwork = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Show laden?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${n('fixtures')} Lampen, ${n('groups')} Gruppen, ${n('scenes')} Szenen, '
              '${n('chases')} Abläufe, ${n('effects')} Effekte, ${n('profiles')} eigene Profile.'),
          const SizedBox(height: 12),
          const Text('Die aktuelle Show auf diesem Handy wird dabei ersetzt. '
              'Sichere sie vorher, wenn du sie behalten willst.'),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: withNetwork,
            title: const Text('Auch Dongle-Einstellungen übernehmen'),
            onChanged: (v) => set(() => withNetwork = v ?? false),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ersetzen und laden')),
        ],
      ),
    ),
  );
  if (ok != true) return;
  try {
    app.importShow(data, includeNetwork: withNetwork);
    snack('Show geladen');
  } on FormatException catch (e) {
    snack(e.message);
  } catch (_) {
    snack('Die Sicherung ist beschädigt und wurde nicht geladen.');
  }
}
