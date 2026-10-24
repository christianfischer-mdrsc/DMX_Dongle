import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_account_backend.dart';

/// Zugriff auf die admin_*-Funktionen der Datenbank
/// (supabase/migrations/*_admin.sql). Jede Funktion prüft dort selbst,
/// ob der Aufrufer Admin ist.
class AdminApi {
  AdminApi(this._sb);
  final SupabaseClient _sb;

  Future<List<Map<String, dynamic>>> _rows(String fn, [Map<String, dynamic>? params]) =>
      guardSupabase(() async {
        final res = await _sb.rpc(fn, params: params);
        return [for (final r in (res as List)) (r as Map).cast<String, dynamic>()];
      });

  Future<void> _call(String fn, Map<String, dynamic> params) =>
      guardSupabase(() async => await _sb.rpc(fn, params: params));

  // ---------- Übersicht ----------

  Future<AdminStats> stats() => guardSupabase(() async {
        final m = (await _sb.rpc('admin_stats') as Map).cast<String, dynamic>();
        return AdminStats.fromJson(m);
      });

  // ---------- Codes ----------

  Future<List<AdminCode>> codes({String? search}) async =>
      (await _rows('admin_list_codes', {'p_search': search, 'p_limit': 300}))
          .map(AdminCode.fromJson)
          .toList();

  Future<List<String>> generateCodes({
    required List<String> packIds,
    required int count,
    required int maxRedemptions,
    DateTime? expiresAt,
    String? note,
  }) =>
      guardSupabase(() async {
        final res = await _sb.rpc('admin_generate_codes', params: {
          'p_pack_ids': packIds,
          'p_count': count,
          'p_max_redemptions': maxRedemptions,
          'p_expires_at': expiresAt?.toUtc().toIso8601String(),
          'p_note': (note == null || note.trim().isEmpty) ? null : note.trim(),
        });
        return [for (final c in (res as List)) c as String];
      });

  Future<void> setCodeActive(String codeId, bool active) =>
      _call('admin_set_code_active', {'p_code_id': codeId, 'p_active': active});

  Future<List<CodeRedemption>> codeRedemptions(String codeId) async =>
      (await _rows('admin_code_redemptions', {'p_code_id': codeId}))
          .map(CodeRedemption.fromJson)
          .toList();

  // ---------- Nutzer ----------

  Future<List<AdminUser>> users({String? search}) async =>
      (await _rows('admin_list_users', {'p_search': search, 'p_limit': 300}))
          .map(AdminUser.fromJson)
          .toList();

  Future<void> setEntitlement(String userId, String packId, bool granted) => _call(
      'admin_set_entitlement', {'p_user_id': userId, 'p_pack_id': packId, 'p_granted': granted});

  Future<void> setAdmin(String userId, bool admin) =>
      _call('admin_set_admin', {'p_user_id': userId, 'p_admin': admin});

  // ---------- Pakete & Einstellungen ----------

  Future<List<PackInfo>> packs() => guardSupabase(() async {
        final rows = await _sb.from('packs').select('id, name, description').order('id');
        return [for (final r in rows) PackInfo.fromJson(r)];
      });

  Future<void> updatePack(String id, String name, String description) =>
      _call('admin_update_pack', {'p_id': id, 'p_name': name, 'p_description': description});

  /// value = null löscht die Einstellung.
  Future<void> setSetting(String key, Object? value) =>
      _call('admin_set_setting', {'p_key': key, 'p_value': value});

  // ---------- Protokoll ----------

  Future<List<AdminLogEntry>> log() async =>
      (await _rows('admin_list_log', {'p_limit': 200})).map(AdminLogEntry.fromJson).toList();
}

DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

class AdminStats {
  final int users, usersConfirmed, users7d, codes, codesOpen, redemptions, redemptions7d;
  final List<({String id, String name, int owners})> packs;

  const AdminStats({
    required this.users,
    required this.usersConfirmed,
    required this.users7d,
    required this.codes,
    required this.codesOpen,
    required this.redemptions,
    required this.redemptions7d,
    required this.packs,
  });

  factory AdminStats.fromJson(Map<String, dynamic> j) => AdminStats(
        users: j['users'] as int,
        usersConfirmed: j['users_confirmed'] as int,
        users7d: j['users_7d'] as int,
        codes: j['codes'] as int,
        codesOpen: j['codes_open'] as int,
        redemptions: j['redemptions'] as int,
        redemptions7d: j['redemptions_7d'] as int,
        packs: [
          for (final p in (j['packs'] as List))
            (id: p['id'] as String, name: p['name'] as String, owners: p['owners'] as int),
        ],
      );
}

enum CodeState { open, usedUp, expired, blocked }

class AdminCode {
  final String id, code;
  final List<String> packIds;
  final int maxRedemptions, redemptionCount;
  final DateTime? expiresAt;
  final bool active;
  final String? note;
  final DateTime createdAt;

  const AdminCode({
    required this.id,
    required this.code,
    required this.packIds,
    required this.maxRedemptions,
    required this.redemptionCount,
    required this.expiresAt,
    required this.active,
    required this.note,
    required this.createdAt,
  });

  CodeState get state {
    if (!active) return CodeState.blocked;
    if (expiresAt != null && expiresAt!.isBefore(DateTime.now())) return CodeState.expired;
    if (redemptionCount >= maxRedemptions) return CodeState.usedUp;
    return CodeState.open;
  }

  factory AdminCode.fromJson(Map<String, dynamic> j) => AdminCode(
        id: j['id'] as String,
        code: j['code'] as String,
        packIds: [for (final p in (j['pack_ids'] as List)) p as String],
        maxRedemptions: j['max_redemptions'] as int,
        redemptionCount: j['redemption_count'] as int,
        expiresAt: _date(j['expires_at']),
        active: j['active'] as bool,
        note: j['note'] as String?,
        createdAt: _date(j['created_at'])!,
      );
}

class CodeRedemption {
  final String userId, email;
  final DateTime redeemedAt;
  const CodeRedemption(this.userId, this.email, this.redeemedAt);
  factory CodeRedemption.fromJson(Map<String, dynamic> j) =>
      CodeRedemption(j['user_id'] as String, j['email'] as String, _date(j['redeemed_at'])!);
}

class AdminUser {
  final String id, email, displayName;
  final DateTime createdAt;
  final DateTime? lastSignInAt;
  final bool confirmed, isAdmin;
  final List<String> packs;

  const AdminUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.createdAt,
    required this.lastSignInAt,
    required this.confirmed,
    required this.isAdmin,
    required this.packs,
  });

  factory AdminUser.fromJson(Map<String, dynamic> j) => AdminUser(
        id: j['id'] as String,
        email: j['email'] as String,
        displayName: j['display_name'] as String? ?? '',
        createdAt: _date(j['created_at'])!,
        lastSignInAt: _date(j['last_sign_in_at']),
        confirmed: j['confirmed'] as bool,
        isAdmin: j['is_admin'] as bool,
        packs: [for (final p in (j['packs'] as List)) p as String],
      );
}

class PackInfo {
  final String id, name, description;
  const PackInfo(this.id, this.name, this.description);
  factory PackInfo.fromJson(Map<String, dynamic> j) =>
      PackInfo(j['id'] as String, j['name'] as String, j['description'] as String? ?? '');
}

class AdminLogEntry {
  final DateTime at;
  final String? adminEmail;
  final String action;
  final Map<String, dynamic> detail;
  const AdminLogEntry(this.at, this.adminEmail, this.action, this.detail);
  factory AdminLogEntry.fromJson(Map<String, dynamic> j) => AdminLogEntry(
        _date(j['at'])!,
        j['admin_email'] as String?,
        j['action'] as String,
        (j['detail'] as Map).cast<String, dynamic>(),
      );
}
