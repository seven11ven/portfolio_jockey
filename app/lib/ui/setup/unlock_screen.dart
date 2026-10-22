import 'dart:async';

import 'package:flutter/material.dart';
import 'package:portfolio_jockey/ui/common.dart';
import 'package:portfolio_jockey/ui/setup/first_run_screen.dart';
import 'package:portfolio_jockey/vault/errors.dart';

/// Shown whenever the app opens, and after Lock.
class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _passphrase = TextEditingController();
  bool _busy = false;
  bool _wrong = false;
  String? _error;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _passphrase.addListener(() => setState(() {}));
    _tickWhileWaiting();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _passphrase.dispose();
    super.dispose();
  }

  Duration get _wait => AppScope.read(context).backoff.remaining;

  void _tickWhileWaiting() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {});
      if (_wait == Duration.zero) {
        timer.cancel();
      }
    });
  }

  Future<void> _unlock() async {
    final passphrase = _passphrase.text;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.read(context).unlock(passphrase);
    } on WrongPassphrase {
      if (mounted) {
        _passphrase.clear();
        setState(() {
          _busy = false;
          _wrong = true;
        });
        _tickWhileWaiting();
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'The vault could not be opened: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wait = _wait;
    final waiting = wait > Duration.zero;
    final canUnlock = !_busy && !waiting && _passphrase.text.isNotEmpty;
    final scheme = Theme.of(context).colorScheme;
    return LockCard(
      icon: Icons.lock_outline,
      title: 'Portfolio Jockey is locked',
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FieldLabel('Passphrase'),
            PassphraseField(
              key: const Key('unlock-passphrase'),
              controller: _passphrase,
              autofocus: true,
              enabled: !_busy,
              onSubmitted: (_) => canUnlock ? _unlock() : null,
              decoration: InputDecoration(
                hintText: 'Enter your passphrase',
                enabledBorder: _wrong
                    ? OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: scheme.error))
                    : null,
              ),
            ),
          ],
        ),
        if (_wrong) const Notice("That passphrase didn't unlock the vault. Check it and try again.", danger: true),
        if (_error case final error?) Notice(error, danger: true),
        FilledButton(
          onPressed: canUnlock ? _unlock : null,
          child: _busy
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(waiting ? 'Try again in ${wait.inSeconds + 1} s' : 'Unlock'),
        ),
        Center(child: Muted('Vault: ${AppScope.of(context).storagePath ?? ''}')),
      ],
    );
  }
}
