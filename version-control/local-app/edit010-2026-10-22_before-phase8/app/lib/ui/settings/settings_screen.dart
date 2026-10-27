import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:portfolio_jockey/app/passphrase_rules.dart';
import 'package:portfolio_jockey/app/theme.dart';
import 'package:portfolio_jockey/app/version.dart';
import 'package:portfolio_jockey/services/project_service.dart';
import 'package:portfolio_jockey/services/storage_move.dart';
import 'package:portfolio_jockey/ui/common.dart';
import 'package:portfolio_jockey/ui/export/export_dialog.dart';
import 'package:portfolio_jockey/ui/home/project_dialogs.dart';
import 'package:portfolio_jockey/ui/preview/edit_dialogs.dart';
import 'package:portfolio_jockey/ui/setup/first_run_screen.dart';
import 'package:portfolio_jockey/vault/errors.dart';
import 'package:portfolio_jockey/vault/native/libc.dart';

/// Settings scene 1, opened from the ⚙ cog: colour scheme, storage location,
/// bulk export, passphrase, lock, and About.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  ProjectListing? _listing;
  int? _free;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final controller = AppScope.read(context);
    final listing = await controller.projects.listProjects();
    final path = controller.storagePath;
    if (mounted) {
      setState(() {
        _listing = listing;
        _free = path == null ? null : Libc.instance.freeBytes(path);
      });
    }
  }

  Future<void> _move() async {
    final controller = AppScope.read(context);
    if (controller.edits.active != null) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => PjDialog(
          title: 'Finish editing first',
          content: [Text('${controller.edits.active!.info.fileName} is still being edited. Save or discard it, then move the storage location.')],
          actions: [FilledButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('OK'))],
        ),
      );
      return;
    }
    final picked = await controller.filePicker.pickFolder(initialDirectory: File(controller.storagePath!).parent.path);
    if (picked == null || !mounted) {
      return;
    }
    try {
      final move = await StorageMove.plan(Directory(controller.storagePath!), Directory(picked));
      if (!mounted) {
        return;
      }
      final moved = await showDialog<bool>(
        context: context,
        builder: (_) => MoveStorageDialog(move: move, projectCount: _listing?.projects.length ?? 0),
      );
      if (moved ?? false) {
        await _reload();
      }
    } on MoveRefused catch (e) {
      if (mounted) {
        showError(context, "Can't move there: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final listing = _listing;
    final size = listing?.projects.fold(0, (sum, p) => sum + p.index.totalSize) ?? 0;
    Widget section(String title, List<Widget> children) => Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [Text(title, style: Theme.of(context).textTheme.titleMedium), ...children],
        ),
      ),
    );
    Widget row(String label, Widget trailing, {String? detail}) => Row(
      spacing: 12,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [Text(label), if (detail != null) Muted(detail)],
          ),
        ),
        Flexible(
          child: Align(alignment: Alignment.centerRight, child: trailing),
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: withEditBanner(
        ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 16,
                  children: [
                    section('Color scheme', [
                      row(
                        'Mode',
                        SegmentedButton<ThemeMode>(
                          segments: const [
                            ButtonSegment(value: ThemeMode.system, label: Text('System')),
                            ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                            ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                          ],
                          selected: {controller.themeMode},
                          showSelectedIcon: false,
                          onSelectionChanged: (s) => unawaited(controller.setAppearance(mode: s.single)),
                        ),
                      ),
                      row(
                        'Accent color',
                        Wrap(
                          spacing: 10,
                          children: [
                            for (final accent in PjAccent.values)
                              Semantics(
                                label: accent.name,
                                selected: accent == controller.accent,
                                button: true,
                                child: InkWell(
                                  key: Key('accent-${accent.name}'),
                                  customBorder: const CircleBorder(),
                                  onTap: () => unawaited(controller.setAppearance(accent: accent)),
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).brightness == Brightness.dark ? accent.dark : accent.light,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        width: 3,
                                        color: accent == controller.accent ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ]),
                    section('Storage location', [
                      const Muted('Where project folders are kept. Everything inside is encrypted.'),
                      Text(controller.storagePath ?? '', style: pathStyle),
                      row(
                        listing == null
                            ? '…'
                            : '${plural(listing.projects.length, 'project')} · ${formatBytes(size)}${_free == null ? '' : ' · ${formatBytes(_free!)} free'}',
                        OutlinedButton(onPressed: listing == null ? null : _move, child: const Text('Move…')),
                      ),
                    ]),
                    section('Export', [
                      row(
                        'Export several or all projects as one ZIP or TAR, or as one file locked with a passphrase.',
                        OutlinedButton(
                          onPressed: listing == null || listing.projects.isEmpty
                              ? null
                              : () => showDialog<bool>(context: context, builder: (_) => ExportDialog(projects: listing.projects, bulk: true)),
                          child: const Text('Export projects…'),
                        ),
                      ),
                    ]),
                    section('Security', [
                      row(
                        'Change passphrase',
                        OutlinedButton(
                          onPressed: () => showDialog<bool>(context: context, builder: (_) => const ChangePassphraseDialog()),
                          child: const Text('Change…'),
                        ),
                      ),
                      row(
                        'Lock now',
                        OutlinedButton.icon(onPressed: () => unawaited(requestLock(context)), icon: const Icon(Icons.lock_outline), label: const Text('Lock')),
                      ),
                    ]),
                    section('About', [
                      row('Version', const Text(appVersion)),
                      row('Network access', const Text('None. This app never connects to the internet.')),
                      row(
                        'License',
                        TextButton(
                          onPressed: () => showLicensePage(context: context, applicationName: 'Portfolio Jockey', applicationVersion: appVersion),
                          child: const Text('AGPL-3.0 · Show licenses'),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Settings scene 2: confirm, then copy, check and switch, with progress.
class MoveStorageDialog extends StatefulWidget {
  const MoveStorageDialog({required this.move, required this.projectCount, super.key});

  final StorageMove move;
  final int projectCount;

  @override
  State<MoveStorageDialog> createState() => _MoveStorageDialogState();
}

class _MoveStorageDialogState extends WriteDialogState<MoveStorageDialog> {
  MoveProgress? _progress;
  late final int? _free = widget.move.freeAtTarget;

  bool get _enoughSpace {
    final free = _free;
    return free == null || free >= widget.move.bytesTotal + 1024 * 1024;
  }

  Future<void> _run() async {
    final controller = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final oldPath = widget.move.source.path;
    await runWrite(() async {
      final removed = await controller.moveStorage(
        widget.move,
        onProgress: (p) {
          if (mounted) {
            setState(() => _progress = p);
          }
        },
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            removed
                ? 'Moved to ${widget.move.target.path}'
                : 'Moved to ${widget.move.target.path}. The old folder ($oldPath) couldn\'t be removed; you can delete it yourself.',
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final move = widget.move;
    final progress = _progress;
    return PopScope(
      canPop: !busy,
      child: PjDialog(
        title: busy ? 'Moving ${plural(widget.projectCount, 'project')}…' : 'Move all projects?',
        content: [
          SummaryBox(
            children: [
              const Muted('From'),
              Text(move.source.path, style: pathStyle),
              const Muted('To'),
              Text(move.target.path, style: pathStyle),
            ],
          ),
          if (busy) ...[
            LinearProgressIndicator(value: progress == null || progress.bytesTotal == 0 ? null : progress.bytesDone / progress.bytesTotal),
            Muted(progress == null ? 'Starting…' : '${formatBytes(progress.bytesDone)} of ${formatBytes(progress.bytesTotal)} copied and checked'),
          ] else ...[
            Text(
              '${plural(widget.projectCount, 'project')} (${formatBytes(move.bytesTotal)}) are copied to the new location and checked. '
              'Then the old folder is deleted. If anything fails, the old location stays in use.',
            ),
            Notice(
              switch (_free) {
                null => "Don't remove the drive while moving.",
                final free => "The new location has ${formatBytes(free)} free. Don't remove the drive while moving.",
              },
            ),
            if (!_enoughSpace) const Notice('Not enough free space at the new location.', danger: true),
          ],
          ?errorNotice(),
        ],
        actions: [
          cancelButton(),
          FilledButton(
            onPressed: busy || !_enoughSpace ? null : _run,
            child: busy
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Move ${plural(widget.projectCount, 'project')}'),
          ),
        ],
      ),
    );
  }
}

/// Settings scene 3. Only the key that protects the files is re-wrapped, so
/// it's quick; the new passphrase follows the same rules as on first run.
class ChangePassphraseDialog extends StatefulWidget {
  const ChangePassphraseDialog({super.key});

  @override
  State<ChangePassphraseDialog> createState() => _ChangePassphraseDialogState();
}

class _ChangePassphraseDialogState extends WriteDialogState<ChangePassphraseDialog> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void initState() {
    super.initState();
    for (final c in [_current, _new, _confirm]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_current, _new, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _change() async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = AppScope.read(context);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await controller.changePassphrase(_current.text, _new.text);
      for (final c in [_current, _new, _confirm]) {
        c.clear();
      }
      messenger.showSnackBar(const SnackBar(content: Text('Passphrase changed')));
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on WrongPassphrase {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'The current passphrase is wrong. Nothing was changed.';
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Nothing was changed. $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strength = passphraseStrength(_new.text);
    final mismatch = _confirm.text.isNotEmpty && _confirm.text != _new.text;
    final ok = _current.text.isNotEmpty && strength > 0 && _new.text == _confirm.text;
    return PjDialog(
      title: 'Change passphrase',
      content: [
        TextField(key: const Key('current-passphrase'), controller: _current, obscureText: true, enabled: !busy, decoration: const InputDecoration(labelText: 'Current passphrase')),
        TextField(key: const Key('new-passphrase'), controller: _new, obscureText: true, enabled: !busy, decoration: const InputDecoration(labelText: 'New passphrase')),
        StrengthBar(strength, active: _new.text.isNotEmpty),
        Muted(strengthLabel(strength)),
        TextField(
          key: const Key('confirm-new-passphrase'),
          controller: _confirm,
          obscureText: true,
          enabled: !busy,
          decoration: InputDecoration(labelText: 'Confirm new passphrase', errorText: mismatch ? "The passphrases don't match." : null),
        ),
        const Muted("Fast: only the key that protects your files is re-wrapped. Files aren't re-encrypted. Exports aren't affected: a locked export keeps the passphrase chosen when it was made."),
        ?errorNotice(),
      ],
      actions: [
        cancelButton(),
        FilledButton(
          onPressed: ok && !busy ? _change : null,
          child: busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Confirm new passphrase'),
        ),
      ],
    );
  }
}
