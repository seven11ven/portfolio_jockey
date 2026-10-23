import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:portfolio_jockey/app/theme.dart';
import 'package:portfolio_jockey/services/project_service.dart';
import 'package:portfolio_jockey/ui/common.dart';
import 'package:portfolio_jockey/ui/export/export_dialog.dart';
import 'package:portfolio_jockey/vault/project_index.dart';

/// The largest cover image accepted, to keep the home screen quick to load.
const int maxCoverBytes = 20 * 1000 * 1000;

/// Lets the user pick a cover image and reads it. Shows an error and returns
/// null if it's too large or can't be read.
Future<Uint8List?> pickCoverImage(BuildContext context) async {
  final path = await AppScope.read(context).filePicker.pickImage();
  if (path == null) {
    return null;
  }
  try {
    final file = File(path);
    if (await file.length() > maxCoverBytes) {
      if (context.mounted) {
        showError(context, 'That image is larger than ${formatBytes(maxCoverBytes)}. Choose a smaller one.');
      }
      return null;
    }
    return await file.readAsBytes();
  } on FileSystemException catch (e) {
    if (context.mounted) {
      showError(context, 'The image could not be read: ${e.message}');
    }
    return null;
  }
}

/// Base for dialogs whose confirm button writes to disk: shows a spinner
/// while writing, and the error if it fails, without closing.
abstract class WriteDialogState<T extends StatefulWidget> extends State<T> {
  bool busy = false;
  String? error;

  Future<void> runWrite(Future<void> Function() write) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await write();
      if (mounted) {
        Navigator.of(context).pop(true);
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

  Widget confirmButton(String label, {required bool enabled, required Future<void> Function() onConfirm, bool danger = false}) =>
      FilledButton(
        style: danger ? dangerButtonStyle(context) : null,
        onPressed: enabled && !busy ? () => runWrite(onConfirm) : null,
        child: busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(label),
      );

  Widget cancelButton({String label = 'Cancel'}) =>
      OutlinedButton(onPressed: busy ? null : () => Navigator.of(context).pop(false), child: Text(label));

  Widget? errorNotice() => error == null ? null : Notice(error!, danger: true);
}

/// "New project". Creating the project is the confirmation.
class NewProjectDialog extends StatefulWidget {
  const NewProjectDialog({super.key});

  @override
  State<NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends WriteDialogState<NewProjectDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  Uint8List? _cover;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PjDialog(
    title: 'New project',
    content: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FieldLabel('Name'),
          TextField(controller: _name, autofocus: true, key: const Key('project-name')),
        ],
      ),
      CoverPicker(
        name: _name.text,
        image: _cover,
        enabled: !busy,
        onChoose: () async {
          final image = await pickCoverImage(context);
          if (image != null) {
            setState(() => _cover = image);
          }
        },
        onRemove: _cover == null ? null : () => setState(() => _cover = null),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FieldLabel('Description'),
          TextField(controller: _description, maxLines: 3, minLines: 2),
        ],
      ),
      ?errorNotice(),
    ],
    actions: [
      cancelButton(),
      confirmButton(
        'Create project',
        enabled: _name.text.trim().isNotEmpty,
        onConfirm: () => AppScope.read(context).projects.createProject(name: _name.text, description: _description.text, cover: _cover),
      ),
    ],
  );
}

/// The cover preview with "Choose image…" (and "Remove", when there is one).
class CoverPicker extends StatelessWidget {
  const CoverPicker({required this.name, required this.image, required this.enabled, required this.onChoose, this.onRemove, super.key});

  final String name;
  final Uint8List? image;
  final bool enabled;
  final VoidCallback onChoose;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const FieldLabel('Cover art'),
      Row(
        spacing: 12,
        children: [
          CoverView(name: name, image: image, height: 80, width: 120),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 6,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(onPressed: enabled ? onChoose : null, child: const Text('Choose image…')),
                    if (onRemove != null) TextButton(onPressed: enabled ? onRemove : null, child: const Text('Remove')),
                  ],
                ),
                const Muted('The image is encrypted along with the project.'),
              ],
            ),
          ),
        ],
      ),
    ],
  );
}

/// "Rename project", with the "Old → New" summary.
class RenameProjectDialog extends StatefulWidget {
  const RenameProjectDialog({required this.projectId, required this.currentName, super.key});

  final String projectId;
  final String currentName;

  @override
  State<RenameProjectDialog> createState() => _RenameProjectDialogState();
}

class _RenameProjectDialogState extends WriteDialogState<RenameProjectDialog> {
  late final _name = TextEditingController(text: widget.currentName);

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final newName = _name.text.trim();
    final changed = newName.isNotEmpty && newName != widget.currentName;
    return PjDialog(
      title: 'Rename project',
      content: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FieldLabel('New name'),
            TextField(controller: _name, autofocus: true, key: const Key('new-name')),
          ],
        ),
        if (changed) SummaryBox(children: [ChangeArrow(widget.currentName, newName)]),
        ?errorNotice(),
      ],
      actions: [
        cancelButton(),
        confirmButton(
          'Confirm rename',
          enabled: changed,
          onConfirm: () => AppScope.read(context).projects.renameProject(widget.projectId, newName),
        ),
      ],
    );
  }
}

/// "Change cover art and description", with a summary of the changes.
class EditDetailsDialog extends StatefulWidget {
  const EditDetailsDialog({required this.projectId, required this.index, required this.cover, super.key});

  final String projectId;
  final ProjectIndex index;
  final Uint8List? cover;

  @override
  State<EditDetailsDialog> createState() => _EditDetailsDialogState();
}

class _EditDetailsDialogState extends WriteDialogState<EditDetailsDialog> {
  late final _description = TextEditingController(text: widget.index.description);
  CoverChange _coverChange = const KeepCover();

  @override
  void initState() {
    super.initState();
    _description.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Uint8List? get _shownCover => switch (_coverChange) {
    KeepCover() => widget.cover,
    RemoveCover() => null,
    ReplaceCover(:final image) => image,
  };

  @override
  Widget build(BuildContext context) {
    final descriptionChanged = _description.text.trim() != widget.index.description;
    final changes = [
      if (_coverChange is ReplaceCover) 'New cover art',
      if (_coverChange is RemoveCover) 'Remove the cover art',
      if (descriptionChanged) 'New description',
    ];
    return PjDialog(
      title: 'Cover art and description',
      content: [
        CoverPicker(
          name: widget.index.name,
          image: _shownCover,
          enabled: !busy,
          onChoose: () async {
            final image = await pickCoverImage(context);
            if (image != null) {
              setState(() => _coverChange = ReplaceCover(image));
            }
          },
          onRemove: _shownCover == null ? null : () => setState(() => _coverChange = widget.cover == null ? const KeepCover() : const RemoveCover()),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FieldLabel('Description'),
            TextField(controller: _description, maxLines: 3, minLines: 2),
          ],
        ),
        if (changes.isNotEmpty) SummaryBox(children: [for (final c in changes) Text('• $c')]),
        ?errorNotice(),
      ],
      actions: [
        cancelButton(),
        confirmButton(
          'Save changes',
          enabled: changes.isNotEmpty,
          onConfirm: () => AppScope.read(context).projects.updateDetails(widget.projectId, description: _description.text, cover: _coverChange),
        ),
      ],
    );
  }
}

/// "Delete project": the name must be typed before Delete is enabled.
class DeleteProjectDialog extends StatefulWidget {
  const DeleteProjectDialog({required this.projectId, required this.index, super.key});

  final String projectId;
  final ProjectIndex index;

  @override
  State<DeleteProjectDialog> createState() => _DeleteProjectDialogState();
}

class _DeleteProjectDialogState extends WriteDialogState<DeleteProjectDialog> {
  final _typed = TextEditingController();

  @override
  void initState() {
    super.initState();
    _typed.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.index.name;
    final count = widget.index.files.length;
    return PjDialog(
      title: 'Delete “$name”?',
      danger: true,
      content: [
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'This permanently deletes the project and its '),
              TextSpan(
                text: '${plural(count, 'encrypted file')} (${formatBytes(widget.index.totalSize)})',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const TextSpan(text: " from this device. It can't be undone."),
            ],
          ),
        ),
        const Muted('Original files elsewhere on this device are not touched. Tip: export the project first if you might want it later.'),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FieldLabel('Type $name to confirm'),
            TextField(controller: _typed, key: const Key('confirm-name')),
          ],
        ),
        ?errorNotice(),
      ],
      actions: [
        cancelButton(),
        OutlinedButton(
          onPressed: busy
              ? null
              : () => showDialog<bool>(
                  context: context,
                  builder: (_) => ExportDialog(projects: [ProjectSummary(id: widget.projectId, index: widget.index)]),
                ),
          child: const Text('Export first…'),
        ),
        confirmButton(
          'Delete project',
          danger: true,
          enabled: _typed.text == name,
          onConfirm: () => AppScope.read(context).projects.deleteProject(widget.projectId),
        ),
      ],
    );
  }
}
