import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_service.dart';

// =====================================================================
// Firmware-Updates für den Dongle
//
//   Admin (App)  ──Datei + Eintrag──▶  Supabase (Bucket `firmware`,
//                                       Tabelle firmware_releases)
//   App          ──lädt herunter───▶  Handy  ──POST /update──▶  Dongle
//
// Datenbank-Gegenstück: supabase/migrations/*_firmware.sql
// Dongle-Gegenstück: firmware/src/main.cpp (handleInfo, handleUpdate…)
// =====================================================================

/// Versionsnummer „1.2.3“ zum Vergleichen.
class FwVersion implements Comparable<FwVersion> {
  final int major, minor, patch;
  const FwVersion(this.major, this.minor, this.patch);

  static final _re = RegExp(r'^(\d+)\.(\d+)\.(\d+)$');

  static FwVersion? tryParse(String? s) {
    final m = _re.firstMatch(s?.trim() ?? '');
    if (m == null) return null;
    return FwVersion(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }

  @override
  int compareTo(FwVersion o) =>
      major != o.major ? major - o.major : minor != o.minor ? minor - o.minor : patch - o.patch;

  bool operator >(FwVersion o) => compareTo(o) > 0;

  @override
  String toString() => '$major.$minor.$patch';
}

class FirmwareRelease {
  final int id;
  final String version;
  final String channel; // stable | beta
  final String notes;
  final String storagePath;
  final int sizeBytes;
  final String md5;
  final bool published;
  final DateTime createdAt;

  const FirmwareRelease({
    required this.id,
    required this.version,
    required this.channel,
    required this.notes,
    required this.storagePath,
    required this.sizeBytes,
    required this.md5,
    required this.published,
    required this.createdAt,
  });

  FwVersion? get parsed => FwVersion.tryParse(version);

  factory FirmwareRelease.fromRow(Map<String, dynamic> r) => FirmwareRelease(
        id: (r['id'] as num).toInt(),
        version: r['version'] as String,
        channel: r['channel'] as String? ?? 'stable',
        notes: r['notes'] as String? ?? '',
        storagePath: r['storage_path'] as String,
        sizeBytes: (r['size_bytes'] as num).toInt(),
        md5: r['md5'] as String,
        published: r['published'] as bool? ?? false,
        createdAt: DateTime.tryParse(r['created_at'] as String? ?? '') ?? DateTime(2000),
      );
}

class FirmwareException implements Exception {
  final String message;
  const FirmwareException(this.message);
  @override
  String toString() => message;
}

String md5Hex(List<int> bytes) => md5.convert(bytes).toString();

/// Prüft, ob die Datei wie ein ESP32-App-Image aussieht (Magic-Byte 0xE9).
void checkFirmwareImage(Uint8List bytes) {
  if (bytes.length < 1024 || bytes[0] != 0xE9) {
    throw const FirmwareException(
        'Das ist keine ESP32-Firmware. Bitte die firmware.bin aus dem Build nehmen '
        '(nicht bootloader.bin oder partitions.bin).');
  }
  if (bytes.length > 1310720) {
    throw const FirmwareException('Die Datei ist größer als die Update-Partition (1,25 MB).');
  }
}

// ---------------------------------------------------------------------
// Netz wählen (Android)
// ---------------------------------------------------------------------

/// Die App ist auf Android ans WLAN gebunden (MainActivity.kt), damit Art-Net
/// im Dongle-WLAN ankommt. Das Dongle-WLAN hat aber kein Internet: Für
/// Downloads die Bindung kurz lösen, dann geht es über mobile Daten.
class NetworkRoute {
  static const _ch = MethodChannel('dmx_control/network');

  static Future<T> withInternet<T>(Future<T> Function() f) async {
    await _call('useInternet');
    try {
      return await f();
    } finally {
      await _call('useWifi');
    }
  }

  static Future<void> _call(String m) async {
    try {
      await _ch.invokeMethod<void>(m);
    } on MissingPluginException {
      // Andere Plattformen: keine Bindung, nichts zu tun
    }
  }
}

// ---------------------------------------------------------------------
// Server: veröffentlichte Versionen
// ---------------------------------------------------------------------

abstract class FirmwareRepository {
  /// false = kein Server (Testmodus): nur lokale Dateien für Admins.
  bool get available;

  /// Veröffentlichte Versionen, neueste zuerst. Admins sehen alle.
  Future<List<FirmwareRelease>> releases();

  Future<Uint8List> download(FirmwareRelease r);

  Future<FirmwareRelease> publish({
    required Uint8List bytes,
    required String version,
    required String channel,
    required String notes,
    required bool published,
  });

  Future<void> setPublished(FirmwareRelease r, bool published);
  Future<void> delete(FirmwareRelease r);
}

class NoFirmwareRepository implements FirmwareRepository {
  @override
  bool get available => false;
  @override
  Future<List<FirmwareRelease>> releases() async => const [];
  @override
  Future<Uint8List> download(FirmwareRelease r) =>
      throw const FirmwareException('Kein Update-Server eingerichtet.');
  @override
  Future<FirmwareRelease> publish({
    required Uint8List bytes,
    required String version,
    required String channel,
    required String notes,
    required bool published,
  }) =>
      throw const FirmwareException('Kein Update-Server eingerichtet.');
  @override
  Future<void> setPublished(FirmwareRelease r, bool published) async {}
  @override
  Future<void> delete(FirmwareRelease r) async {}
}

class SupabaseFirmwareRepository implements FirmwareRepository {
  SupabaseFirmwareRepository(this._sb);
  final SupabaseClient _sb;

  static const _bucket = 'firmware';
  static const _table = 'firmware_releases';

  @override
  bool get available => true;

  Future<T> _guard<T>(Future<T> Function() f) => NetworkRoute.withInternet(() async {
        try {
          return await f().timeout(const Duration(seconds: 60));
        } on FirmwareException {
          rethrow;
        } on PostgrestException catch (e) {
          throw FirmwareException('Serverfehler: ${e.message}');
        } on StorageException catch (e) {
          throw FirmwareException('Speicherfehler: ${e.message}');
        } catch (_) {
          throw const FirmwareException(
              'Keine Verbindung zum Server. Zum Herunterladen braucht das Handy Internet '
              '(Heim-WLAN oder mobile Daten).');
        }
      });

  @override
  Future<List<FirmwareRelease>> releases() => _guard(() async {
        final rows = await _sb.from(_table).select().order('version_code', ascending: false);
        return [for (final r in rows) FirmwareRelease.fromRow(r)];
      });

  @override
  Future<Uint8List> download(FirmwareRelease r) => _guard(() async {
        final url = _sb.storage.from(_bucket).getPublicUrl(r.storagePath);
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
        try {
          final req = await client.getUrl(Uri.parse(url));
          final res = await req.close();
          if (res.statusCode != 200) {
            throw FirmwareException('Download fehlgeschlagen (HTTP ${res.statusCode}).');
          }
          final bytes = BytesBuilder(copy: false);
          await for (final chunk in res) {
            bytes.add(chunk);
          }
          final data = bytes.takeBytes();
          if (data.length != r.sizeBytes || md5Hex(data) != r.md5) {
            throw const FirmwareException('Die heruntergeladene Datei ist beschädigt. Bitte erneut versuchen.');
          }
          return data;
        } finally {
          client.close(force: true);
        }
      });

  @override
  Future<FirmwareRelease> publish({
    required Uint8List bytes,
    required String version,
    required String channel,
    required String notes,
    required bool published,
  }) {
    checkFirmwareImage(bytes);
    if (FwVersion.tryParse(version) == null) {
      throw const FirmwareException('Version bitte im Format 1.2.3 angeben.');
    }
    return _guard(() async {
      final path = '$version/firmware.bin';
      await _sb.storage.from(_bucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(contentType: 'application/octet-stream', upsert: true),
          );
      try {
        final row = await _sb
            .from(_table)
            .insert({
              'version': version,
              'channel': channel,
              'notes': notes.trim(),
              'storage_path': path,
              'size_bytes': bytes.length,
              'md5': md5Hex(bytes),
              'published': published,
            })
            .select()
            .single();
        return FirmwareRelease.fromRow(row);
      } on PostgrestException catch (e) {
        if (e.code == '23505') {
          throw FirmwareException('Version $version gibt es schon. Bitte die Nummer erhöhen.');
        }
        rethrow;
      }
    });
  }

  @override
  Future<void> setPublished(FirmwareRelease r, bool published) =>
      _guard(() => _sb.from(_table).update({'published': published}).eq('id', r.id));

  @override
  Future<void> delete(FirmwareRelease r) => _guard(() async {
        await _sb.from(_table).delete().eq('id', r.id);
        await _sb.storage.from(_bucket).remove([r.storagePath]);
      });
}

/// Passender Server zum Konto-Backend.
FirmwareRepository firmwareRepositoryFor(AccountBackend account) {
  if (account.isDemo) return NoFirmwareRepository();
  try {
    return SupabaseFirmwareRepository(Supabase.instance.client);
  } catch (_) {
    return NoFirmwareRepository();
  }
}

// ---------------------------------------------------------------------
// Dongle: Info und Upload über HTTP
// ---------------------------------------------------------------------

class DongleInfo {
  final String name;
  final String firmware;
  final String mode; // ap | sta
  final String ip;
  final int uptimeSeconds;
  const DongleInfo(this.name, this.firmware, this.mode, this.ip, this.uptimeSeconds);

  FwVersion? get version => FwVersion.tryParse(firmware);
}

class DongleClient {
  DongleClient(this.ip);
  final String ip;

  Uri _uri(String path, [Map<String, String>? q]) =>
      Uri(scheme: 'http', host: ip, port: 80, path: path, queryParameters: q);

  /// null bei alter Firmware ohne /api/info (vor 1.1.0).
  Future<DongleInfo?> info() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final res = await (await client.getUrl(_uri('/api/info'))).close().timeout(const Duration(seconds: 6));
      if (res.statusCode == 404) return null;
      if (res.statusCode != 200) throw FirmwareException('Dongle antwortet mit HTTP ${res.statusCode}.');
      final j = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
      return DongleInfo(
        j['name'] as String? ?? 'DMX-Dongle',
        j['fw'] as String? ?? '?',
        j['mode'] as String? ?? '',
        j['ip'] as String? ?? ip,
        (j['uptime'] as num?)?.toInt() ?? 0,
      );
    } on FirmwareException {
      rethrow;
    } catch (_) {
      throw FirmwareException('Dongle unter $ip nicht erreichbar. Ist das Handy in seinem WLAN?');
    } finally {
      client.close(force: true);
    }
  }

  /// Schickt die Firmware. [onProgress] bekommt 0..1. Der Dongle startet danach neu.
  Future<void> upload(Uint8List bytes, String key, {void Function(double)? onProgress}) async {
    checkFirmwareImage(bytes);
    const boundary = '----dmxdongle-ota-7f3a';
    final head = utf8.encode('--$boundary\r\n'
        'Content-Disposition: form-data; name="f"; filename="firmware.bin"\r\n'
        'Content-Type: application/octet-stream\r\n\r\n');
    final tail = utf8.encode('\r\n--$boundary--\r\n');

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.postUrl(_uri('/update', {'key': key, 'md5': md5Hex(bytes)}));
      req.headers.contentType = ContentType('multipart', 'form-data', parameters: {'boundary': boundary});
      req.contentLength = head.length + bytes.length + tail.length;
      req.add(head);
      const chunk = 8192;
      for (var i = 0; i < bytes.length; i += chunk) {
        req.add(bytes.sublist(i, i + chunk > bytes.length ? bytes.length : i + chunk));
        await req.flush();
        onProgress?.call((i + chunk).clamp(0, bytes.length) / bytes.length);
      }
      req.add(tail);
      final res = await req.close().timeout(const Duration(seconds: 60));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 401) {
        throw const FirmwareException('Update-Schlüssel falsch. Er steht auf der Setup-Seite des Dongles.');
      }
      if (res.statusCode != 200) {
        String msg = body;
        try {
          msg = (jsonDecode(body) as Map)['error'] as String? ?? body;
        } catch (_) {}
        throw FirmwareException('Dongle meldet: $msg');
      }
    } on FirmwareException {
      rethrow;
    } on SocketException catch (e) {
      throw FirmwareException('Verbindung zum Dongle abgebrochen: ${e.message}');
    } on TimeoutException {
      throw const FirmwareException('Der Dongle antwortet nicht mehr. Bitte Status prüfen.');
    } finally {
      client.close(force: true);
    }
  }

  /// Wartet nach dem Neustart, bis der Dongle wieder antwortet.
  Future<DongleInfo?> waitForRestart({Duration timeout = const Duration(seconds: 45)}) async {
    final end = DateTime.now().add(timeout);
    await Future<void>.delayed(const Duration(seconds: 3));
    while (DateTime.now().isBefore(end)) {
      try {
        final i = await info();
        if (i != null) return i;
      } catch (_) {}
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return null;
  }
}
