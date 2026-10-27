import 'package:flutter/material.dart';
import 'package:portfolio_jockey/app/passphrase_rules.dart';
import 'package:portfolio_jockey/app/settings_store.dart';
import 'package:portfolio_jockey/app/theme.dart';
import 'package:portfolio_jockey/ui/common.dart';
import 'package:portfolio_jockey/vault/errors.dart';

/// First run: choose where projects are stored and set the passphrase.
/// Creating the vault writes to disk, and this screen is its confirmation.
class FirstRunScreen extends StatefulWidget {
  const FirstRunScreen({super.key});

  @override
  State<FirstRunScreen> createState() => _FirstRunScreenState();
}

class _FirstRunScreenState extends State<FirstRunScreen> {
  final _passphrase = TextEditingController();
  final _confirm = TextEditingController();
  String? _path;
  bool _understood = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _passphrase.addListener(_changed);
    _confirm.addListener(_changed);
  }

  @override
  void dispose() {
    _passphrase.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  String get _storagePath => _path ?? AppScope.read(context).storagePath ?? defaultStoragePath();

  bool get _canCreate =>
      !_busy &&
      passphraseStrength(_passphrase.text) > 0 &&
      _passphrase.text == _confirm.text &&
      _understood;

  Future<void> _chooseFolder() async {
    final picked = await AppScope.read(context).filePicker.pickFolder(initialDirectory: _storagePath);
    if (picked != null && mounted) {
      setState(() => _path = picked);
    }
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final passphrase = _passphrase.text;
    _passphrase.clear();
    _confirm.clear();
    try {
      await AppScope.read(context).createVault(_storagePath, passphrase);
    } on VaultAlreadyExists {
      _fail('That folder already has a Portfolio Jockey vault. Choose another folder, or restart the app to unlock it.');
    } on Exception catch (e) {
      _fail('The vault could not be created: $e');
    }
  }

  void _fail(String message) {
    if (mounted) {
      setState(() {
        _busy = false;
        _error = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strength = passphraseStrength(_passphrase.text);
    final mismatch = _confirm.text.isNotEmpty && _confirm.text != _passphrase.text;
    return LockCard(
      icon: Icons.enhanced_encryption_outlined,
      title: 'Welcome to Portfolio Jockey',
      children: [
        const Muted('Everything stays on this device. Your files are encrypted with a passphrase only you know.', textAlign: TextAlign.center),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FieldLabel('Where should projects be stored?'),
            Row(
              spacing: 8,
              children: [
                Expanded(child: PathBox(_storagePath)),
                OutlinedButton(onPressed: _busy ? null : _chooseFolder, child: const Text('Change…')),
              ],
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FieldLabel('Passphrase'),
            TextField(controller: _passphrase, obscureText: true, enabled: !_busy, key: const Key('passphrase')),
            const SizedBox(height: 8),
            StrengthBar(strength, active: _passphrase.text.isNotEmpty),
            const SizedBox(height: 4),
            Muted(strengthLabel(strength)),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FieldLabel('Confirm passphrase'),
            TextField(
              controller: _confirm,
              obscureText: true,
              enabled: !_busy,
              key: const Key('confirm'),
              decoration: InputDecoration(errorText: mismatch ? "The passphrases don't match." : null),
            ),
          ],
        ),
        const Notice(
          "There is no way to recover a forgotten passphrase. If you lose it, your projects can't be opened by anyone, including you.",
        ),
        CheckboxListTile(
          key: const Key('understood'),
          value: _understood,
          onChanged: _busy ? null : (v) => setState(() => _understood = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text('I understand that a forgotten passphrase means my files are lost.'),
        ),
        if (_error case final error?) Notice(error, danger: true),
        FilledButton(
          onPressed: _canCreate ? _create : null,
          child: _busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Create vault'),
        ),
      ],
    );
  }
}

/// The centred card used by the first-run and unlock screens.
class LockCard extends StatelessWidget {
  const LockCard({required this.icon, required this.title, required this.children, super.key});

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 16,
                children: [
                  Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
                  Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A folder path in the mockups' grey box.
class PathBox extends StatelessWidget {
  const PathBox(this.path, {super.key});

  final String path;

  @override
  Widget build(BuildContext context) {
    final extra = PjColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: extra.surface2, borderRadius: BorderRadius.circular(10), border: Border.all(color: extra.border)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(path, overflow: TextOverflow.ellipsis, style: pathStyle),
      ),
    );
  }
}

/// Four bars showing passphrase strength.
class StrengthBar extends StatelessWidget {
  const StrengthBar(this.strength, {required this.active, super.key});

  final int strength;

  /// False while nothing is typed: all bars stay empty.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final extra = PjColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final color = switch (strength) {
      0 => scheme.error,
      1 => extra.warn,
      _ => extra.ok,
    };
    final filled = !active ? 0 : (strength == 0 ? 1 : strength);
    return Row(
      spacing: 4,
      children: [
        for (var i = 0; i < 4; i++)
          Expanded(
            child: Container(
              height: 5,
              decoration: BoxDecoration(color: i < filled ? color : extra.border, borderRadius: BorderRadius.circular(3)),
            ),
          ),
      ],
    );
  }
}
