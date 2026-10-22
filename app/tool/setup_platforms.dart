// Einmalig nach `flutter create .` ausführen:
//   dart run tool/setup_platforms.dart
//
// Trägt die nötigen Netzwerk-Berechtigungen ein (Android, iOS, macOS)
// und entfernt den generierten Beispiel-Test.
import 'dart:io';

void main() {
  _android();
  _ios();
  _macos();
  final demoTest = File('test/widget_test.dart');
  if (demoTest.existsSync() && demoTest.readAsStringSync().contains('MyApp')) {
    demoTest.deleteSync();
    print('✓ Beispiel-Test entfernt');
  }
  print('Fertig. Jetzt: flutter run');
}

void _android() {
  final f = File('android/app/src/main/AndroidManifest.xml');
  if (!f.existsSync()) return print('– Android nicht vorhanden');
  var s = f.readAsStringSync();
  const perms = [
    'android.permission.INTERNET',
    'android.permission.ACCESS_NETWORK_STATE',
    'android.permission.ACCESS_WIFI_STATE',
  ];
  final missing = perms.where((p) => !s.contains(p)).toList();
  if (missing.isEmpty) return print('✓ Android-Berechtigungen vorhanden');
  final lines = missing.map((p) => '    <uses-permission android:name="$p"/>\n').join();
  s = s.replaceFirst('    <application', '$lines    <application');
  f.writeAsStringSync(s);
  print('✓ Android-Berechtigungen ergänzt');
}

void _ios() {
  final f = File('ios/Runner/Info.plist');
  if (!f.existsSync()) return;
  var s = f.readAsStringSync();
  if (s.contains('NSLocalNetworkUsageDescription')) return;
  s = s.replaceFirst('<dict>', '''<dict>
	<key>NSLocalNetworkUsageDescription</key>
	<string>Zum Finden und Steuern des DMX-Dongles im lokalen Netzwerk.</string>''');
  f.writeAsStringSync(s);
  print('✓ iOS Local-Network-Hinweis ergänzt');
}

void _macos() {
  for (final name in ['DebugProfile.entitlements', 'Release.entitlements']) {
    final f = File('macos/Runner/$name');
    if (!f.existsSync()) continue;
    var s = f.readAsStringSync();
    if (s.contains('com.apple.security.network.client')) continue;
    s = s.replaceFirst('<dict>', '''<dict>
	<key>com.apple.security.network.client</key>
	<true/>
	<key>com.apple.security.network.server</key>
	<true/>''');
    f.writeAsStringSync(s);
    print('✓ macOS $name ergänzt');
  }
}
