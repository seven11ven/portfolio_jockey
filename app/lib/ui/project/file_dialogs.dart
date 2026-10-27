import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:portfolio_jockey/services/project_service.dart';
import 'package:portfolio_jockey/services/tag_changes.dart';
import 'package:portfolio_jockey/ui/common.dart';
import 'package:portfolio_jockey/ui/home/project_dialogs.dart';
import 'package:portfolio_jockey/vault/project_index.dart';

/// What the user confirmed in "Add files".
final class AddFilesRequest {
  const AddFilesRequest({required this.tags, required this.newTags});

  final List<String> tags;
  final List<String> newTags;
}

/// "Add N files to …?": lists the picked files, with optional tags for the batch.
/// Returns the request when confirmed; the caller then runs [AddProgressDialog].
class AddFilesDialog extends StatefulWidget {
  const AddFilesDialog({required this.index, required this.paths, this.where, super.key});

  final ProjectIndex index;
  final List<String> paths;

  /// The folder the files go into, as a path ("Project / Folder"); null is the project's top level.
  final String? where;

  @override
  State<AddFilesDialog> createState() => _AddFilesDialogState();
}

class _AddFilesDialogState extends State<AddFilesDialog> {
  late final List<String> _tags = [...widget.index.tags];
  final List<String> _newTags = [];
  final Set<String> _chosen = {};
  final _newTag = TextEditingController();
  bool _addingTag = false;
  Map<String, int?>? _sizes;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSizes());
  }

  @override
  void dispose() {
    _newTag.dispose();
    super.dispose();
  }

  Future<void> _loadSizes() async {
    final sizes = <String, int?>{};
    for (final path in widget.paths) {
      try {
        sizes[path] = await File(path).length();
      } on FileSystemException {
        sizes[path] = null;
      }
    }
    if (mounted) {
      setState(() => _sizes = sizes);
    }
  }

  void _addTag() {
    final name = cleanTagName(_newTag.text);
    setState(() {
      if (name != null && !hasTag(_tags, name)) {
        _tags.add(name);
        _newTags.add(name);
        _chosen.add(name);
      }
      _newTag.clear();
      _addingTag = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.paths.length;
    return PjDialog(
      title: 'Add ${plural(count, 'file')} to “${widget.where ?? widget.index.name}”?',
      content: [
        SummaryBox(
          children: [
            for (final path in widget.paths)
              Row(
                spacing: 8,
                children: [
                  Icon(fileKind(path).icon, size: 18),
                  Expanded(child: Text(File(path).uri.pathSegments.last, overflow: TextOverflow.ellipsis)),
                  Muted(switch (_sizes?[path]) {
                    final int size => formatBytes(size),
                    null when _sizes == null => '…',
                    _ => "can't be read",
                  }),
                ],
              ),
          ],
        ),
        const FieldLabel('Tags for these files (optional)'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in _tags)
              TagChip(
                tag,
                selected: _chosen.contains(tag),
                onTap: () => setState(() => _chosen.contains(tag) ? _chosen.remove(tag) : _chosen.add(tag)),
              ),
            if (_addingTag)
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _newTag,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: 'New tag'),
                  onSubmitted: (_) => _addTag(),
                ),
              )
            else
              TagChip('New tag', icon: Icons.add, onTap: () => setState(() => _addingTag = true)),
          ],
        ),
        const Muted('Each file is encrypted and copied into the project. The originals are left where they are.'),
      ],
      actions: [
        OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            AddFilesRequest(tags: [for (final t in _tags) if (_chosen.contains(t)) t], newTags: _newTags),
          ),
          child: Text('Encrypt and add ${plural(count, 'file')}'),
        ),
      ],
    );
  }
}

/// Encrypts the files with a progress bar, then returns the [AddResult].
class AddProgressDialog extends StatefulWidget {
  const AddProgressDialog({required this.projectId, required this.paths, required this.request, this.folderId, super.key});

  final String projectId;
  final List<String> paths;
  final AddFilesRequest request;
  final String? folderId;

  @override
  State<AddProgressDialog> createState() => _AddProgressDialogState();
}

class _AddProgressDialogState extends State<AddProgressDialog> {
  AddProgress? _progress;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    AddResult result;
    try {
      result = await AppScope.read(context).projects.addFiles(
        widget.projectId,
        widget.paths,
        tags: widget.request.tags,
        newTags: widget.request.newTags,
        folderId: widget.folderId,
        onProgress: (p) {
          if (mounted) {
            setState(() => _progress = p);
          }
        },
      );
    } on Exception catch (e) {
      result = AddResult(const [], {for (final p in widget.paths) p: '$e'});
    }
    if (mounted) {
      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _progress;
    final fraction = p == null || p.bytesTotal == 0 ? null : p.bytesDone / p.bytesTotal;
    return PopScope(
      canPop: false,
      child: PjDialog(
        title: 'Encrypting files…',
        content: [
          Text(p == null ? 'Starting…' : 'File ${p.fileNumber} of ${p.fileCount}: ${p.fileName}', overflow: TextOverflow.ellipsis),
          LinearProgressIndicator(value: fraction),
          const Muted('Keep the app open until this finishes.'),
        ],
        actions: const [],
      ),
    );
  }
}

/// Lists files that couldn't be added. The others were added.
class AddFailuresDialog extends StatelessWidget {
  const AddFailuresDialog({required this.result, super.key});

  final AddResult result;

  @override
  Widget build(BuildContext context) => PjDialog(
    title: '${plural(result.failed.length, 'file')} could not be added',
    content: [
      if (result.added.isNotEmpty) Text('${plural(result.added.length, 'file')} were added. These were not:'),
      SummaryBox(
        children: [
          for (final MapEntry(key: path, value: reason) in result.failed.entries)
            Text('${File(path).uri.pathSegments.last}: $reason'),
        ],
      ),
    ],
    actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
  );
}

/// "Rename file", with the "Old → New" summary.
class RenameFileDialog extends StatefulWidget {
  const RenameFileDialog({required this.projectId, required this.file, super.key});

  final String projectId;
  final FileEntry file;

  @override
  State<RenameFileDialog> createState() => _RenameFileDialogState();
}

class _RenameFileDialogState extends WriteDialogState<RenameFileDialog> {
  late final _name = TextEditingController(text: widget.file.name);

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
    final changed = newName.isNotEmpty && newName != widget.file.name;
    return PjDialog(
      title: 'Rename file',
      content: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FieldLabel('New name'),
            TextField(controller: _name, autofocus: true),
          ],
        ),
        if (changed) SummaryBox(children: [ChangeArrow(widget.file.name, newName)]),
        const Muted('Only the name inside the project changes. The original file keeps its name.'),
        ?errorNotice(),
      ],
      actions: [
        cancelButton(),
        confirmButton(
          'Confirm rename',
          enabled: changed,
          onConfirm: () => AppScope.read(context).projects.renameFile(widget.projectId, widget.file.id, newName),
        ),
      ],
    );
  }
}

/// Which copy a delete removes: the original (to the Trash), the project
/// copy (permanently), or both.
enum DeleteTarget { device, project, both }

/// The notice shown after a confirmed delete.
String deletedMessage(DeleteTarget target, String fileName) => switch (target) {
  DeleteTarget.device => '$fileName: original moved to Trash',
  DeleteTarget.project => '$fileName: removed from the project',
  DeleteTarget.both => '$fileName: original trashed and project copy deleted',
};

/// The three confirmations from the file menu (mockup scenes 4a–4c). The
/// original always goes to the Trash; the project copy is deleted permanently.
class DeleteFileDialog extends StatefulWidget {
  const DeleteFileDialog({required this.projectId, required this.projectName, required this.file, required this.target, super.key});

  final String projectId;
  final String projectName;
  final FileEntry file;
  final DeleteTarget target;

  @override
  State<DeleteFileDialog> createState() => _DeleteFileDialogState();
}

class _DeleteFileDialogState extends WriteDialogState<DeleteFileDialog> {
  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final original = file.shownOriginal ?? 'an unknown location';
    final service = AppScope.read(context).projects;
    final bold = const TextStyle(fontWeight: FontWeight.w700);
    return switch (widget.target) {
      DeleteTarget.device => PjDialog(
        title: 'Move the original to the Trash?',
        danger: true,
        content: [
          SummaryBox(children: [const Muted('Original location'), Text(original, style: pathStyle)]),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'The original is moved to your Trash. You can restore it from there until the Trash is emptied. The encrypted copy in '),
                TextSpan(text: widget.projectName, style: bold),
                const TextSpan(text: ' stays.'),
              ],
            ),
          ),
          ?errorNotice(),
        ],
        actions: [
          cancelButton(),
          confirmButton('Move to Trash', danger: true, enabled: true, onConfirm: () => service.trashOriginal(widget.projectId, file.id)),
        ],
      ),
      DeleteTarget.project => PjDialog(
        title: 'Remove from “${widget.projectName}”?',
        danger: true,
        content: [
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'The encrypted copy of '),
                TextSpan(text: file.name, style: bold),
                TextSpan(
                  text: file.tags.isEmpty
                      ? ' is permanently deleted from the project.'
                      : ' is permanently deleted from the project, along with its tags (${file.tags.join(', ')}).',
                ),
              ],
            ),
          ),
          Muted(file.originalPath == null ? 'No original elsewhere is touched.' : 'The original at $original is not touched.'),
          ?errorNotice(),
        ],
        actions: [
          cancelButton(),
          confirmButton('Delete from project', danger: true, enabled: true, onConfirm: () => service.deleteFromProject(widget.projectId, file.id)),
        ],
      ),
      DeleteTarget.both => PjDialog(
        title: 'Trash the original and delete the copy?',
        danger: true,
        content: [
          Text.rich(TextSpan(children: [const TextSpan(text: 'Both copies of '), TextSpan(text: file.name, style: bold), const TextSpan(text: ' are removed:')])),
          SummaryBox(
            children: [
              Row(
                spacing: 8,
                children: [const Icon(Icons.delete_outline, size: 18), Expanded(child: Text('The original at $original is moved to your Trash'))],
              ),
              Row(
                spacing: 8,
                children: [
                  const Icon(Icons.lock_outline, size: 18),
                  Expanded(child: Text('The encrypted copy in ${widget.projectName} is permanently deleted')),
                ],
              ),
            ],
          ),
          const Muted('The original can be restored from the Trash until it is emptied.'),
          ?errorNotice(),
        ],
        actions: [
          cancelButton(),
          confirmButton(
            'Trash and delete',
            danger: true,
            enabled: true,
            onConfirm: () => service.trashOriginalAndDeleteCopy(widget.projectId, file.id),
          ),
        ],
      ),
    };
  }
}
