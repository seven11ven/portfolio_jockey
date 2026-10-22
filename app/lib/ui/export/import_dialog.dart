import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:portfolio_jockey/services/export_service.dart';
import 'package:portfolio_jockey/ui/common.dart';
import 'package:portfolio_jockey/vault/errors.dart';
import 'package:portfolio_jockey/vault/export_format.dart';

/// Picks a locked export and shows [ImportDialog] for it. Returns true if
/// projects were imported.
Future<bool> importExport(BuildContext context) async {
  final path = await AppScope.read(context).filePicker.pickExport();
  if (path == null || !context.mounted) {
    return false;
  }
  return await showDialog<bool>(context: context, builder: (_) => ImportDialog(file: File(path))) ?? false;
}

/// Import scenes 4 and 5: the export's passphrase, then a confirmation
/// listing the projects (and any renames), then progress with Cancel.
/// Nothing is written before Import is pressed, and a failed or cancelled
/// import removes what it created. Pops true once projects are imported.
class ImportDialog extends StatefulWidget {
  const ImportDialog({required this.file, super.key});

  final File file;

  @override
  State<ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<ImportDialog> {
  final _passphrase = TextEditingController();
  LockedExport? _opened;
  bool _busy = false;
  String? _error;
  CancelToken? _cancel;
  ExportProgress? _progress;

  @override
  void initState() {
    super.initState();
    _passphrase.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _opened?.dispose();
    _passphrase.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final opened = await AppScope.read(context).exports.openLocked(widget.file, _passphrase.text);
      _passphrase.clear();
      if (!mounted) {
        opened.dispose();
        return;
      }
      setState(() {
        _opened = opened;
        _busy = false;
      });
    } on WrongExportPassphrase {
      _fail("That passphrase doesn't open this export, or the export is damaged.");
    } on VaultFormatError catch (e) {
      _fail("This file can't be imported: ${e.message}.");
    } on Exception catch (e) {
      _fail("This export can't be opened: $e");
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

  Future<void> _import() async {
    final opened = _opened!;
    final cancel = CancelToken();
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _cancel = cancel;
      _error = null;
    });
    try {
      final ids = await AppScope.read(context).exports.import(
        opened,
        cancel: cancel,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _progress = progress);
          }
        },
      );
      messenger.showSnackBar(SnackBar(content: Text('Imported ${plural(ids.length, 'project')}')));
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on Cancelled {
      messenger.showSnackBar(const SnackBar(content: Text('Import cancelled. Nothing was added.')));
      if (mounted) {
        Navigator.of(context).pop(false);
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _cancel = null;
          _error = 'Nothing was added: the export is damaged or incomplete. ($e)';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final opened = _opened;
    final cancel = _cancel;
    return PopScope(
      canPop: cancel == null,
      child: switch ((opened, cancel)) {
        (null, _) => _passphraseStep(context),
        (final LockedExport opened, null) => _confirmStep(context, opened),
        (final LockedExport opened, final CancelToken cancel) => _progressStep(context, opened, cancel),
      },
    );
  }

  Widget _passphraseStep(BuildContext context) => PjDialog(
    title: 'Open this export',
    content: [
      Text(widget.file.path, style: pathStyle),
      PassphraseField(
        key: const Key('import-passphrase'),
        controller: _passphrase,
        autofocus: true,
        enabled: !_busy,
        decoration: const InputDecoration(labelText: 'Passphrase for this export', helperText: 'The passphrase chosen when the export was made.'),
        onSubmitted: (_) => _passphrase.text.isEmpty || _busy ? null : _open(),
      ),
      if (_error case final error?) Notice(error, danger: true),
    ],
    actions: [
      OutlinedButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
      FilledButton(
        onPressed: _passphrase.text.isEmpty || _busy ? null : _open,
        child: _busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Open'),
      ),
    ],
  );

  Widget _confirmStep(BuildContext context, LockedExport opened) => PjDialog(
    title: 'Import projects?',
    content: [
      Text(widget.file.path, style: pathStyle),
      SummaryBox(
        children: [
          for (var i = 0; i < opened.projects.length; i++)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 10,
              children: [
                Expanded(child: Text(opened.projects[i].name)),
                Flexible(
                  child: Muted(
                    opened.importNames[i] == opened.projects[i].name
                        ? plural(opened.projects[i].files.length, 'file')
                        : '${plural(opened.projects[i].files.length, 'file')} · already exists, imported as “${opened.importNames[i]}”',
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
        ],
      ),
      const Muted('Imported files are re-encrypted into your vault with new keys.'),
      if (_error case final error?) Notice(error, danger: true),
    ],
    actions: [
      OutlinedButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
      FilledButton(onPressed: opened.projects.isEmpty ? null : _import, child: Text('Import ${plural(opened.projects.length, 'project')}')),
    ],
  );

  Widget _progressStep(BuildContext context, LockedExport opened, CancelToken cancel) {
    final progress = _progress;
    return PjDialog(
      title: 'Importing ${plural(opened.projects.length, 'project')}…',
      content: [
        LinearProgressIndicator(value: progress == null || progress.bytesTotal == 0 ? null : progress.bytesDone / progress.bytesTotal),
        Muted(
          progress == null
              ? 'Starting…'
              : '${progress.projectName} · file ${progress.fileNumber} of ${progress.fileCount} · ${formatBytes(progress.bytesDone)} of ${formatBytes(progress.bytesTotal)}',
        ),
      ],
      actions: [OutlinedButton(onPressed: cancel.isCancelled ? null : () => setState(cancel.cancel), child: const Text('Cancel import'))],
    );
  }
}
