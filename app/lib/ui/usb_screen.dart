import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/usb_link.dart';
import '../state/app_state.dart';
import 'app_scope.dart';

/// Dongle per USB-C: verbinden und einrichten (Name, Ausgänge, WLAN, Passwörter).
/// DMX läuft dann über das Kabel; das WLAN des Handys bleibt fürs Internet frei.
class UsbScreen extends StatefulWidget {
  const UsbScreen({super.key});

  @override
  State<UsbScreen> createState() => _UsbScreenState();
}

class _UsbScreenState extends State<UsbScreen> {
  Map<String, dynamic>? _info;
  Map<String, dynamic>? _cfg;
  String? _error;
  bool _loading = false;
  bool _saving = false;

  final _name = TextEditingController();
  final _ssid = TextEditingController();
  final _pass = TextEditingController();
  final _apSsid = TextEditingController();
  final _apPass = TextEditingController();
  final _otaKey = TextEditingController();
  String _wifi = 'ap';
  final _en = [true, true];
  final _u = [0, 1];
  int _net = 0, _sub = 0;
  bool _showPass = false;

  AppState get _app => AppScope.of(context);
  UsbLink get _usb => _app.usb!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_app.usb == null) return;
      _usb.addListener(_onUsb);
      _usb.refresh();
      if (_usb.isOpen) _load();
    });
  }

  bool _wasOpen = false;

  void _onUsb() {
    if (!mounted) return;
    final open = _usb.isOpen;
    if (open && !_wasOpen) _load();
    if (!open) {
      _info = null;
      _cfg = null;
    }
    _wasOpen = open;
    setState(() {});
  }

  @override
  void dispose() {
    _app.usb?.removeListener(_onUsb);
    for (final c in [_name, _ssid, _pass, _apSsid, _apPass, _otaKey]) {
      c.dispose();
    }
    super.dispose();
  }

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await _usb.getInfo();
      final cfg = await _usb.getConfig();
      if (!mounted) return;
      setState(() {
        _info = info;
        _cfg = cfg;
        _name.text = cfg['name'] as String? ?? '';
        _ssid.text = cfg['ssid'] as String? ?? '';
        _apSsid.text = cfg['apSsid'] as String? ?? '';
        _pass.clear();
        _apPass.clear();
        _otaKey.clear();
        _wifi = cfg['wifi'] as String? ?? 'ap';
        _en[0] = cfg['en0'] as bool? ?? true;
        _en[1] = cfg['en1'] as bool? ?? true;
        _u[0] = (cfg['u0'] as num?)?.toInt() ?? 0;
        _u[1] = (cfg['u1'] as num?)?.toInt() ?? 1;
        _net = (cfg['net'] as num?)?.toInt() ?? 0;
        _sub = (cfg['sub'] as num?)?.toInt() ?? 0;
      });
    } on UsbException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _connect(UsbDeviceInfo d) async {
    try {
      await _usb.open(d);
    } catch (e) {
      if (mounted) _toast(_usb.error ?? '$e');
    }
  }

  int _pa(int port) => ((_net & 0x7F) << 8) | ((_sub & 0x0F) << 4) | (_u[port] & 0x0F);

  /// Nur Felder, die sich gegenüber dem Dongle geändert haben.
  Map<String, dynamic> _changes() {
    final c = _cfg ?? const {};
    final m = <String, dynamic>{};
    void put(String k, Object v) {
      if (c[k] != v) m[k] = v;
    }

    put('name', _name.text.trim());
    put('wifi', _wifi);
    put('ssid', _ssid.text.trim());
    put('apSsid', _apSsid.text.trim());
    put('net', _net);
    put('sub', _sub);
    put('u0', _u[0]);
    put('u1', _u[1]);
    put('en0', _en[0]);
    put('en1', _en[1]);
    if (_pass.text.isNotEmpty) m['pass'] = _pass.text;
    if (_apPass.text.isNotEmpty) m['apPass'] = _apPass.text;
    if (_otaKey.text.isNotEmpty) m['otaKey'] = _otaKey.text;
    return m;
  }

  String? _validate() {
    final name = _name.text.trim();
    if (name.isEmpty || name.length > 17) return 'Name: 1 bis 17 Zeichen';
    if (_wifi == 'sta' && _ssid.text.trim().isEmpty) return 'Für das Heimnetz eine SSID eingeben';
    if (_pass.text.isNotEmpty && (_pass.text.length < 8 || _pass.text.length > 63)) {
      return 'WLAN-Passwort: 8 bis 63 Zeichen';
    }
    if (_apPass.text.isNotEmpty && (_apPass.text.length < 8 || _apPass.text.length > 63)) {
      return 'Passwort des Dongle-WLANs: 8 bis 63 Zeichen';
    }
    if (_apSsid.text.trim().length > 31) return 'Name des Dongle-WLANs: max. 31 Zeichen';
    if (_otaKey.text.isNotEmpty && _otaKey.text.length < 8) return 'Update-Schlüssel: mind. 8 Zeichen';
    return null;
  }

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) return _toast(problem);
    final changes = _changes();
    if (changes.isEmpty) return _toast('Nichts geändert.');
    if (_wifi == 'off' && (_cfg?['wifi'] != 'off')) {
      final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('WLAN am Dongle ausschalten?'),
              content: const Text('Danach ist der Dongle nur noch per USB erreichbar – auch die Handy-App ohne Kabel '
                  'und der PC-Simulator per WLAN finden ihn nicht mehr.\n\n'
                  'Wieder einschalten: hier per USB, oder am Dongle die BOOT-Taste 3 s halten '
                  '(dann eigenes WLAN mit Passwort dmxdongle).'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ausschalten')),
              ],
            ),
          ) ??
          false;
      if (!ok) return;
    }
    setState(() => _saving = true);
    try {
      final r = await _usb.setConfig(changes);
      if (r['ok'] != true) {
        _toast(r['error'] as String? ?? 'Speichern fehlgeschlagen');
        return;
      }
      _toast('Gespeichert – Dongle startet neu');
      await Future.delayed(const Duration(seconds: 4));
      if (mounted && _usb.isOpen) await _load();
    } on UsbException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _scan() async {
    _toast('Suche WLANs … (dauert ein paar Sekunden)');
    try {
      final list = await _usb.scanWifi();
      if (!mounted) return;
      list.sort((a, b) => ((b['rssi'] as num?) ?? -100).compareTo((a['rssi'] as num?) ?? -100));
      final picked = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: list.isEmpty
              ? const Padding(padding: EdgeInsets.all(24), child: Text('Keine WLANs gefunden.'))
              : ListView(shrinkWrap: true, children: [
                  for (final n in list)
                    ListTile(
                      leading: Icon(_signal((n['rssi'] as num?)?.toInt() ?? -100)),
                      title: Text(n['ssid'] as String? ?? ''),
                      subtitle: Text('${n['rssi']} dBm${n['secure'] == true ? ' · verschlüsselt' : ' · offen'}'),
                      onTap: () => Navigator.pop(ctx, n['ssid'] as String?),
                    ),
                ]),
        ),
      );
      if (picked != null) setState(() => _ssid.text = picked);
    } on UsbException catch (e) {
      _toast(e.message);
    }
  }

  static IconData _signal(int rssi) => rssi > -60
      ? Icons.network_wifi
      : rssi > -75
          ? Icons.network_wifi_2_bar
          : Icons.network_wifi_1_bar;

  /// App-Universen an die Ausgänge des Dongles anpassen.
  void _matchApp() {
    final ports = [for (var p = 0; p < 2; p++) if (_en[p]) _u[p]];
    if (ports.isEmpty) return;
    final lo = ports.reduce((a, b) => a < b ? a : b), hi = ports.reduce((a, b) => a > b ? a : b);
    final n = _app.network;
    _app.updateNetwork(NetworkSettings(
      nodeIp: n.nodeIp,
      universeCount: hi - lo + 1,
      net: _net,
      subnet: _sub,
      firstUniverse: lo,
    ));
    setState(() {});
    _toast('App sendet jetzt Universe ${_pa(0) - _u[0] + lo + 1} bis ${_pa(0) - _u[0] + hi + 1}.');
  }

  @override
  Widget build(BuildContext context) {
    final usb = _app.usb;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dongle über USB'),
        actions: [
          if (usb != null && usb.isOpen)
            IconButton(icon: const Icon(Icons.refresh), tooltip: 'Neu laden', onPressed: _loading ? null : _load),
        ],
      ),
      body: usb == null || !usb.supported ? _unsupported() : _body(usb),
    );
  }

  Widget _unsupported() => const Padding(
        padding: EdgeInsets.all(24),
        child: Text('Die USB-Verbindung gibt es nur unter Android. iPhones erlauben keinen Zugriff auf '
            'USB-Seriell-Chips – dort bitte das WLAN des Dongles nutzen.'),
      );

  Widget _body(UsbLink usb) {
    final t = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _connectionCard(usb, t),
        if (usb.isOpen && _loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        if (usb.isOpen && _error != null)
          Card(
            color: t.colorScheme.errorContainer,
            child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
          ),
        if (usb.isOpen && _cfg != null) ...[
          _statusCard(t),
          _universeHint(t),
          _section(t, 'Name'),
          TextField(
            controller: _name,
            maxLength: 17,
            decoration: const InputDecoration(labelText: 'Name des Dongles', border: OutlineInputBorder()),
          ),
          _section(t, 'DMX-Ausgänge'),
          _portTile(0),
          _portTile(1),
          ExpansionTile(
            title: const Text('Art-Net Net / Sub-Net'),
            subtitle: Text('Net $_net · Sub-Net $_sub (nur für große Anlagen nötig)'),
            tilePadding: EdgeInsets.zero,
            children: [
              Row(children: [
                Expanded(child: _numberField('Net (0–127)', _net, 127, (v) => setState(() => _net = v))),
                const SizedBox(width: 12),
                Expanded(child: _numberField('Sub-Net (0–15)', _sub, 15, (v) => setState(() => _sub = v))),
              ]),
              const SizedBox(height: 8),
            ],
          ),
          _section(t, 'WLAN des Dongles'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'off', label: Text('Aus'), icon: Icon(Icons.usb)),
              ButtonSegment(value: 'ap', label: Text('Eigenes'), icon: Icon(Icons.wifi_tethering)),
              ButtonSegment(value: 'sta', label: Text('Heimnetz'), icon: Icon(Icons.wifi)),
            ],
            selected: {_wifi},
            onSelectionChanged: (s) => setState(() => _wifi = s.first),
          ),
          const SizedBox(height: 12),
          ..._wifiFields(t),
          _section(t, 'Firmware-Update über WLAN'),
          TextField(
            controller: _otaKey,
            obscureText: !_showPass,
            decoration: const InputDecoration(
              labelText: 'Update-Schlüssel',
              helperText: 'Leer = unverändert, mind. 8 Zeichen',
              border: OutlineInputBorder(),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Passwörter anzeigen'),
            value: _showPass,
            onChanged: (v) => setState(() => _showPass = v),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: const Text('Speichern & Neustart'),
          ),
        ],
      ],
    );
  }

  Widget _section(ThemeData t, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
        child: Text(text, style: t.textTheme.titleSmall?.copyWith(color: t.colorScheme.primary)),
      );

  Widget _connectionCard(UsbLink usb, ThemeData t) {
    if (usb.isOpen) {
      final d = usb.device!;
      return Card(
        child: ListTile(
          leading: Icon(Icons.usb, color: t.colorScheme.primary),
          title: Text('Verbunden: ${d.name}'),
          subtitle: Text('${usb.hello ?? d.chip}\nDMX läuft über USB – das WLAN des Handys bleibt fürs Internet frei.'),
          isThreeLine: true,
          trailing: TextButton(onPressed: usb.close, child: const Text('Trennen')),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.usb_off),
            const SizedBox(width: 12),
            Expanded(child: Text(usb.devices.isEmpty ? 'Kein Dongle per USB erkannt' : 'Dongle gefunden', style: t.textTheme.titleMedium)),
          ]),
          const SizedBox(height: 8),
          if (usb.devices.isEmpty)
            const Text('Dongle mit einem USB-C-Kabel ans Handy stecken. Das Handy versorgt ihn dabei auch mit Strom. '
                'Android fragt beim ersten Mal, ob die App auf das Gerät zugreifen darf.'),
          for (final d in usb.devices)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(d.name),
              subtitle: Text(d.chip),
              trailing: FilledButton(
                onPressed: usb.busy ? null : () => _connect(d),
                child: const Text('Verbinden'),
              ),
            ),
          if (usb.error != null) Text(usb.error!, style: TextStyle(color: t.colorScheme.error)),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(onPressed: usb.refresh, icon: const Icon(Icons.refresh), label: const Text('Erneut suchen')),
          ),
        ]),
      ),
    );
  }

  Widget _statusCard(ThemeData t) {
    final i = _info ?? const {};
    final wifi = switch (i['wifi']) {
      'off' => 'aus (nur USB)',
      'ap' => 'eigenes WLAN „${i['network']}“, ${i['clients']} verbunden',
      _ => i['connected'] == true ? 'verbunden mit „${i['network']}“ (${i['rssi']} dBm)' : 'nicht verbunden',
    };
    final ports = (i['ports'] as List?) ?? const [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${i['name']} · Firmware ${i['fw']}', style: t.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text('WLAN: $wifi'),
          if (i['wifi'] != 'off') Text('IP: ${i['ip']}'),
          for (final p in ports)
            Text('Ausgang ${p['port']}: ${p['on'] == true ? 'Universe ${p['universe']}${p['active'] == true ? ' · empfängt Daten' : ''}' : 'aus'}'),
          Text('Laufzeit: ${Duration(seconds: (i['uptime'] as num?)?.toInt() ?? 0).toString().split('.').first}'),
        ]),
      ),
    );
  }

  /// Warnung, wenn die App andere Universen sendet als der Dongle ausgibt.
  Widget _universeHint(ThemeData t) {
    final app = _app;
    final sent = {for (var u = 0; u < app.network.universeCount; u++) app.engine.portAddressFor(u)};
    final missing = [for (var p = 0; p < 2; p++) if (_en[p] && !sent.contains(_pa(p))) p];
    if (missing.isEmpty) return const SizedBox.shrink();
    final names = missing.map((p) => '${p == 0 ? 'A' : 'B'} (Universe ${_pa(p) + 1})').join(' und ');
    return Card(
      color: t.colorScheme.tertiaryContainer,
      child: ListTile(
        leading: const Icon(Icons.info_outline),
        title: Text('Ausgang $names bekommt von der App keine Daten.'),
        subtitle: Text('Die App sendet Universe ${sent.map((pa) => pa + 1).join(', ')}.'),
        trailing: TextButton(onPressed: _matchApp, child: const Text('App anpassen')),
      ),
    );
  }

  Widget _portTile(int p) {
    final label = p == 0 ? 'A' : 'B';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Ausgang $label'),
              Text(_en[p] ? 'gibt Universe ${_pa(p) + 1} aus' : 'aus – kein DMX-Signal',
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          DropdownButton<int>(
            value: _u[p],
            onChanged: _en[p] ? (v) => setState(() => _u[p] = v ?? _u[p]) : null,
            items: [
              for (var u = 0; u < 16; u++)
                DropdownMenuItem(value: u, child: Text('Universe ${((_net & 0x7F) << 8 | (_sub & 0x0F) << 4 | u) + 1}')),
            ],
          ),
          Switch(value: _en[p], onChanged: (v) => setState(() => _en[p] = v)),
        ]),
      ),
    );
  }

  Widget _numberField(String label, int value, int max, ValueChanged<int> onChanged) => TextFormField(
        initialValue: '$value',
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        onChanged: (s) {
          final v = int.tryParse(s);
          if (v != null && v >= 0 && v <= max) onChanged(v);
        },
      );

  List<Widget> _wifiFields(ThemeData t) {
    final c = _cfg ?? const {};
    switch (_wifi) {
      case 'off':
        return [
          const Text('Der Dongle schaltet sein WLAN ganz ab und ist nur noch per USB steuerbar. '
              'Wieder einschalten: hier, oder BOOT-Taste am Dongle 3 s halten.'),
        ];
      case 'ap':
        return [
          TextField(
            controller: _apSsid,
            maxLength: 31,
            decoration: InputDecoration(
              labelText: 'Name des Dongle-WLANs',
              hintText: c['apSsidDefault'] as String?,
              helperText: 'Leer = ${c['apSsidDefault'] ?? 'DMX-Dongle-XXXX'}',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _apPass,
            obscureText: !_showPass,
            decoration: InputDecoration(
              labelText: 'Passwort des Dongle-WLANs',
              helperText: c['apPassDefault'] == true
                  ? 'Zurzeit Standard (dmxdongle). Leer = unverändert, mind. 8 Zeichen'
                  : 'Leer = unverändert, mind. 8 Zeichen',
              border: const OutlineInputBorder(),
            ),
          ),
        ];
      default:
        return [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _ssid,
                decoration: const InputDecoration(labelText: 'WLAN (SSID)', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(onPressed: _scan, icon: const Icon(Icons.wifi_find), tooltip: 'Netze suchen'),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            obscureText: !_showPass,
            decoration: InputDecoration(
              labelText: 'WLAN-Passwort',
              helperText: c['hasPass'] == true ? 'Gespeichert. Leer = unverändert' : 'Leer = offenes WLAN',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          Text('Klappt die Verbindung nicht, macht der Dongle nach 15 s sein eigenes WLAN auf.',
              style: t.textTheme.bodySmall),
        ];
    }
  }
}
