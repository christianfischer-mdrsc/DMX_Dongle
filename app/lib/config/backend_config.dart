/// Verbindung zum Konto-Server (Supabase).
///
/// URL und „Publishable key“ (früher „anon key“) stehen im Supabase-Dashboard
/// unter Project Settings → API Keys. Dieser Schlüssel ist dafür gemacht, in
/// Apps zu stehen: Was er darf, regeln die Rechte in der Datenbank.
/// NIEMALS den „secret“ bzw. „service_role“-Schlüssel hier eintragen.
///
/// Projekt: „DMX Control“ (Frankfurt). Leere Werte = Testmodus (lokales Demo-Konto).
/// Überschreiben beim Bauen:
///   flutter build apk --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...
class BackendConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL',
      defaultValue: 'https://dinpegcabjxywluvtizt.supabase.co');
  static const supabaseKey = String.fromEnvironment('SUPABASE_KEY',
      defaultValue: 'sb_publishable_XpXGZJRYaUWcfihBWmtUJg_k1W7aA7G');

  /// true, sobald eigener Mailversand (SMTP) eingerichtet ist und die
  /// E-Mail-Vorlagen {{ .Token }} enthalten: Dann Bestätigung und
  /// Passwort-Reset per 6-stelligem Code. false = Bestätigung per Link.
  static const emailCodes = bool.fromEnvironment('EMAIL_CODES', defaultValue: false);

  static bool get enabled => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
