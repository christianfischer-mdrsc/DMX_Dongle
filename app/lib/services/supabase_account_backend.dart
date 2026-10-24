import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/backend_config.dart';
import 'account_service.dart';
import 'admin_api.dart';

/// Echter Konto-Server über Supabase.
///
/// Datenbank-Gegenstück: supabase/migrations/*_licensing.sql
///   * Tabelle `entitlements` (nur eigene Zeilen lesbar)
///   * Funktion `redeem_code(p_code)` prüft und verbucht Codes
///   * Funktion `delete_my_account()`
///
/// E-Mail-Bestätigung und Passwort-Reset laufen über 6-stellige Codes aus
/// der E-Mail (keine Links), damit alles in der App bleibt.
class SupabaseAccountBackend implements AccountBackend {
  SupabaseAccountBackend(this._sb);
  final SupabaseClient _sb;

  GoTrueClient get _auth => _sb.auth;

  @override
  bool get isDemo => false;

  @override
  bool get supportsPasswordReset => BackendConfig.emailCodes;

  @override
  bool get usesEmailCodes => BackendConfig.emailCodes;

  // ---------- Hilfen ----------

  static String _norm(String email) => email.trim().toLowerCase();

  static void _validateEmail(String email) {
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim())) {
      throw const AccountException('Bitte eine gültige E-Mail-Adresse eingeben.');
    }
  }

  static void _validatePassword(String pw) {
    if (pw.length < 8) {
      throw const AccountException('Das Passwort braucht mindestens 8 Zeichen.');
    }
  }

  static UserAccount _toAccount(User u) {
    final email = u.email ?? '';
    final name = (u.userMetadata?['display_name'] as String?)?.trim();
    return UserAccount(
      id: u.id,
      email: email,
      displayName: (name == null || name.isEmpty) ? email.split('@').first : name,
    );
  }

  /// Übersetzt Server-Fehler in verständliche deutsche Meldungen.
  static Never _fail(Object e) {
    if (e is AccountException) throw e;
    if (e is AuthException) {
      final code = e.code ?? '';
      final msg = e.message.toLowerCase();
      if (e is AuthRetryableFetchException || e.statusCode == null && msg.contains('socket')) {
        throw const AccountException(networkErrorMessage, AccountError.network);
      }
      if (code == 'invalid_credentials' || msg.contains('invalid login credentials')) {
        throw const AccountException('E-Mail oder Passwort stimmt nicht.', AccountError.invalidCredentials);
      }
      if (code == 'email_not_confirmed' || msg.contains('email not confirmed')) {
        throw const AccountException(
            'Bitte bestätige zuerst deine E-Mail-Adresse.', AccountError.emailNotConfirmed);
      }
      if (code == 'user_already_exists' || code == 'email_exists' || msg.contains('already registered')) {
        throw const AccountException(
            'Zu dieser E-Mail gibt es schon ein Konto. Bitte anmelden.', AccountError.alreadyRegistered);
      }
      if (code == 'weak_password') {
        throw const AccountException(
            'Das Passwort ist zu schwach. Bitte länger wählen und Zahlen oder Zeichen mischen.');
      }
      if (code == 'otp_expired' || msg.contains('token has expired') || msg.contains('invalid')) {
        throw const AccountException(
            'Der Code ist falsch oder abgelaufen. Lass dir einen neuen schicken.');
      }
      if (code.startsWith('over_') || e.statusCode == '429') {
        throw const AccountException(
            'Zu viele Versuche in kurzer Zeit. Bitte ein paar Minuten warten.');
      }
      if (code == 'same_password') {
        throw const AccountException('Das neue Passwort muss sich vom alten unterscheiden.');
      }
      if (code == 'signup_disabled') {
        throw const AccountException('Registrierung ist gerade abgeschaltet.');
      }
      throw AccountException('Anmeldung fehlgeschlagen: ${e.message}');
    }
    if (e is PostgrestException) {
      if (e.code == '42501') throw const AccountException('Dafür fehlen dir die Rechte.');
      // Eigene Meldungen aus den Datenbank-Funktionen sind schon deutsch
      if (e.code == 'P0001') throw AccountException(e.message);
      throw AccountException('Serverfehler: ${e.message}');
    }
    // SocketException, ClientException, Timeouts …
    throw const AccountException(networkErrorMessage, AccountError.network);
  }

  Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f().timeout(const Duration(seconds: 15));
    } catch (e) {
      _fail(e);
    }
  }

  @override
  late final AdminApi admin = AdminApi(_sb);

  @override
  Future<bool> checkIsAdmin() => _guard(() async => (await _sb.rpc('is_admin')) == true);

  @override
  Future<Map<String, dynamic>> fetchAppSettings() => _guard(() async {
        final rows = await _sb.from('app_settings').select('key, value');
        return {for (final r in rows) r['key'] as String: r['value']};
      });

  // ---------- Sitzung ----------

  @override
  Future<UserAccount?> restoreSession() async {
    final u = _auth.currentUser;
    return u == null ? null : _toAccount(u);
  }

  @override
  Future<UserAccount> signIn(String email, String password) => _guard(() async {
        _validateEmail(email);
        final r = await _auth.signInWithPassword(email: _norm(email), password: password);
        final u = r.user;
        if (u == null) throw const AccountException('Anmeldung fehlgeschlagen.');
        return _toAccount(u);
      });

  @override
  Future<UserAccount?> register(String name, String email, String password) => _guard(() async {
        _validateEmail(email);
        _validatePassword(password);
        final r = await _auth.signUp(
          email: _norm(email),
          password: password,
          data: {if (name.trim().isNotEmpty) 'display_name': name.trim()},
        );
        final u = r.user;
        // Supabase verrät aus Datenschutzgründen nicht, ob es die E-Mail schon
        // gibt: dann kommt ein Nutzer ohne Identitäten zurück.
        if (u != null && (u.identities?.isEmpty ?? false)) {
          throw const AccountException(
              'Zu dieser E-Mail gibt es schon ein Konto. Bitte anmelden.', AccountError.alreadyRegistered);
        }
        if (r.session == null) return null; // E-Mail-Bestätigung nötig
        return u == null ? null : _toAccount(u);
      });

  @override
  Future<UserAccount> verifyEmail(String email, String code) => _guard(() async {
        final r = await _auth.verifyOTP(type: OtpType.email, email: _norm(email), token: code.trim());
        final u = r.user;
        if (u == null) throw const AccountException('Bestätigung fehlgeschlagen.');
        return _toAccount(u);
      });

  @override
  Future<void> resendConfirmation(String email) =>
      _guard(() => _auth.resend(type: OtpType.signup, email: _norm(email)));

  @override
  Future<void> requestPasswordReset(String email) => _guard(() async {
        _validateEmail(email);
        await _auth.resetPasswordForEmail(_norm(email));
      });

  @override
  Future<UserAccount> resetPassword(String email, String code, String newPassword) =>
      _guard(() async {
        _validatePassword(newPassword);
        final r = await _auth.verifyOTP(type: OtpType.recovery, email: _norm(email), token: code.trim());
        if (r.user == null) throw const AccountException('Der Code ist falsch oder abgelaufen.');
        final u = await _auth.updateUser(UserAttributes(password: newPassword));
        return _toAccount(u.user ?? r.user!);
      });

  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (_) {
      // Offline: lokal trotzdem abmelden
      await _auth.signOut(scope: SignOutScope.local);
    }
  }

  @override
  Future<void> deleteAccount() => _guard(() async {
        await _sb.rpc('delete_my_account');
        try {
          await _auth.signOut(scope: SignOutScope.local);
        } catch (_) {}
      });

  // ---------- Freischaltungen ----------

  @override
  Future<Set<String>> fetchEntitlements(UserAccount user) => _guard(() async {
        final rows = await _sb.from('entitlements').select('pack_id');
        return {for (final r in rows) r['pack_id'] as String};
      });

  @override
  Future<Set<String>> redeemCode(UserAccount user, String code) => _guard(() async {
        final res = await _sb.rpc('redeem_code', params: {'p_code': code});
        final m = (res as Map).cast<String, dynamic>();
        switch (m['status']) {
          case 'ok':
            return {for (final p in (m['added'] as List? ?? const [])) p as String};
          case 'expired':
            throw const AccountException('Dieser Code ist abgelaufen.');
          case 'used_up':
            throw const AccountException('Dieser Code wurde bereits so oft eingelöst wie erlaubt.');
          case 'already_redeemed':
            throw const AccountException('Diesen Code hast du schon eingelöst.');
          case 'already_owned':
            throw const AccountException(
                'Du hast alle Geräte dieses Codes schon freigeschaltet. Der Code wurde nicht verbraucht.');
          case 'too_many_attempts':
            throw const AccountException(
                'Zu viele falsche Codes. Bitte in einer Stunde erneut versuchen.');
          default:
            throw const AccountException('Dieser Code ist ungültig. Bitte Schreibweise prüfen.');
        }
      });
}

/// Für [AdminApi]: Server-Fehler in verständliche Meldungen übersetzen.
Future<T> guardSupabase<T>(Future<T> Function() f) async {
  try {
    return await f().timeout(const Duration(seconds: 20));
  } catch (e) {
    SupabaseAccountBackend._fail(e);
  }
}
