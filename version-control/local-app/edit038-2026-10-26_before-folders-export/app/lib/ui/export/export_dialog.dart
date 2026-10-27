import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:portfolio_jockey/app/theme.dart';
import 'package:portfolio_jockey/services/export_service.dart';
import 'package:portfolio_jockey/services/project_service.dart';
import 'package:portfolio_jockey/ui/common.dart';
import 'package:portfolio_jockey/vault/native/libc.dart';

/// Export scenes 1, 1b, 2 and 3: one project (from its "…" menu) or several
/// (bulk, from Settings). Exactly two options (PM decision, 2026-10-22):
/// lock with a custom passphrase, or a regular unlocked ZIP/TAR. The dialog
/// is the confirmation; it then shows progress with Cancel, and pops true
/// once the export is saved.
class ExportDialog extends StatefulWidget {
  const ExportDialog({required this.projects, this.bulk = false, this.format = ArchiveFormat.zip, super.key});

  final List<ProjectSummary> projects;
  final bool bulk;
  final ArchiveFormat format;

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  late final Set<String> _selected = {for (final p in widget.projects) p.id};
  late ArchiveFormat _format = widget.format;
  bool _locked = false;
  final _passphrase = TextEditingController();
  final _confirm = TextEditingController();
  /// Where to save. Inside a Flatpak nothing is suggested (the sandbox can't
  /// write to ~/Documents): the user chooses through the desktop's dialog.
  late String? _target = AppScope.read(context).sandboxed ? null : _defaultTarget();
  int? _free;
  bool _exists = false;
  String? _error;

  CancelToken? _cancel;
  ExportProgress? _progress;

  bool get _running => _cancel != null;

  List<ProjectSummary> get _chosen => [for (final p in widget.projects) if (_selected.contains(p.id)) p];

  int get _bytes => _chosen.fold(0, (sum, p) => sum + p.index.totalSize);

  int get _fileCount => _chosen.fold(0, (sum, p) => sum + p.index.files.length);

  String get _extension => _locked ? lockedExtension : _format.extension;

  /// Room for the archive's own headers on top of the files themselves.
  int get _needed => _bytes + _bytes ~/ 100 + 1024 * 1024;

  bool get _passphraseOk => _passphrase.text.isNotEmpty && _passphrase.text == _confirm.text;

  bool get _enoughSpace => _free == null || _free! >= _needed;

  bool get _canExport => _target != null && _chosen.isNotEmpty && _enoughSpace && (!_locked || _passphraseOk);

  @override
  void initState() {
    super.initState();
    _passphrase.addListener(() => setState(() {}));
    _confirm.addListener(() => setState(() {}));
    unawaited(_checkTarget());
  }

  @override
  void dispose() {
    _passphrase.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String get _baseName {
    final now = DateTime.now();
    final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return widget.bulk ? 'Portfolio Jockey projects $date' : safeName(widget.projects.single.index.name, fallback: 'Project');
  }

  String _defaultTarget() {
    final home = Platform.environment['HOME'] ?? '/';
    final documents = Directory('$home/Documents');
    final folder = documents.existsSync() ? documents.path : home;
    return '$folder/$_baseName.${widget.format.extension}';
  }

  /// Gives the target the extension the current choice needs.
  void _fixExtension() {
    final target = _target;
    if (target == null) {
      return;
    }
    const known = ['zip', 'tar', lockedExtension];
    final dot = target.lastIndexOf('.');
    final slash = target.lastIndexOf('/');
    final hasKnown = dot > slash && known.contains(target.substring(dot + 1).toLowerCase());
    _target = '${hasKnown ? target.substring(0, dot) : target}.$_extension';
    unawaited(_checkTarget());
  }

  Future<void> _checkTarget() async {
    final target = _target;
    if (target == null) {
      return;
    }
    final file = File(target);
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
    final target = _target;
    final chosen = await AppScope.read(context).filePicker.pickSaveLocation(
      suggestedName: target == null ? '$_baseName.$_extension' : File(target).uri.pathSegments.last,
      initialDirectory: target == null ? null : File(target).parent.path,
    );
    if (chosen != null && mounted) {
      setState(() {
        _target = chosen;
        _fixExtension();
      });
    }
  }

  Future<void> _export() async {
    final controller = AppScope.read(context);
    final cancel = CancelToken();
    final lock = _locked ? LockedWith(_passphrase.text) : Unlocked(_format);
    final target = File(_target!);
    setState(() {
      _cancel = cancel;
      _error = null;
      _progress = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await controller.exports.export(
        projectIds: [for (final p in _chosen) p.id],
        target: target,
        lock: lock,
        cancel: cancel,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _progress = progress);
          }
        },
      );
      _passphrase.clear();
      _confirm.clear();
      messenger.showSnackBar(SnackBar(content: Text('Exported to ${target.path}')));
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on Cancelled {
      messenger.showSnackBar(const SnackBar(content: Text('Export cancelled. Nothing was saved.')));
      if (mounted) {
        Navigator.of(context).pop(false);
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _cancel = null;
          _error = 'Nothing was saved. $e';
        });
        unawaited(_checkTarget());
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(canPop: !_running, child: _running ? _buildProgress(context) : _buildForm(context));

  Widget _buildProgress(BuildContext context) {
    final progress = _progress;
    final total = progress?.bytesTotal ?? _bytes;
    final done = progress?.bytesDone ?? 0;
    return PjDialog(
      title: widget.bulk ? 'Exporting ${plural(_chosen.length, 'project')}…' : 'Exporting “${widget.projects.single.index.name}”…',
      content: [
        LinearProgressIndicator(value: total == 0 ? null : done / total),
        Muted(
          progress == null
              ? (_locked ? 'Protecting the export with your passphrase…' : 'Starting…')
              : '${progress.projectName} · file ${progress.fileNumber} of ${progress.fileCount} · ${formatBytes(done)} of ${formatBytes(total)}',
        ),
      ],
      actions: [OutlinedButton(onPressed: _cancel!.isCancelled ? null : () => setState(_cancel!.cancel), child: const Text('Cancel export'))],
    );
  }

  Widget _buildForm(BuildContext context) {
    final colors = PjColors.of(context);
    final mismatch = _confirm.text.isNotEmpty && _confirm.text != _passphrase.text;
    return PjDialog(
      title: widget.bulk ? 'Export projects' : 'Export “${widget.projects.single.index.name}”',
      width: 520,
      content: [
        if (widget.bulk) _projectList(context),
        CheckboxListTile(
          key: const Key('export-lock'),
          value: _locked,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Lock with a custom passphrase', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text('Only Portfolio Jockey can open a locked export, with that passphrase.'),
          onChanged: (value) => setState(() {
            _locked = value ?? false;
            _fixExtension();
          }),
        ),
        if (_locked) ...[
          PassphraseField(
            key: const Key('export-passphrase'),
            controller: _passphrase,
            decoration: const InputDecoration(labelText: 'Passphrase'),
          ),
          PassphraseField(
            key: const Key('export-confirm'),
            controller: _confirm,
            decoration: InputDecoration(
              labelText: 'Confirm passphrase',
              helperText: _confirm.text.isEmpty ? 'Type the same passphrase again.' : null,
              errorText: mismatch ? "The passphrases don't match." : null,
            ),
          ),
          const Notice("Write it down. A forgotten export passphrase can't be recovered, and the export can't be opened without it."),
        ] else ...[
          Row(
            spacing: 12,
            children: [
              const FieldLabel('Format'),
              SegmentedButton<ArchiveFormat>(
                segments: const [ButtonSegment(value: ArchiveFormat.zip, label: Text('ZIP')), ButtonSegment(value: ArchiveFormat.tar, label: Text('TAR'))],
                selected: {_format},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() {
                  _format = s.single;
                  _fixExtension();
                }),
              ),
            ],
          ),
          Muted(
            widget.bulk
                ? 'One archive with a folder per project: each file once, with its real name, plus project.json listing the description and tags.'
                : 'Each file once, with its real name, plus project.json listing the description and tags.',
          ),
          const Notice('This export is not protected. Anyone who gets the archive can open every file in it.'),
        ],
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 6,
          children: [
            const FieldLabel('Save to'),
            Row(
              spacing: 8,
              children: [
                Expanded(child: _target == null ? const Muted('No location chosen yet', small: false) : Text(_target!, style: pathStyle)),
                OutlinedButton(onPressed: _changeTarget, child: Text(_target == null ? 'Choose…' : 'Change…')),
              ],
            ),
            Muted(
              _free == null
                  ? 'Needs about ${formatBytes(_needed)} of free space at the destination.'
                  : 'Needs about ${formatBytes(_needed)} of free space at the destination (${formatBytes(_free!)} free).',
            ),
          ],
        ),
        if (_exists && _target != null) Notice('A file named ${File(_target!).uri.pathSegments.last} already exists there. Exporting replaces it.'),
        if (!_enoughSpace) Notice('Not enough free space at the destination: about ${formatBytes(_needed)} is needed. Choose another location.', danger: true),
        if (_error case final error?) Notice(error, danger: true),
        if (widget.bulk && _chosen.isEmpty) Text('Choose at least one project.', style: TextStyle(color: colors.muted)),
      ],
      actions: [
        OutlinedButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(
          key: const Key('export-confirm-button'),
          onPressed: _canExport ? _export : null,
          child: Text(
            widget.bulk ? 'Export ${plural(_chosen.length, 'project')}' : 'Export ${plural(_fileCount, 'file')} (${formatBytes(_bytes)})',
          ),
        ),
      ],
    );
  }

  Widget _projectList(BuildContext context) {
    final all = _selected.length == widget.projects.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          value: all ? true : (_selected.isEmpty ? false : null),
          tristate: true,
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text('All projects (${widget.projects.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
          onChanged: (_) => setState(() {
            if (all) {
              _selected.clear();
            } else {
              _selected.addAll([for (final p in widget.projects) p.id]);
            }
          }),
        ),
        for (final project in widget.projects)
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: CheckboxListTile(
              value: _selected.contains(project.id),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text('${project.index.name} · ${formatBytes(project.index.totalSize)}'),
              onChanged: (value) => setState(() => value ?? false ? _selected.add(project.id) : _selected.remove(project.id)),
            ),
          ),
      ],
    );
  }
}
