import 'dart:async';

import 'package:flutter/material.dart';

import '../core/artnet/artnet_packet.dart';
import '../models/models.dart';
import 'app_scope.dart';

/// Dongle suchen, Ziel-IP und Universe-Zuordnung einstellen.
class NetworkScreen extends StatefulWidget {
  const NetworkScreen({super.key});

  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen> {
  List<ArtNetNode> _nodes = [];
  bool _searching = false;
  late final TextEditingController _ip;
  Timer? _statsTimer;
  int _lastPackets = 0;
  int _rate = 0;

  @override
  void initState() {
    super.initState();
    final app = AppScope.of(context);
    _ip = TextEditingController(text: app.network.nodeIp ?? '');
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final p = app.engine.transport.packetsSent;
      if (mounted) setState(() => _rate = p - _lastPackets);
      _lastPackets = p;
    });
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _ip.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _searching = true);
    final nodes = await AppScope.of(context).engine.transport.discover();
    if (!mounted) return;
    setState(() {
      _nodes = nodes;
      _searching = false;
    });
  }

  void _apply(NetworkSettings Function(NetworkSettings) change) {
    final app = AppScope.of(context);
    app.updateNetwork(change(app.network));
  }

  void _useNode(ArtNetNode n) {
    _ip.text = n.ip;
    _apply((s) => s
      ..nodeIp = n.ip
      ..net = n.net
      ..subnet = n.subnet
      ..firstUniverse = n.outputUniverses.isEmpty ? 0 : n.outputUniverses.first
      ..universeCount = n.outputUniverses.isEmpty
          ? s.universeCount
          : n.outputUniverses.length);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dongle & Netzwerk')),
      body: AppListener(
      engine: false,
      builder: (context, app) {
        final s = app.network;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: Icon(Icons.circle,
                    size: 14, color: _rate > 0 ? Colors.greenAccent : Colors.grey),
                title: Text(s.nodeIp == null ? 'Ziel: Broadcast' : 'Ziel: ${s.nodeIp}'),
                subtitle: Text('$_rate Art-Net Pakete/s gesendet'
                    '${app.engine.transport.sendErrors > 0 ? ' · ${app.engine.transport.sendErrors} Sendefehler' : ''}'),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Text('Dongles im Netz', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _searching ? null : _search,
                icon: _searching
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.search),
                label: const Text('Suchen'),
              ),
            ]),
            if (_nodes.isEmpty && !_searching)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Handy mit dem WLAN des Dongles („DMX-Dongle-XXXX“) oder demselben '
                  'Heimnetz verbinden, dann „Suchen“.',
                ),
              ),
            for (final n in _nodes)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.router),
                  title: Text(n.shortName.isEmpty ? n.ip : n.shortName),
                  subtitle: Text('${n.ip} · Net ${n.net} Sub ${n.subnet} · '
                      'Universen ${n.outputUniverses.join(', ')}\n${n.report}'),
                  isThreeLine: true,
                  trailing: s.nodeIp == n.ip
                      ? const Icon(Icons.check_circle, color: Colors.greenAccent)
                      : TextButton(onPressed: () => _useNode(n), child: const Text('Nutzen')),
                ),
              ),
            const Divider(height: 32),
            Text('Manuell', style: Theme.of(context).textTheme.titleMedium),
            TextField(
              controller: _ip,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'IP des Dongles (leer = Broadcast)',
                hintText: '192.168.4.1',
              ),
              onSubmitted: (v) =>
                  _apply((s) => s..nodeIp = v.trim().isEmpty ? null : v.trim()),
            ),
            const SizedBox(height: 16),
            _Stepper(
              label: 'Anzahl Universen',
              value: s.universeCount,
              min: 1,
              max: 16,
              onChanged: (v) => _apply((s) => s..universeCount = v),
            ),
            _Stepper(
              label: 'Art-Net Net',
              value: s.net,
              min: 0,
              max: 127,
              onChanged: (v) => _apply((s) => s..net = v),
            ),
            _Stepper(
              label: 'Sub-Net',
              value: s.subnet,
              min: 0,
              max: 15,
              onChanged: (v) => _apply((s) => s..subnet = v),
            ),
            _Stepper(
              label: 'Erstes Universe',
              value: s.firstUniverse,
              min: 0,
              max: 15,
              onChanged: (v) => _apply((s) => s..firstUniverse = v),
            ),
            const SizedBox(height: 8),
            Text(
              'App-Universe 1 → Art-Net Port-Address '
              '${app.engine.portAddressFor(0)}, Universe 2 → ${app.engine.portAddressFor(1)} …',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      },
    ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final String label;
  final int value, min, max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text(label)),
        IconButton(
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove)),
        SizedBox(width: 36, child: Text('$value', textAlign: TextAlign.center)),
        IconButton(
            onPressed: value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add)),
      ]);
}
