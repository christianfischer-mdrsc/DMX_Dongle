import 'package:flutter/material.dart';

import '../services/account_service.dart';
import '../state/app_state.dart';
import 'app_scope.dart';
import 'network_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppListener(
      engine: false,
      builder: (context, app) {
        final s = Theme.of(context).colorScheme;
        final user = app.user;
        void push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

        return Scaffold(
          appBar: AppBar(title: const Text('Einstellungen')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              // Konto-Karte
              Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => push(user == null ? const SignInScreen() : const AccountScreen()),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: s.primaryContainer,
                        child: user == null
                            ? Icon(Icons.person_outline, color: s.onPrimaryContainer)
                            : Text(user.displayName.characters.first.toUpperCase(),
                                style: TextStyle(
                                    color: s.onPrimaryContainer, fontWeight: FontWeight.w700, fontSize: 20)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(user?.displayName ?? 'Nicht angemeldet',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                          Text(user?.email ?? 'Anmelden, um Geräte freizuschalten',
                              style: TextStyle(color: s.onSurfaceVariant)),
                        ]),
                      ),
                      Icon(Icons.chevron_right, color: s.onSurfaceVariant),
                    ]),
                  ),
                ),
              ),
              const _Header('Verbindung'),
              _Group(children: [
                ListTile(
                  leading: const Icon(Icons.router_outlined),
                  title: const Text('Dongle & Netzwerk'),
                  subtitle: Text(app.network.nodeIp == null
                      ? 'Kein Dongle gewählt'
                      : 'Sendet an ${app.network.nodeIp} · ${app.network.universeCount} Universen'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => push(const NetworkScreen()),
                ),
              ]),
              const _Header('Darstellung'),
              _Group(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Erscheinungsbild'),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Tag')),
                          ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Nacht')),
                          ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined), label: Text('Auto')),
                        ],
                        selected: {app.themeMode},
                        onSelectionChanged: (v) => app.setThemeMode(v.first),
                      ),
                    ),
                  ]),
                ),
              ]),
              const _Header('Freischaltungen'),
              _Group(children: [
                for (final p in featurePacks)
                  ListTile(
                    leading: Icon(
                      app.entitlements.contains(p.id) ? Icons.verified_outlined : Icons.lock_outline,
                      color: app.entitlements.contains(p.id) ? s.primary : s.outline,
                    ),
                    title: Text(p.name),
                    subtitle: Text(app.entitlements.contains(p.id) ? 'Freigeschaltet' : 'Gesperrt'),
                  ),
                ListTile(
                  leading: const Icon(Icons.key_outlined),
                  title: const Text('Code einlösen'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => push(const UnlockScreen()),
                ),
              ]),
              const _Header('Show'),
              _Group(children: [
                ListTile(
                  leading: const Icon(Icons.lightbulb_outline),
                  title: const Text('Lampen'),
                  trailing: Text('${app.fixtures.length}'),
                ),
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('Szenen & Abläufe'),
                  trailing: Text('${app.scenes.length} · ${app.chases.length}'),
                ),
              ]),
              const _Header('Über'),
              _Group(children: [
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('DMX Control'),
                  subtitle: Text('Version 0.2.1 · Art-Net 4'),
                ),
                if (app.account.isDemo)
                  ListTile(
                    leading: Icon(Icons.science_outlined, color: s.tertiary),
                    title: const Text('Konto im Testmodus'),
                    subtitle: const Text('Konten und Codes werden nur auf diesem Gerät gespeichert. '
                        'Die Server-Anbindung folgt.'),
                  ),
              ]),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
        child: Text(text.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                )),
      );
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            children[i],
          ],
        ]),
      );
}

// ---------------- Anmelden / Registrieren ----------------

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _register = false;
  bool _busy = false;
  bool _showPw = false;
  String? _error;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pw = TextEditingController();

  Future<void> _submit() async {
    final app = AppScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        await app.register(_name.text, _email.text, _pw.text);
      } else {
        await app.signIn(_email.text, _pw.text);
      }
      if (mounted) Navigator.pop(context);
    } on AccountException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(_register ? 'Konto erstellen' : 'Anmelden')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            'Mit einem Konto kannst du zusätzliche Geräte freischalten. '
            'Deine Freischaltungen hängen am Konto, nicht am Handy.',
            style: TextStyle(color: s.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          if (_register) ...[
            TextField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Name', prefixIcon: Icon(Icons.person_outline)),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'E-Mail', prefixIcon: Icon(Icons.mail_outline)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pw,
            obscureText: !_showPw,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Passwort',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_showPw ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _showPw = !_showPw),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: s.error)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text(_register ? 'Konto erstellen' : 'Anmelden'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() {
              _register = !_register;
              _error = null;
            }),
            child: Text(_register ? 'Schon ein Konto? Anmelden' : 'Neu hier? Konto erstellen'),
          ),
        ],
      ),
    );
  }
}

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppListener(
      engine: false,
      builder: (context, app) {
        final u = app.user;
        return Scaffold(
          appBar: AppBar(title: const Text('Konto')),
          body: u == null
              ? const SizedBox.shrink()
              : ListView(padding: const EdgeInsets.all(16), children: [
                  _Group(children: [
                    ListTile(leading: const Icon(Icons.person_outline), title: const Text('Name'), subtitle: Text(u.displayName)),
                    ListTile(leading: const Icon(Icons.mail_outline), title: const Text('E-Mail'), subtitle: Text(u.email)),
                  ]),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.logout),
                    label: const Text('Abmelden'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () async {
                      await app.signOut();
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                ]),
        );
      },
    );
  }
}

// ---------------- Freischalten ----------------

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  List<FeaturePack>? _done;

  Future<void> _redeem(AppState app) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final packs = await app.redeemCode(_code.text);
      setState(() => _done = packs);
    } on AccountException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppListener(
      engine: false,
      builder: (context, app) {
        final s = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(title: const Text('Geräte freischalten')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              for (final p in featurePacks)
                Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    leading: Icon(
                      app.entitlements.contains(p.id) ? Icons.verified : Icons.lock_outline,
                      color: app.entitlements.contains(p.id) ? s.primary : s.outline,
                    ),
                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(p.description),
                  ),
                ),
              const SizedBox(height: 24),
              if (app.user == null) ...[
                Text('Zum Freischalten brauchst du ein Konto. So bleiben deine Geräte auch '
                    'nach einem Handywechsel freigeschaltet.',
                    style: TextStyle(color: s.onSurfaceVariant)),
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const SignInScreen())),
                  child: const Text('Anmelden oder Konto erstellen'),
                ),
              ] else if (_done != null) ...[
                Icon(Icons.check_circle, size: 56, color: s.primary),
                const SizedBox(height: 12),
                Text(
                  _done!.isEmpty ? 'Code eingelöst.' : '${_done!.map((p) => p.name).join(', ')} freigeschaltet.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text('Die Geräte erscheinen jetzt beim Hinzufügen einer Lampe.',
                    textAlign: TextAlign.center, style: TextStyle(color: s.onSurfaceVariant)),
              ] else ...[
                TextField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: (_) => _redeem(app),
                  decoration: const InputDecoration(
                    labelText: 'Freischaltcode',
                    hintText: 'XXXX-XXXX-XXXX',
                    prefixIcon: Icon(Icons.key_outlined),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: s.error)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : () => _redeem(app),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : const Text('Einlösen'),
                ),
                if (app.account.isDemo) ...[
                  const SizedBox(height: 12),
                  Text('Testmodus: der Code DMX-PRO-DEMO schaltet die Pro-Geräte frei.',
                      textAlign: TextAlign.center, style: TextStyle(color: s.onSurfaceVariant, fontSize: 13)),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}
