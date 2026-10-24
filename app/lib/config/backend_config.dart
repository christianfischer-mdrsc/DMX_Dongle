/// Verbindung zum Konto-Server (Supabase).
///
/// URL und „Publishable key“ (früher „anon key“) stehen im Supabase-Dashboard
/// unter Project Settings → API Keys. Dieser Schlüssel ist dafür gemacht, in
/// Apps zu stehen: Was er darf, regeln die Rechte in der Datenbank.
/// NIEMALS den „secret“ bzw. „service_role“-Schlüssel hier eintragen.
///
/// Sind beide Werte leer, läuft die App im Testmodus (lokales Demo-Konto).
/// Überschreiben beim Bauen:
///   flutter build apk --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...
class BackendConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const supabaseKey = String.fromEnvironment('SUPABASE_KEY', defaultValue: '');

  static bool get enabled => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
