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
                  subtitle: Text('Version 0.3.0 · Art-Net 4'),
                ),
                if (app.account.isDemo)
                  ListTile(
                    leading: Icon(Icons.science_outlined, color: s.tertiary),
                    title: const Text('Konto im Testmodus'),
                    subtitle: const Text('Kein Server eingetragen: Konten und Codes werden nur auf '
                        'diesem Gerät gespeichert.'),
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

enum _AuthStep { signIn, register, verify, forgot, reset }

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  _AuthStep _step = _AuthStep.signIn;
  bool _busy = false;
  bool _showPw = false;
  String? _error;
  String? _info;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pw = TextEditingController();
  final _code = TextEditingController();

  @override
  void dispose() {
    for (final c in [_name, _email, _pw, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  void _go(_AuthStep s, {String? info}) => setState(() {
        _step = s;
        _error = null;
        _info = info;
        _code.clear();
      });

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on AccountException catch (e) {
      if (!mounted) return;
      if (e.kind == AccountError.emailNotConfirmed) {
        _go(_AuthStep.verify, info: 'Deine E-Mail ist noch nicht bestätigt. Gib den Code aus der '
            'Bestätigungs-E-Mail ein oder lass dir einen neuen schicken.');
      } else {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final app = AppScope.of(context);
    final email = _email.text.trim();
    switch (_step) {
      case _AuthStep.signIn:
        await _run(() async {
          await app.signIn(email, _pw.text);
          if (mounted) Navigator.pop(context);
        });
      case _AuthStep.register:
        await _run(() async {
          final done = await app.register(_name.text, email, _pw.text);
          if (!mounted) return;
          if (done) {
            Navigator.pop(context);
          } else {
            _go(_AuthStep.verify, info: 'Wir haben dir einen Bestätigungscode an $email geschickt.');
          }
        });
      case _AuthStep.verify:
        await _run(() async {
          await app.verifyEmail(email, _code.text);
          if (mounted) Navigator.pop(context);
        });
      case _AuthStep.forgot:
        await _run(() async {
          await app.account.requestPasswordReset(email);
          if (mounted) {
            _go(_AuthStep.reset,
                info: 'Falls es ein Konto zu $email gibt, kommt gleich eine E-Mail mit einem Code.');
          }
        });
      case _AuthStep.reset:
        await _run(() async {
          await app.resetPassword(email, _code.text, _pw.text);
          if (mounted) Navigator.pop(context);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final app = AppScope.of(context);
    final (title, button, intro) = switch (_step) {
      _AuthStep.signIn => ('Anmelden', 'Anmelden',
          'Mit einem Konto kannst du zusätzliche Geräte freischalten. Deine Freischaltungen '
              'hängen am Konto, nicht am Handy.'),
      _AuthStep.register => ('Konto erstellen', 'Konto erstellen',
          'Du bekommst danach eine E-Mail mit einem Code, um deine Adresse zu bestätigen.'),
      _AuthStep.verify => ('E-Mail bestätigen', 'Bestätigen', ''),
      _AuthStep.forgot => ('Passwort vergessen', 'Code anfordern',
          'Wir schicken dir einen Code, mit dem du ein neues Passwort setzen kannst.'),
      _AuthStep.reset => ('Neues Passwort', 'Passwort speichern', ''),
    };
    final showName = _step == _AuthStep.register;
    final showEmail = true;
    final emailLocked = _step == _AuthStep.verify || _step == _AuthStep.reset;
    final showCode = _step == _AuthStep.verify || _step == _AuthStep.reset;
    final showPw = _step == _AuthStep.signIn || _step == _AuthStep.register || _step == _AuthStep.reset;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: AutofillGroup(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            if ((_info ?? intro).isNotEmpty) ...[
              Text(_info ?? intro, style: TextStyle(color: s.onSurfaceVariant)),
              const SizedBox(height: 20),
            ],
            if (showName) ...[
              TextField(
                controller: _name,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                decoration: const InputDecoration(labelText: 'Name', prefixIcon: Icon(Icons.person_outline)),
              ),
              const SizedBox(height: 12),
            ],
            if (showEmail) ...[
              TextField(
                controller: _email,
                readOnly: emailLocked,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'E-Mail', prefixIcon: Icon(Icons.mail_outline)),
              ),
              const SizedBox(height: 12),
            ],
            if (showCode) ...[
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                textInputAction: showPw ? TextInputAction.next : TextInputAction.done,
                onSubmitted: showPw ? null : (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Code aus der E-Mail',
                  hintText: '123456',
                  prefixIcon: Icon(Icons.pin_outlined),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (showPw)
              TextField(
                controller: _pw,
                obscureText: !_showPw,
                autofillHints: [
                  _step == _AuthStep.signIn ? AutofillHints.password : AutofillHints.newPassword,
                ],
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: _step == _AuthStep.reset ? 'Neues Passwort' : 'Passwort',
                  helperText: _step == _AuthStep.signIn || app.account.isDemo ? null : 'Mindestens 8 Zeichen',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _showPw ? 'Passwort verbergen' : 'Passwort anzeigen',
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
                  : Text(button),
            ),
            const SizedBox(height: 8),
            ...switch (_step) {
              _AuthStep.signIn => [
                  TextButton(
                      onPressed: () => _go(_AuthStep.register), child: const Text('Neu hier? Konto erstellen')),
                  if (app.account.supportsPasswordReset)
                    TextButton(onPressed: () => _go(_AuthStep.forgot), child: const Text('Passwort vergessen?')),
                ],
              _AuthStep.register => [
                  TextButton(
                      onPressed: () => _go(_AuthStep.signIn), child: const Text('Schon ein Konto? Anmelden')),
                ],
              _AuthStep.verify => [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                              await app.account.resendConfirmation(_email.text.trim());
                              if (mounted) setState(() => _info = 'Neuer Code ist unterwegs.');
                            }),
                    child: const Text('Code erneut senden'),
                  ),
                  TextButton(onPressed: () => _go(_AuthStep.signIn), child: const Text('Zurück zur Anmeldung')),
                ],
              _AuthStep.forgot || _AuthStep.reset => [
                  TextButton(onPressed: () => _go(_AuthStep.signIn), child: const Text('Zurück zur Anmeldung')),
                ],
            },
          ],
        ),
      ),
    );
  }
}

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  Future<void> _confirmDelete(BuildContext context, AppState app) async {
    final s = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Konto löschen?'),
        content: const Text('Dein Konto und alle Freischaltungen werden endgültig gelöscht. '
            'Eingelöste Codes lassen sich danach nicht erneut verwenden. Lampen, Szenen und '
            'Abläufe auf diesem Handy bleiben erhalten.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: s.error, foregroundColor: s.onError),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Endgültig löschen'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await app.deleteAccount();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Konto gelöscht')));
        Navigator.pop(context);
      }
    } on AccountException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppListener(
      engine: false,
      builder: (context, app) {
        final u = app.user;
        final s = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(title: const Text('Konto')),
          body: u == null
              ? const SizedBox.shrink()
              : ListView(padding: const EdgeInsets.all(16), children: [
                  _Group(children: [
                    ListTile(leading: const Icon(Icons.person_outline), title: const Text('Name'), subtitle: Text(u.displayName)),
                    ListTile(leading: const Icon(Icons.mail_outline), title: const Text('E-Mail'), subtitle: Text(u.email)),
                    ListTile(
                      leading: const Icon(Icons.sync),
                      title: const Text('Freischaltungen aktualisieren'),
                      onTap: () async {
                        await app.refreshEntitlements();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(content: Text('Freischaltungen geprüft')));
                        }
                      },
                    ),
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
                  const SizedBox(height: 12),
                  TextButton.icon(
                    icon: Icon(Icons.delete_forever_outlined, color: s.error),
                    label: Text('Konto löschen', style: TextStyle(color: s.error)),
                    onPressed: () => _confirmDelete(context, app),
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
