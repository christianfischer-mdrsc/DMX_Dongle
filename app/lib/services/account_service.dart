import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'admin_api.dart';

/// Angemeldeter Nutzer.
class UserAccount {
  final String id;
  final String email;
  final String displayName;
  const UserAccount({required this.id, required this.email, required this.displayName});

  Map<String, dynamic> toJson() => {'id': id, 'email': email, 'displayName': displayName};
  factory UserAccount.fromJson(Map<String, dynamic> j) => UserAccount(
        id: j['id'] as String,
        email: j['email'] as String,
        displayName: j['displayName'] as String,
      );
}

enum AccountError {
  general,
  network,
  invalidCredentials,
  emailNotConfirmed,
  alreadyRegistered,
  unsupported,
}

class AccountException implements Exception {
  final String message;
  final AccountError kind;
  const AccountException(this.message, [this.kind = AccountError.general]);
  @override
  String toString() => message;
}

const networkErrorMessage =
    'Keine Verbindung zum Server. Ist das Handy mit dem WLAN des Dongles verbunden? '
    'Das hat kein Internet. Zum Anmelden kurz ins Heim-WLAN oder mobile Daten wechseln.';

/// Freischaltbares Paket (z.B. eine Gruppe von Geräteprofilen).
class FeaturePack {
  final String id;
  final String name;
  final String description;
  const FeaturePack(this.id, this.name, this.description);
}

const featurePacks = <FeaturePack>[
  FeaturePack('pack.pro', 'Pro-Geräte',
      'LED-Bars mit Einzelsegmenten und Moving Heads mit 16-Bit-Positionierung.'),
];

/// Schnittstelle zum Konto-Server. Umgesetzt von [SupabaseAccountBackend]
/// (echter Server) und [DemoAccountBackend] (Testmodus, nur lokal).
/// Codes werden beim echten Server NUR dort geprüft – nie in der App.
abstract class AccountBackend {
  bool get isDemo;
  bool get supportsPasswordReset;

  /// true = E-Mail enthält einen Code zum Eintippen, false = nur einen Link.
  bool get usesEmailCodes;

  /// Gespeicherte Anmeldung wiederherstellen (funktioniert auch offline).
  Future<UserAccount?> restoreSession();
  Future<UserAccount> signIn(String email, String password);

  /// Liefert null, wenn erst die E-Mail bestätigt werden muss.
  Future<UserAccount?> register(String name, String email, String password);
  Future<UserAccount> verifyEmail(String email, String code);
  Future<void> resendConfirmation(String email);

  Future<void> requestPasswordReset(String email);
  Future<UserAccount> resetPassword(String email, String code, String newPassword);

  Future<void> signOut();
  Future<void> deleteAccount();

  Future<Set<String>> fetchEntitlements(UserAccount user);

  /// Löst einen Freischaltcode ein. Liefert die neu freigeschalteten Pakete.
  Future<Set<String>> redeemCode(UserAccount user, String code);

  /// Admin-Funktionen (null im Testmodus).
  AdminApi? get admin;
  Future<bool> checkIsAdmin();

  /// Öffentliche Einstellungen vom Server, z. B. der Hinweis an alle.
  Future<Map<String, dynamic>> fetchAppSettings();
}

/// Lokales Demo-Backend: speichert alles auf dem Gerät.
/// Testcode: DMX-PRO-DEMO
class DemoAccountBackend implements AccountBackend {
  static const _kSession = 'account.session';
  static const _kUsers = 'account.users';
  static String _kEnt(String id) => 'account.entitlements.$id';

  static const _demoCodes = {'DMX-PRO-DEMO': {'pack.pro'}};

  @override
  bool get isDemo => true;

  @override
  bool get supportsPasswordReset => false;

  @override
  bool get usesEmailCodes => false;

  @override
  AdminApi? get admin => null;

  @override
  Future<bool> checkIsAdmin() async => false;

  @override
  Future<Map<String, dynamic>> fetchAppSettings() async => const {};

  @override
  Future<UserAccount> verifyEmail(String email, String code) =>
      throw const AccountException('Im Testmodus nicht nötig.', AccountError.unsupported);

  @override
  Future<void> resendConfirmation(String email) async {}

  @override
  Future<void> requestPasswordReset(String email) =>
      throw const AccountException('Im Testmodus nicht verfügbar.', AccountError.unsupported);

  @override
  Future<UserAccount> resetPassword(String email, String code, String newPassword) =>
      throw const AccountException('Im Testmodus nicht verfügbar.', AccountError.unsupported);

  @override
  Future<void> deleteAccount() async {
    final u = await restoreSession();
    if (u == null) return;
    final p = await _p;
    final users = await _users();
    users.remove(u.email);
    await p.setString(_kUsers, jsonEncode(users));
    await p.remove(_kEnt(u.id));
    await p.remove(_kSession);
  }

  Future<SharedPreferences> get _p => SharedPreferences.getInstance();

  Future<Map<String, dynamic>> _users() async {
    final raw = (await _p).getString(_kUsers);
    return raw == null ? {} : jsonDecode(raw) as Map<String, dynamic>;
  }

  @override
  Future<UserAccount?> restoreSession() async {
    final raw = (await _p).getString(_kSession);
    if (raw == null) return null;
    try {
      return UserAccount.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<UserAccount> _startSession(UserAccount u) async {
    await (await _p).setString(_kSession, jsonEncode(u.toJson()));
    return u;
  }

  static String _norm(String email) => email.trim().toLowerCase();

  static void _validate(String email, String password) {
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim())) {
      throw const AccountException('Bitte eine gültige E-Mail-Adresse eingeben.');
    }
    if (password.length < 6) {
      throw const AccountException('Das Passwort braucht mindestens 6 Zeichen.');
    }
  }

  @override
  Future<UserAccount?> register(String name, String email, String password) async {
    _validate(email, password);
    final users = await _users();
    final key = _norm(email);
    if (users.containsKey(key)) {
      throw const AccountException(
          'Zu dieser E-Mail gibt es schon ein Konto. Bitte anmelden.', AccountError.alreadyRegistered);
    }
    final user = UserAccount(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      email: key,
      displayName: name.trim().isEmpty ? key.split('@').first : name.trim(),
    );
    // Demo: Passwort nur als Hash-Ersatz abgelegt. Ein echtes Backend
    // speichert Passwörter ausschließlich serverseitig und gehasht.
    users[key] = {...user.toJson(), 'pw': base64Encode(utf8.encode(password))};
    await (await _p).setString(_kUsers, jsonEncode(users));
    return _startSession(user);
  }

  @override
  Future<UserAccount> signIn(String email, String password) async {
    _validate(email, password);
    final users = await _users();
    final u = users[_norm(email)] as Map<String, dynamic>?;
    if (u == null || u['pw'] != base64Encode(utf8.encode(password))) {
      throw const AccountException('E-Mail oder Passwort stimmt nicht.', AccountError.invalidCredentials);
    }
    return _startSession(UserAccount.fromJson(u));
  }

  @override
  Future<void> signOut() async => (await _p).remove(_kSession);

  @override
  Future<Set<String>> fetchEntitlements(UserAccount user) async =>
      ((await _p).getStringList(_kEnt(user.id)) ?? const []).toSet();

  @override
  Future<Set<String>> redeemCode(UserAccount user, String code) async {
    final packs = _demoCodes[code.trim().toUpperCase()];
    if (packs == null) {
      throw const AccountException('Dieser Code ist ungültig. Bitte Schreibweise prüfen.');
    }
    final current = await fetchEntitlements(user);
    final added = packs.difference(current);
    if (added.isEmpty) {
      throw const AccountException('Dieser Code ist bei deinem Konto bereits eingelöst.');
    }
    await (await _p).setStringList(_kEnt(user.id), {...current, ...packs}.toList());
    return added;
  }
}
