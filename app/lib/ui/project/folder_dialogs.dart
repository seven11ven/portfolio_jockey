import 'dart:async';

import 'package:flutter/material.dart';
import 'package:portfolio_jockey/app/theme.dart';
import 'package:portfolio_jockey/services/project_service.dart';
import 'package:portfolio_jockey/ui/common.dart';
import 'package:portfolio_jockey/ui/home/project_dialogs.dart';
import 'package:portfolio_jockey/ui/project/explorer.dart';
import 'package:portfolio_jockey/vault/project_index.dart';

/// "New folder" (inside [parentId]) or, with [rename], "Rename folder".
/// The live message and the service use the same name rules.
class FolderNameDialog extends StatefulWidget {
  const FolderNameDialog({required this.projectId, required this.index, this.parentId, this.rename, super.key});

  final String projectId;
  final ProjectIndex index;

  /// Where a new folder goes; null is the top level. Ignored when renaming.
  final String? parentId;
  final FolderEntry? rename;

  @override
  State<FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends WriteDialogState<FolderNameDialog> {
  late final _name = TextEditingController(text: widget.rename?.name ?? '');

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

  String? _problem(String name) {
    if (name.isEmpty) {
      return null;
    }
    final unsafe = folderNameProblem(name);
    if (unsafe != null) {
      return unsafe;
    }
    final parent = widget.rename?.parentId ?? widget.parentId;
    final lower = name.toLowerCase();
    if (widget.index.foldersIn(parent).any((f) => f.id != widget.rename?.id && f.name.toLowerCase() == lower)) {
      return 'A folder named “$name” already exists here. Pick another name.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final name = _name.text.trim();
    final problem = _problem(name);
    final renaming = widget.rename;
    final changed = name.isNotEmpty && problem == null && (renaming == null || name != renaming.name);
    return PjDialog(
      title: renaming == null ? 'New folder' : 'Rename folder',
      content: [
        if (renaming == null) Muted('It will be created in ${folderPathLabel(widget.index, widget.parentId)}.'),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FieldLabel('Folder name'),
            TextField(
              controller: _name,
              autofocus: true,
              key: const Key('folder-name'),
              decoration: InputDecoration(errorText: problem),
              onSubmitted: (_) {
                if (changed && !busy) {
                  unawaited(runWrite(_write));
                }
              },
            ),
          ],
        ),
        if (renaming != null && changed) SummaryBox(children: [ChangeArrow(renaming.name, name)]),
        ?errorNotice(),
      ],
      actions: [
        cancelButton(),
        confirmButton(renaming == null ? 'Create folder' : 'Confirm rename', enabled: changed, onConfirm: _write),
      ],
    );
  }

  Future<void> _write() {
    final projects = AppScope.read(context).projects;
    final renaming = widget.rename;
    return renaming == null
        ? projects.createFolder(widget.projectId, name: _name.text, parentId: widget.parentId)
        : projects.renameFolder(widget.projectId, renaming.id, _name.text);
  }
}

/// A short description of what's being moved, for titles.
String describeItems(ProjectIndex index, List<String> fileIds, List<String> folderIds) {
  if (fileIds.length + folderIds.length == 1) {
    final name = fileIds.isNotEmpty ? index.files.firstWhere((f) => f.id == fileIds.single).name : index.folderById(folderIds.single)!.name;
    return '“$name”';
  }
  if (folderIds.isEmpty) {
    return plural(fileIds.length, 'file');
  }
  if (fileIds.isEmpty) {
    return plural(folderIds.length, 'folder');
  }
  return plural(fileIds.length + folderIds.length, 'item');
}

/// What the screen says after a move, including any renames.
String movedMessage(MoveResult result, String targetLabel) {
  if (result.moved == 0) {
    return 'Nothing to move: already in $targetLabel';
  }
  final moved = 'Moved ${plural(result.moved, 'item')} to $targetLabel';
  return result.renamed.isEmpty ? moved : '$moved. ${plural(result.renamed.length, 'name')} changed to avoid a clash.';
}

/// Moves files and folders. With [pick], the user chooses the target from
/// every folder ("Move to…"); otherwise the target is fixed ([targetFolderId],
/// from a drop) and this just confirms it. [onMoved] gets the result, and
/// where things went, before the dialog closes.
class MoveItemsDialog extends StatefulWidget {
  const MoveItemsDialog({
    required this.projectId,
    required this.index,
    required this.fileIds,
    required this.folderIds,
    required this.onMoved,
    this.targetFolderId,
    this.pick = false,
    super.key,
  });

  final String projectId;
  final ProjectIndex index;
  final List<String> fileIds;
  final List<String> folderIds;
  final String? targetFolderId;
  final bool pick;
  final void Function(MoveResult result, String targetLabel) onMoved;

  @override
  State<MoveItemsDialog> createState() => _MoveItemsDialogState();
}

class _MoveItemsDialogState extends WriteDialogState<MoveItemsDialog> {
  late String? _target = widget.targetFolderId != null && _blocked.contains(widget.targetFolderId) ? null : widget.targetFolderId;

  late final Set<String> _blocked = {for (final id in widget.folderIds) ...widget.index.subtreeIds(id)};

  /// Every folder, parents before children, with its depth (no recursion).
  List<(FolderEntry, int)> _tree() {
    final children = <String?, List<FolderEntry>>{};
    for (final folder in widget.index.folders) {
      children.putIfAbsent(folder.parentId, () => []).add(folder);
    }
    for (final list in children.values) {
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    final rows = <(FolderEntry, int)>[];
    final pending = [for (final f in (children[null] ?? const <FolderEntry>[]).reversed) (f, 0)];
    while (pending.isNotEmpty) {
      final (folder, depth) = pending.removeLast();
      rows.add((folder, depth));
      for (final child in (children[folder.id] ?? const <FolderEntry>[]).reversed) {
        pending.add((child, depth + 1));
      }
    }
    return rows;
  }

  bool get _allAlreadyThere =>
      widget.fileIds.every((id) => widget.index.files.firstWhere((f) => f.id == id).folderId == _target) &&
      widget.folderIds.every((id) => widget.index.folderById(id)!.parentId == _target);

  String get _targetLabel => _target == null ? widget.index.name : widget.index.folderById(_target!)!.name;

  Widget _node(IconData icon, String label, {required String? id, required int depth, required bool blocked, String? key}) {
    final selected = !blocked && _target == id;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: Key(key ?? 'move-target-$id'),
      onTap: blocked || busy ? null : () => setState(() => _target = id),
      child: Container(
        color: selected ? PjColors.of(context).accentSoft : null,
        padding: EdgeInsets.fromLTRB(12 + (depth > 12 ? 12 : depth) * 18.0, 8, 12, 8),
        child: Opacity(
          opacity: blocked ? 0.45 : 1,
          child: Row(
            spacing: 8,
            children: [
              Icon(icon, size: 18, color: selected ? scheme.primary : null),
              Expanded(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: selected ? FontWeight.w600 : null, color: selected ? scheme.primary : null))),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final index = widget.index;
    final what = describeItems(index, widget.fileIds, widget.folderIds);
    final count = widget.fileIds.length + widget.folderIds.length;
    final unchanged = _allAlreadyThere;
    return PjDialog(
      title: widget.pick ? 'Move $what to…' : 'Move $what to “$_targetLabel”?',
      content: [
        if (widget.pick) ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: DecoratedBox(
              decoration: BoxDecoration(border: Border.all(color: PjColors.of(context).border), borderRadius: BorderRadius.circular(8)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    _node(Icons.home_outlined, '${index.name} (top level)', id: null, depth: 0, blocked: false, key: 'move-target-top'),
                    for (final (folder, depth) in _tree()) _node(Icons.folder_outlined, folder.name, id: folder.id, depth: depth + 1, blocked: _blocked.contains(folder.id)),
                  ],
                ),
              ),
            ),
          ),
          if (widget.folderIds.isNotEmpty) const Muted("A folder can't be moved into itself or into a folder inside it."),
        ] else ...[
          SummaryBox(
            children: [
              for (final id in widget.folderIds)
                Row(spacing: 8, children: [const Icon(Icons.folder_outlined, size: 18), Expanded(child: Text(index.folderById(id)!.name, overflow: TextOverflow.ellipsis))]),
              for (final id in widget.fileIds) _fileRow(index.files.firstWhere((f) => f.id == id)),
            ],
          ),
          Muted('Tags stay as they are. Names that clash in “$_targetLabel” get a number added.'),
        ],
        ?errorNotice(),
      ],
      actions: [
        cancelButton(),
        confirmButton(
          widget.pick ? 'Move here' : 'Move ${plural(count, 'item')}',
          enabled: !unchanged,
          onConfirm: () async {
            final result = await AppScope.read(context).projects.moveItems(widget.projectId, fileIds: widget.fileIds, folderIds: widget.folderIds, targetFolderId: _target);
            widget.onMoved(result, _targetLabel);
          },
        ),
      ],
    );
  }

  Widget _fileRow(FileEntry file) => Row(
    spacing: 8,
    children: [
      Icon(fileKind(file.name).icon, size: 18),
      Expanded(child: Text(file.name, overflow: TextOverflow.ellipsis)),
      Muted(formatBytes(file.size)),
    ],
  );
}

/// "Delete the folder …?": counts everything inside, subfolders included.
class DeleteFolderDialog extends StatefulWidget {
  const DeleteFolderDialog({required this.projectId, required this.index, required this.folder, super.key});

  final String projectId;
  final ProjectIndex index;
  final FolderEntry folder;

  @override
  State<DeleteFolderDialog> createState() => _DeleteFolderDialogState();
}

class _DeleteFolderDialogState extends WriteDialogState<DeleteFolderDialog> {
  @override
  Widget build(BuildContext context) {
    final stats = widget.index.statsOf(widget.folder.id);
    final empty = stats.files == 0 && stats.folders == 0;
    Widget row(IconData icon, String label, String value) => Row(
      spacing: 8,
      children: [Icon(icon, size: 18), Expanded(child: Text(label)), Text(value, style: const TextStyle(fontWeight: FontWeight.w700))],
    );
    return PjDialog(
      title: 'Delete the folder “${widget.folder.name}”?',
      danger: true,
      content: [
        if (empty)
          const Text('This folder is empty.')
        else ...[
          SummaryBox(
            children: [
              row(Icons.description_outlined, 'Files inside', '${stats.files}'),
              row(Icons.folder_outlined, 'Folders inside', '${stats.folders}'),
              row(Icons.storage_outlined, 'Total size', formatBytes(stats.bytes)),
            ],
          ),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'The folder and the '),
                TextSpan(text: '${plural(stats.files, 'encrypted file')} ', style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: 'inside it, with their tags, are permanently deleted from ${widget.index.name}.'),
              ],
            ),
          ),
          const Muted("The originals on your device are not touched. This can't be undone."),
        ],
        ?errorNotice(),
      ],
      actions: [
        cancelButton(),
        confirmButton(
          stats.files > 0 ? 'Delete folder and ${plural(stats.files, 'file')}' : 'Delete folder',
          enabled: true,
          danger: true,
          onConfirm: () async {
            await AppScope.read(context).projects.deleteFolder(widget.projectId, widget.folder.id);
          },
        ),
      ],
    );
  }
}
