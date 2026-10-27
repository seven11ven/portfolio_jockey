import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:portfolio_jockey/services/export_service.dart';
import 'package:portfolio_jockey/ui/common.dart';
import 'package:portfolio_jockey/ui/home/project_dialogs.dart';
import 'package:portfolio_jockey/vault/native/libc.dart';
import 'package:portfolio_jockey/vault/project_index.dart';

/// Export scenes 6 and 6b: save a readable copy of one file, from its menu or
/// the preview's "…" menu. There's no lock option (PM decision, 2026-10-22):
/// the point is a normal file to use elsewhere. The dialog is the
/// confirmation, and pops true once the copy is saved.
class ReadableCopyDialog extends StatefulWidget {
  const ReadableCopyDialog({required this.projectId, required this.projectName, required this.file, super.key});

  final String projectId;
  final String projectName;
  final FileEntry file;

  @override
  State<ReadableCopyDialog> createState() => _ReadableCopyDialogState();
}

class _ReadableCopyDialogState extends WriteDialogState<ReadableCopyDialog> {
  late String _target = _defaultTarget();
  bool _exists = false;
  int? _free;

  bool get _enoughSpace {
    final free = _free;
    return free == null || free >= widget.file.size + 1024 * 1024;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_checkTarget());
  }

  String _defaultTarget() {
    final home = Platform.environment['HOME'] ?? '/';
    final documents = Directory('$home/Documents');
    return '${documents.existsSync() ? documents.path : home}/${safeName(widget.file.name, fallback: 'file')}';
  }

  Future<void> _checkTarget() async {
    final file = File(_target);
    final exists = await file.exists();
    final free = Libc.instance.freeBytes(file.parent.path);
    if (mounted) {
      setState(() {
        _exists = exists;
        _free = free;
      });
    }
  }

  Future<void> _changeTarget() async {
    final file = File(_target);
    final chosen = await AppScope.read(context).filePicker.pickSaveLocation(suggestedName: file.uri.pathSegments.last, initialDirectory: file.parent.path);
    if (chosen != null && mounted) {
      setState(() => _target = chosen);
      unawaited(_checkTarget());
    }
  }

  /// Run by [confirmButton] inside [runWrite], which shows errors and pops.
  Future<void> _save() async {
    final controller = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final target = File(_target);
    await controller.exports.exportReadableCopy(widget.projectId, widget.file, target);
    messenger.showSnackBar(SnackBar(content: Text('Saved a readable copy to ${target.path}')));
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    return PopScope(
      canPop: !busy,
      child: PjDialog(
        title: 'Save a readable copy of ${file.name}?',
        content: [
          SummaryBox(
            children: [
              Row(spacing: 10, children: [Expanded(child: Text(file.name)), Muted(formatBytes(file.size))]),
            ],
          ),
          Notice(
            'The copy is not protected. Anyone who can open the folder you save it to can read it. '
            'The encrypted file in ${widget.projectName} stays as it is.',
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 6,
            children: [
              const FieldLabel('Save to'),
              Row(
                spacing: 8,
                children: [
                  Expanded(child: Text(_target, style: pathStyle)),
                  OutlinedButton(onPressed: busy ? null : _changeTarget, child: const Text('Change…')),
                ],
              ),
            ],
          ),
          if (_exists) Notice('A file named ${File(_target).uri.pathSegments.last} already exists there. Saving replaces it.'),
          if (!_enoughSpace) const Notice('Not enough free space at the destination. Choose another location.', danger: true),
          ?errorNotice(),
        ],
        actions: [
          cancelButton(),
          confirmButton('Save readable copy', enabled: _enoughSpace, onConfirm: _save),
        ],
      ),
    );
  }
}
