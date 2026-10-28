import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:portfolio_jockey/app/app_controller.dart';
import 'package:portfolio_jockey/app/theme.dart';
import 'package:portfolio_jockey/services/project_service.dart';
import 'package:portfolio_jockey/ui/common.dart';
import 'package:portfolio_jockey/ui/export/export_dialog.dart';
import 'package:portfolio_jockey/ui/export/readable_copy_dialog.dart';
import 'package:portfolio_jockey/ui/home/home_screen.dart';
import 'package:portfolio_jockey/ui/home/project_dialogs.dart';
import 'package:portfolio_jockey/ui/preview/edit_dialogs.dart';
import 'package:portfolio_jockey/ui/preview/preview_screen.dart';
import 'package:portfolio_jockey/ui/project/explorer.dart';
import 'package:portfolio_jockey/ui/project/file_dialogs.dart';
import 'package:portfolio_jockey/ui/project/folder_dialogs.dart';
import 'package:portfolio_jockey/ui/settings/settings_screen.dart';
import 'package:portfolio_jockey/ui/tags/tag_dialogs.dart';
import 'package:portfolio_jockey/vault/project_index.dart';

/// Which files the chips show.
sealed class _Filter {
  const _Filter();
}

final class _All extends _Filter {
  const _All();
}

final class _Untagged extends _Filter {
  const _Untagged();
}

final class _Tagged extends _Filter {
  const _Tagged(this.tag);

  final String tag;
}

/// One project: its files, tags and the file menu.
class ProjectScreen extends StatefulWidget {
  const ProjectScreen({required this.projectId, super.key});

  final String projectId;

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  ProjectIndex? _index;
  Uint8List? _cover;
  String? _loadError;
  _Filter _filter = const _All();
  final Set<String> _selected = {};
  bool _selecting = false;
  String? _anchor;

  /// The folder being looked at; null is the project's top level.
  String? _folderId;
  final _search = TextEditingController();

  ProjectService get _service => AppScope.read(context).projects;

  bool _isTagFilter(String tag) => switch (_filter) {
    _Tagged(tag: final current) => current == tag,
    _ => false,
  };

  /// Searching or filtering by tag lists matches from every folder, flat.
  bool get _isFlat => _search.text.trim().isNotEmpty || _filter is! _All;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    unawaited(_reload());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final controller = AppScope.read(context);
    if (controller.stage != AppStage.unlocked) {
      return; // Locked while a preview was open: this screen is going away.
    }
    final service = controller.projects;
    try {
      final index = await service.readProject(widget.projectId);
      final cover = await service.readCover(widget.projectId, index);
      if (mounted) {
        setState(() {
          _index = index;
          _cover = cover;
          _loadError = null;
          _selected.removeWhere((id) => !index.files.any((f) => f.id == id) && index.folderById(id) == null);
          if (_folderId != null && index.folderById(_folderId!) == null) {
            _folderId = null;
          }
          if (_filter case _Tagged(:final tag) when !index.tags.contains(tag)) {
            _filter = const _All();
          }
        });
      }
    } on Object catch (e) {
      if (!controller.isCurrent(service)) {
        return; // Locked during the read, which then failed: nothing to show.
      }
      if (e is! Exception) {
        rethrow;
      }
      if (mounted) {
        setState(() => _loadError = 'This project could not be opened: $e');
      }
    }
  }

  Future<bool> _show(Widget dialog) async {
    final changed = await showDialog<bool>(context: context, builder: (_) => dialog) ?? false;
    if (changed) {
      if (dialog is DeleteProjectDialog) {
        if (mounted) {
          Navigator.of(context).pop();
        }
      } else {
        await _reload();
      }
    }
    return changed;
  }

  Future<void> _addFiles(ProjectIndex index) async {
    final paths = await AppScope.read(context).filePicker.pickFiles();
    if (paths.isEmpty || !mounted) {
      return;
    }
    final request = await showDialog<AddFilesRequest>(
      context: context,
      builder: (_) => AddFilesDialog(index: index, paths: paths, where: _folderId == null ? null : folderPathLabel(index, _folderId)),
    );
    if (request == null || !mounted) {
      return;
    }
    final result = await showDialog<AddResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddProgressDialog(projectId: widget.projectId, paths: paths, request: request, folderId: _folderId),
    );
    await _reload();
    if (result != null && result.failed.isNotEmpty && mounted) {
      await showDialog<void>(context: context, builder: (_) => AddFailuresDialog(result: result));
    }
  }

  bool _matchesFilter(FileEntry file) => switch (_filter) {
    _All() => true,
    _Untagged() => file.tags.isEmpty,
    _Tagged(:final tag) => file.tags.contains(tag),
  };

  /// What the screen lists, in order: the current folder's contents, or (when
  /// searching or filtering by tag) matches from the whole project.
  List<ExplorerItem> _shownItems(ProjectIndex index) {
    final prefs = AppScope.read(context).explorer;
    final stats = index.allFolderStats();
    final query = _search.text.trim();
    final flat = _isFlat;
    final Iterable<FileEntry> files = flat ? index.files.where((f) => _matchesFilter(f) && nameMatches(f.name, query)) : index.filesIn(_folderId);
    final Iterable<FolderEntry> folders = flat ? (_filter is _All ? index.folders.where((f) => nameMatches(f.name, query)) : const []) : index.foldersIn(_folderId);
    return sortItems([for (final f in folders) ExplorerItem.folder(f, stats[f.id]!), for (final f in files) ExplorerItem.file(f)], prefs.sortKey, ascending: prefs.ascending);
  }

  void _openFolder(String? id) => setState(() {
    _folderId = id;
    _selected.clear();
    _anchor = null;
    _search.clear();
    _filter = const _All();
  });

  void _tap(ExplorerItem item, List<ExplorerItem> shown) {
    final keys = HardwareKeyboard.instance;
    if (keys.isShiftPressed && _anchor != null) {
      final from = shown.indexWhere((i) => i.id == _anchor);
      final to = shown.indexWhere((i) => i.id == item.id);
      if (from >= 0 && to >= 0) {
        setState(() => _selected.addAll([for (final i in shown.sublist(from < to ? from : to, (from < to ? to : from) + 1)) i.id]));
        return;
      }
    }
    if (_selecting || keys.isControlPressed || _selected.isNotEmpty) {
      setState(() {
        _selected.contains(item.id) ? _selected.remove(item.id) : _selected.add(item.id);
        _anchor = item.id;
      });
      return;
    }
    // A single click opens a file's preview, or a folder, straight away (PM
    // decision, 2026-10-23); the menu is on right-click or a long press.
    if (item.isFolder) {
      _openFolder(item.id);
    } else {
      unawaited(_preview(item.file!));
    }
  }

  /// Opens the preview, with previous/next through the files the screen lists.
  /// Reloads afterwards: an edit saved meanwhile changes sizes.
  Future<void> _preview(FileEntry file) async {
    final index = _index!;
    final visible = [for (final i in _shownItems(index)) if (!i.isFolder) i.file!];
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PreviewScreen(
          projectId: widget.projectId,
          projectName: index.name,
          files: visible,
          initial: visible.indexOf(file).clamp(0, visible.length - 1),
          onFileMenu: (menuContext, file, position) => unawaited(_openFileMenu(file, position, fromPreview: true, menuContext: menuContext)),
        ),
      ),
    );
    await _reload();
  }

  // ---- Dragging files and folders into folders ----

  DragItems _payload(ExplorerItem item) {
    if (_selected.contains(item.id)) {
      final index = _index!;
      return DragItems(
        fileIds: [for (final f in index.files) if (_selected.contains(f.id)) f.id],
        folderIds: [for (final f in index.folders) if (_selected.contains(f.id)) f.id],
      );
    }
    return item.isFolder ? DragItems(folderIds: [item.id]) : DragItems(fileIds: [item.id]);
  }

  /// Whether dropping [items] on [target] (null is the top level) would move something, legally.
  bool _canDrop(DragItems items, String? target) {
    final index = _index!;
    if (target != null && index.folderById(target) == null) {
      return false;
    }
    if (items.folderIds.any((id) => !index.canMoveFolder(id, target))) {
      return false;
    }
    return items.folderIds.any((id) => index.folderById(id)?.parentId != target) || items.fileIds.any((id) => index.files.any((f) => f.id == id && f.folderId != target));
  }

  Widget _dragSource(ExplorerItem item, Widget child) {
    final payload = _payload(item);
    return Draggable<DragItems>(
      data: payload,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _DragFeedback(label: item.name, count: payload.count),
      childWhenDragging: Opacity(opacity: 0.45, child: child),
      child: child,
    );
  }

  Widget _dropTarget(String? folderId, Widget Function(bool hovering) build) => DragTarget<DragItems>(
    onWillAcceptWithDetails: (details) => _canDrop(details.data, folderId),
    onAcceptWithDetails: (details) => unawaited(_confirmMove(details.data, folderId)),
    builder: (context, candidates, _) => build(candidates.isNotEmpty),
  );

  /// A drop only asks; nothing moves until the dialog is confirmed.
  Future<void> _confirmMove(DragItems items, String? target) async {
    final done =
        await showDialog<bool>(
          context: context,
          builder: (_) => MoveItemsDialog(projectId: widget.projectId, index: _index!, fileIds: items.fileIds, folderIds: items.folderIds, targetFolderId: target, onMoved: _showMoved),
        ) ??
        false;
    if (done && mounted) {
      setState(_selected.clear);
      await _reload();
    }
  }

  void _showMoved(MoveResult result, String targetLabel) => showError(context, movedMessage(result, targetLabel));

  Future<void> _moveTo({required List<String> fileIds, required List<String> folderIds, bool closePreview = false}) async {
    final moved = await _show(MoveItemsDialog(projectId: widget.projectId, index: _index!, fileIds: fileIds, folderIds: folderIds, pick: true, targetFolderId: _folderId, onMoved: _showMoved));
    if (moved && mounted) {
      setState(_selected.clear);
      if (closePreview) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _deleteFolder(FolderEntry folder) async {
    final index = _index!;
    final stats = index.statsOf(folder.id);
    final done = await _show(DeleteFolderDialog(projectId: widget.projectId, index: index, folder: folder));
    if (done && mounted) {
      showError(context, stats.files > 0 ? '“${folder.name}” deleted, with ${plural(stats.files, 'file')}' : '“${folder.name}” deleted');
    }
  }

  void _sortBy(SortKey key) {
    final prefs = AppScope.read(context).explorer;
    setState(() {
      if (prefs.sortKey == key) {
        prefs.ascending = !prefs.ascending;
      } else {
        prefs
          ..sortKey = key
          ..ascending = true;
      }
    });
  }

  PopupMenuItem<VoidCallback> _menuItem(IconData icon, String label, VoidCallback? action, {bool danger = false, String? hint}) {
    final error = Theme.of(context).colorScheme.error;
    return PopupMenuItem(
      value: action,
      enabled: action != null,
      // Flexible text: the menu is briefly narrower while it animates open.
      child: Row(
        spacing: 10,
        children: [
          Icon(icon, size: 20, color: danger && action != null ? error : null),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: danger && action != null ? error : null),
            ),
          ),
          if (hint != null) Flexible(child: Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: PjColors.of(context).muted, fontSize: 12.5))),
        ],
      ),
    );
  }

  Future<void> _openFolderMenu(FolderEntry folder, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<VoidCallback>(
      context: context,
      constraints: const BoxConstraints(minWidth: 300, maxWidth: 380),
      position: RelativeRect.fromRect(position & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        PopupMenuItem(enabled: false, height: 32, child: Text('${folder.name} · folder', style: const TextStyle(fontWeight: FontWeight.w700))),
        _menuItem(Icons.folder_open_outlined, 'Open', () => _openFolder(folder.id)),
        _menuItem(Icons.edit_outlined, 'Rename…', () => _show(FolderNameDialog(projectId: widget.projectId, index: _index!, rename: folder))),
        _menuItem(Icons.drive_file_move_outline, 'Move to…', () => _moveTo(fileIds: const [], folderIds: [folder.id])),
        _menuItem(
          Icons.ios_share,
          'Export a readable copy…',
          () => showDialog<bool>(context: context, builder: (_) => ExportDialog(projects: [ProjectSummary(id: widget.projectId, index: _index!, cover: _cover)], folder: folder)),
        ),
        const PopupMenuDivider(),
        _menuItem(Icons.delete_outline, 'Delete folder…', () => _deleteFolder(folder), danger: true, hint: "and what's inside"),
      ],
    );
    action?.call();
  }

  Future<void> _showOriginalInFileManager(FileEntry file) async {
    final path = file.originalPath;
    if (path == null) {
      return;
    }
    try {
      await AppScope.read(context).edits.launcher.showFileInFolder(path);
    } on FileSystemException catch (e) {
      if (mounted) {
        showError(context, e.message);
      }
    }
  }

  Future<void> _openFileMenu(FileEntry file, Offset position, {bool fromPreview = false, BuildContext? menuContext}) async {
    final index = _index!;
    final originalThere = await _service.originalExists(file);
    if (!mounted) {
      return;
    }
    final flatpak = AppScope.read(context).edits.launcher.usesDesktopChooser;
    final activeContext = menuContext ?? context;
    if (!activeContext.mounted) {
      return;
    }
    final overlay = Overlay.of(activeContext).context.findRenderObject()! as RenderBox;
    final item = _menuItem;

    Future<void> delete(DeleteTarget target) async {
      final done = await _show(DeleteFileDialog(projectId: widget.projectId, projectName: index.name, file: file, target: target));
      if (done && mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(tapDismissibleSnackBar(messenger, Text(deletedMessage(target, file.name))));
        if (fromPreview && target != DeleteTarget.device) {
          Navigator.of(context).pop();
        }
      }
    }

    final action = await showMenu<VoidCallback>(
      context: activeContext,
      // Wide enough for the mockup's labels and their hints ("the original").
      constraints: const BoxConstraints(minWidth: 300, maxWidth: 380),
      position: RelativeRect.fromRect(position & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        PopupMenuItem(enabled: false, height: 32, child: Text(file.name, style: const TextStyle(fontWeight: FontWeight.w700))),
        item(Icons.visibility_outlined, 'Preview', fromPreview ? () {} : () => _preview(file)),
        if (_isFlat)
          item(Icons.folder_open_outlined, 'Show in folder', () {
            if (fromPreview) {
              Navigator.of(context).pop();
            }
            _openFolder(file.folderId);
          }),
        item(Icons.open_in_new, 'Edit in another app…', () => editInAnotherApp(context, projectId: widget.projectId, projectName: index.name, file: file)),
        item(Icons.sell_outlined, 'Edit tags…', () async {
          final changed = await _show(EditFileTagsDialog(projectId: widget.projectId, index: index, files: [file]));
          if (changed && fromPreview && mounted) {
            Navigator.of(context).pop();
          }
        }),
        item(Icons.edit_outlined, 'Rename…', () async {
          final changed = await _show(RenameFileDialog(projectId: widget.projectId, file: file));
          if (changed && fromPreview && mounted) {
            Navigator.of(context).pop();
          }
        }),
        item(Icons.drive_file_move_outline, 'Move to…', () => _moveTo(fileIds: [file.id], folderIds: const [], closePreview: fromPreview)),
        item(Icons.ios_share, 'Export a readable copy…', () => showDialog<bool>(context: context, builder: (_) => ReadableCopyDialog(projectId: widget.projectId, projectName: index.name, file: file))),
        const PopupMenuDivider(),
        if (flatpak)
          item(Icons.folder_open_outlined, 'Show original in file manager', originalThere ? () => _showOriginalInFileManager(file) : null, hint: 'the original')
        else
          item(Icons.delete_outline, 'Move to Trash', originalThere ? () => delete(DeleteTarget.device) : null, danger: true, hint: 'the original'),
        item(Icons.delete_outline, 'Delete from project', () => delete(DeleteTarget.project), danger: true, hint: 'the encrypted copy'),
        if (!flatpak)
          item(Icons.delete_outline, 'Trash original, delete copy', originalThere ? () => delete(DeleteTarget.both) : null, danger: true),
        if (!originalThere)
          PopupMenuItem(
            enabled: false,
            child: SizedBox(
              width: 340,
              child: Muted(
                file.originalPath == null
                  ? "The original's location isn't known, so it can't be ${flatpak ? 'shown in the file manager' : 'moved to the Trash'}. Only the project copy can be deleted."
                  : "The original is no longer at ${file.shownOriginal}, so it can't be ${flatpak ? 'shown in the file manager' : 'moved to the Trash'}. Only the project copy can be deleted.",
              ),
            ),
          ),
      ],
    );
    action?.call();
  }

  @override
  Widget build(BuildContext context) {
    final index = _index;
    if (index == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: _loadError == null ? const CircularProgressIndicator() : Notice(_loadError!, danger: true)),
      );
    }
    final shown = _shownItems(index);
    final untagged = index.files.where((f) => f.tags.isEmpty).length;
    final selectedFiles = index.files.where((f) => _selected.contains(f.id)).toList();
    final selectedFolders = index.folders.where((f) => _selected.contains(f.id)).map((f) => f.id).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(index.name),
        actions: [
          ProjectMenuButton(
            project: ProjectSummary(id: widget.projectId, index: index, cover: _cover),
            onAction: (dialog) => unawaited(_show(dialog)),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
              await _reload();
            },
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: withEditBanner(
        ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Wrap(
              spacing: 20,
              runSpacing: 16,
              children: [
                CoverView(name: index.name, image: _cover, height: 130, width: 200),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 8,
                    children: [
                      if (index.description.isNotEmpty) Text(index.description, style: TextStyle(color: PjColors.of(context).muted)),
                      Muted('${plural(index.files.length, 'file')} · ${formatBytes(index.totalSize)} · encrypted'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(onPressed: () => _addFiles(index), icon: const Icon(Icons.add), label: Text(_folderId == null ? 'Add files' : 'Add files here')),
                          OutlinedButton.icon(
                            onPressed: () => _show(ManageTagsDialog(projectId: widget.projectId, index: index)),
                            icon: const Icon(Icons.sell_outlined),
                            label: const Text('Manage tags'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => setState(() {
                              _selecting = !_selecting;
                              if (!_selecting) {
                                _selected.clear();
                              }
                            }),
                            icon: Icon(_selecting ? Icons.close : Icons.checklist),
                            label: Text(_selecting ? 'Done selecting' : 'Select'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TagChip('All ${index.files.length}', check: false, selected: _filter is _All, onTap: () => setState(() => _filter = const _All())),
                for (final tag in index.tags)
                  TagChip(
                    '$tag ${index.files.where((f) => f.tags.contains(tag)).length}',
                    check: false,
                    selected: _isTagFilter(tag),
                    onTap: () => setState(() => _filter = _Tagged(tag)),
                  ),
                TagChip('Untagged $untagged', check: false, selected: _filter is _Untagged, onTap: () => setState(() => _filter = const _Untagged())),
              ],
            ),
            const SizedBox(height: 14),
            _toolbar(index),
            if (_selected.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    spacing: 8,
                    children: [
                      Text('${_selected.length} selected', style: const TextStyle(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: selectedFiles.isEmpty ? null : () => _show(EditFileTagsDialog(projectId: widget.projectId, index: index, files: selectedFiles)),
                        icon: const Icon(Icons.sell_outlined),
                        label: const Text('Edit tags…'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _moveTo(fileIds: [for (final f in selectedFiles) f.id], folderIds: selectedFolders),
                        icon: const Icon(Icons.drive_file_move_outline),
                        label: const Text('Move to…'),
                      ),
                      TextButton(onPressed: () => setState(_selected.clear), child: const Text('Clear')),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_isFlat) _resultsSummary(shown) else _crumbs(index),
            const SizedBox(height: 14),
            ..._content(index, shown),
          ],
        ),
      ),
    );
  }

  Widget _toolbar(ProjectIndex index) {
    final prefs = AppScope.read(context).explorer;
    final search = TextField(
      controller: _search,
      key: const Key('project-search'),
      decoration: InputDecoration(
        hintText: 'Search this whole project',
        isDense: true,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _search.text.isEmpty ? null : IconButton(tooltip: 'Clear search', onPressed: _search.clear, icon: const Icon(Icons.close)),
      ),
    );
    Widget checked(bool on, String label, {String? hint}) => Row(
      spacing: 8,
      children: [
        SizedBox(width: 20, child: on ? const Icon(Icons.check, size: 18) : null),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        if (hint != null) Flexible(child: Muted(hint)),
      ],
    );
    final sort = PopupMenuButton<Object>(
      tooltip: 'Sort',
      constraints: const BoxConstraints(minWidth: 260),
      position: PopupMenuPosition.under,
      onSelected: (value) => setState(() {
        if (value is SortKey) {
          prefs.sortKey = value;
        } else if (value is bool) {
          prefs.ascending = value;
        }
      }),
      itemBuilder: (_) => [
        const PopupMenuItem<Object>(enabled: false, height: 32, child: Text('Sort by', style: TextStyle(fontWeight: FontWeight.w700))),
        for (final key in SortKey.values) PopupMenuItem<Object>(value: key, child: checked(prefs.sortKey == key, _sortLabel(key))),
        const PopupMenuDivider(),
        PopupMenuItem<Object>(value: true, child: checked(prefs.ascending, 'Ascending', hint: _directionHint(prefs.sortKey, ascending: true))),
        PopupMenuItem<Object>(value: false, child: checked(!prefs.ascending, 'Descending', hint: _directionHint(prefs.sortKey, ascending: false))),
      ],
      // The button only draws; the menu button above handles the tap.
      child: IgnorePointer(
        child: OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.swap_vert),
          label: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [Text(_sortLabel(prefs.sortKey)), Icon(prefs.ascending ? Icons.arrow_upward : Icons.arrow_downward, size: 14)]),
        ),
      ),
    );
    final view = SegmentedButton<bool>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: false, icon: Icon(Icons.grid_view), tooltip: 'Grid view'),
        ButtonSegment(value: true, icon: Icon(Icons.view_list), tooltip: 'List view'),
      ],
      selected: {prefs.listView},
      onSelectionChanged: (choice) => setState(() => prefs.listView = choice.single),
    );
    final newFolder = OutlinedButton.icon(
      onPressed: () => _show(FolderNameDialog(projectId: widget.projectId, index: index, parentId: _folderId)),
      icon: const Icon(Icons.create_new_folder_outlined),
      label: const Text('New folder'),
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 640
          ? Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [SizedBox(width: constraints.maxWidth, child: search), sort, view, newFolder])
          : Row(spacing: 8, children: [Expanded(child: search), sort, view, newFolder]),
    );
  }

  static String _sortLabel(SortKey key) => switch (key) {
    SortKey.name => 'Name',
    SortKey.size => 'Size',
    SortKey.date => 'Date added',
  };

  static String _directionHint(SortKey key, {required bool ascending}) => switch (key) {
    SortKey.name => ascending ? 'A to Z' : 'Z to A',
    SortKey.size => ascending ? 'small to large' : 'large to small',
    SortKey.date => ascending ? 'old to new' : 'new to old',
  };

  Widget _resultsSummary(List<ExplorerItem> shown) {
    final query = _search.text.trim();
    return Muted(
      query.isNotEmpty
          ? '${plural(shown.length, 'result')} for “$query” in the whole project'
          : switch (_filter) {
              _Tagged(:final tag) => '${plural(shown.length, 'file')} tagged “$tag” in the whole project',
              _ => '${plural(shown.length, 'untagged file')} in the whole project',
            },
    );
  }

  /// The path to the current folder. Each part opens that folder, and takes drops.
  Widget _crumbs(ProjectIndex index) {
    final path = index.pathTo(_folderId);
    Widget crumb(String label, String? id, {required bool here}) =>
        _dropTarget(id, (hovering) => _Crumb(label: label, here: here, hovering: hovering, onTap: here ? null : () => _openFolder(id)));
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        crumb(index.name, null, here: path.isEmpty),
        for (final folder in path) ...[const Icon(Icons.chevron_right, size: 18), crumb(folder.name, folder.id, here: folder.id == _folderId)],
      ],
    );
  }

  List<Widget> _content(ProjectIndex index, List<ExplorerItem> shown) {
    if (index.files.isEmpty && index.folders.isEmpty) {
      return const [Padding(padding: EdgeInsets.all(32), child: Center(child: Muted('No files yet. Use “Add files” to encrypt files into this project.', small: false)))];
    }
    if (shown.isEmpty) {
      final query = _search.text.trim();
      return [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: _isFlat
                ? Muted(query.isEmpty ? 'No files match this filter.' : 'Nothing matches “$query”.', small: false)
                : const Column(
                    spacing: 6,
                    children: [
                      Icon(Icons.folder_open_outlined, size: 40),
                      Text('This folder is empty', style: TextStyle(fontWeight: FontWeight.w700)),
                      Muted('Add files here, or drag files in from another folder.'),
                    ],
                  ),
          ),
        ),
      ];
    }
    return AppScope.read(context).explorer.listView ? [_listContent(index, shown)] : _gridContent(index, shown);
  }

  List<Widget> _gridContent(ProjectIndex index, List<ExplorerItem> shown) {
    final folders = [for (final i in shown) if (i.isFolder) i];
    final files = [for (final i in shown) if (!i.isFolder) i];
    final flat = _isFlat;
    return [
      if (folders.isNotEmpty) ...[
        const _SectionLabel('Folders'),
        const SizedBox(height: 8),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 260, mainAxisExtent: 64, mainAxisSpacing: 10, crossAxisSpacing: 10),
          children: [
            for (final item in folders)
              _dragSource(
                item,
                _dropTarget(
                  item.id,
                  (hovering) => _FolderCard(
                    item: item,
                    selected: _selected.contains(item.id),
                    hovering: hovering,
                    path: flat ? folderPathLabel(index, item.parentId) : null,
                    onTap: () => _tap(item, shown),
                    onMenu: (position) => unawaited(_openFolderMenu(item.folder!, position)),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
      ],
      if (files.isNotEmpty) ...[
        if (folders.isNotEmpty) ...[const _SectionLabel('Files'), const SizedBox(height: 8)],
        GridView.extent(
          maxCrossAxisExtent: 190,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: flat ? 0.74 : 0.82,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final item in files)
              _dragSource(
                item,
                _FileCard(
                  file: item.file!,
                  selected: _selected.contains(item.id),
                  path: flat ? folderPathLabel(index, item.parentId) : null,
                  onTap: () => _tap(item, shown),
                  onMenu: (position) => unawaited(_openFileMenu(item.file!, position)),
                ),
              ),
          ],
        ),
      ],
    ];
  }

  Widget _listContent(ProjectIndex index, List<ExplorerItem> shown) {
    final prefs = AppScope.read(context).explorer;
    final flat = _isFlat;
    return LayoutBuilder(
      builder: (context, constraints) {
        final showDate = constraints.maxWidth >= 560;
        Widget row(ExplorerItem item) {
          Widget build(bool hovering) => _ListRow(
            item: item,
            selected: _selected.contains(item.id),
            hovering: hovering,
            showDate: showDate,
            path: flat ? folderPathLabel(index, item.parentId) : null,
            onTap: () => _tap(item, shown),
            onMenu: (position) => unawaited(item.isFolder ? _openFolderMenu(item.folder!, position) : _openFileMenu(item.file!, position)),
          );
          return _dragSource(item, item.isFolder ? _dropTarget(item.id, build) : build(false));
        }

        return Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _ListHeader(sortKey: prefs.sortKey, ascending: prefs.ascending, showDate: showDate, onSort: _sortBy),
              for (final item in shown) row(item),
            ],
          ),
        );
      },
    );
  }
}

class _FileCard extends StatelessWidget {
  const _FileCard({required this.file, required this.selected, required this.onTap, required this.onMenu, this.path});

  final FileEntry file;
  final bool selected;

  /// Where the file is, when results come from several folders.
  final String? path;
  final VoidCallback onTap;
  final void Function(Offset position) onMenu;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onSecondaryTapUp: (d) => onMenu(d.globalPosition),
      onLongPressStart: (d) => onMenu(d.globalPosition),
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: selected
            ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: scheme.primary, width: 2))
            : null,
        // No double-tap handler: it made every single click wait about 0.3 s
        // to rule out a double click.
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 6,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      TypeBadge(fileName: file.name),
                      if (selected) Positioned(top: 4, right: 4, child: Icon(Icons.check_circle, color: scheme.primary)),
                    ],
                  ),
                ),
                Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                if (path != null) Text(path!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: PjColors.of(context).muted)),
                Wrap(spacing: 4, runSpacing: 4, children: [for (final tag in file.tags) TagChip(tag, small: true)]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: PjColors.of(context).muted));
}

/// A folder in the grid. Takes drops: [hovering] shows it as the target.
class _FolderCard extends StatelessWidget {
  const _FolderCard({required this.item, required this.selected, required this.hovering, required this.onTap, required this.onMenu, this.path});

  final ExplorerItem item;
  final bool selected;
  final bool hovering;
  final String? path;
  final VoidCallback onTap;
  final void Function(Offset position) onMenu;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extra = PjColors.of(context);
    final stats = item.stats!;
    return GestureDetector(
      onSecondaryTapUp: (d) => onMenu(d.globalPosition),
      onLongPressStart: (d) => onMenu(d.globalPosition),
      child: Card(
        clipBehavior: Clip.antiAlias,
        color: hovering ? extra.accentSoft : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: hovering || selected ? BorderSide(color: scheme.primary, width: 2) : BorderSide(color: extra.border),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              spacing: 10,
              children: [
                Icon(selected ? Icons.check_circle : Icons.folder, size: 28, color: scheme.primary),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      Text(
                        path ?? '${plural(stats.files, 'file')} · ${formatBytes(stats.bytes)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: extra.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The column headings of the list view; each sorts by its column.
class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.sortKey, required this.ascending, required this.showDate, required this.onSort});

  final SortKey sortKey;
  final bool ascending;
  final bool showDate;
  final void Function(SortKey key) onSort;

  @override
  Widget build(BuildContext context) {
    final extra = PjColors.of(context);
    Widget heading(String label, SortKey key) {
      final active = sortKey == key;
      return InkWell(
        onTap: () => onSort(key),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: active ? Theme.of(context).colorScheme.primary : extra.muted)),
            if (active) Icon(ascending ? Icons.arrow_upward : Icons.arrow_downward, size: 13, color: Theme.of(context).colorScheme.primary),
          ],
        ),
      );
    }

    return Container(
      color: extra.surface2,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        spacing: 12,
        children: [
          Expanded(child: Align(alignment: Alignment.centerLeft, child: heading('Name', SortKey.name))),
          SizedBox(width: 100, child: Align(alignment: Alignment.centerLeft, child: heading('Size', SortKey.size))),
          if (showDate) SizedBox(width: 130, child: Align(alignment: Alignment.centerLeft, child: heading('Date added', SortKey.date))),
        ],
      ),
    );
  }
}

/// One folder or file in the list view.
class _ListRow extends StatelessWidget {
  const _ListRow({required this.item, required this.selected, required this.hovering, required this.showDate, required this.onTap, required this.onMenu, this.path});

  final ExplorerItem item;
  final bool selected;
  final bool hovering;
  final bool showDate;
  final String? path;
  final VoidCallback onTap;
  final void Function(Offset position) onMenu;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extra = PjColors.of(context);
    final icon = item.isFolder ? Icons.folder : fileKind(item.name).icon;
    final color = item.isFolder ? scheme.primary : fileKind(item.name).color;
    return GestureDetector(
      onSecondaryTapUp: (d) => onMenu(d.globalPosition),
      onLongPressStart: (d) => onMenu(d.globalPosition),
      child: Material(
        color: hovering || selected ? extra.accentSoft : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: extra.border), left: hovering ? BorderSide(color: scheme.primary, width: 3) : BorderSide.none),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              spacing: 12,
              children: [
                Expanded(
                  child: Row(
                    spacing: 10,
                    children: [
                      Icon(selected ? Icons.check_circle : icon, size: 22, color: selected ? scheme.primary : color),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (path != null) Text(path!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: extra.muted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 100, child: Text(formatBytes(item.size), style: TextStyle(fontSize: 13, color: extra.muted))),
                if (showDate) SizedBox(width: 130, child: Text(formatDate(item.date), style: TextStyle(fontSize: 13, color: extra.muted))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One part of the path above the files. Takes drops: [hovering] shows it as the target.
class _Crumb extends StatelessWidget {
  const _Crumb({required this.label, required this.here, required this.hovering, required this.onTap});

  final String label;
  final bool here;
  final bool hovering;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: hovering ? PjColors.of(context).accentSoft : Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: hovering ? BorderSide(color: scheme.primary, width: 2) : BorderSide.none),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(label, style: TextStyle(fontWeight: here ? FontWeight.w700 : null, color: here ? null : PjColors.of(context).muted)),
        ),
      ),
    );
  }
}

/// What follows the pointer while dragging.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 4,
      color: scheme.surface,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(border: Border.all(color: scheme.primary), borderRadius: BorderRadius.circular(10)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
            if (count > 1)
              DecoratedBox(
                decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(999)),
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1), child: Text('$count', style: TextStyle(color: scheme.onPrimary, fontSize: 12))),
              ),
          ],
        ),
      ),
    );
  }
}
