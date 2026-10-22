import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:portfolio_jockey/app/theme.dart';
import 'package:portfolio_jockey/services/project_service.dart';
import 'package:portfolio_jockey/ui/common.dart';
import 'package:portfolio_jockey/ui/home/home_screen.dart';
import 'package:portfolio_jockey/ui/home/project_dialogs.dart';
import 'package:portfolio_jockey/ui/project/file_dialogs.dart';
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

  ProjectService get _service => AppScope.read(context).projects;

  bool _isTagFilter(String tag) => switch (_filter) {
    _Tagged(tag: final current) => current == tag,
    _ => false,
  };

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final index = await _service.readProject(widget.projectId);
      final cover = await _service.readCover(widget.projectId, index);
      if (mounted) {
        setState(() {
          _index = index;
          _cover = cover;
          _loadError = null;
          _selected.removeWhere((id) => !index.files.any((f) => f.id == id));
          if (_filter case _Tagged(:final tag) when !index.tags.contains(tag)) {
            _filter = const _All();
          }
        });
      }
    } on Exception catch (e) {
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
    final request = await showDialog<AddFilesRequest>(context: context, builder: (_) => AddFilesDialog(index: index, paths: paths));
    if (request == null || !mounted) {
      return;
    }
    final result = await showDialog<AddResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddProgressDialog(projectId: widget.projectId, paths: paths, request: request),
    );
    await _reload();
    if (result != null && result.failed.isNotEmpty && mounted) {
      await showDialog<void>(context: context, builder: (_) => AddFailuresDialog(result: result));
    }
  }

  List<FileEntry> _visible(ProjectIndex index) => switch (_filter) {
    _All() => index.files,
    _Untagged() => index.files.where((f) => f.tags.isEmpty).toList(),
    _Tagged(:final tag) => index.files.where((f) => f.tags.contains(tag)).toList(),
  };

  void _tap(FileEntry file, List<FileEntry> visible, Offset position) {
    final keys = HardwareKeyboard.instance;
    if (keys.isShiftPressed && _anchor != null) {
      final from = visible.indexWhere((f) => f.id == _anchor);
      final to = visible.indexWhere((f) => f.id == file.id);
      if (from >= 0 && to >= 0) {
        setState(() => _selected.addAll([for (final f in visible.sublist(from < to ? from : to, (from < to ? to : from) + 1)) f.id]));
        return;
      }
    }
    if (_selecting || keys.isControlPressed || _selected.isNotEmpty) {
      setState(() {
        _selected.contains(file.id) ? _selected.remove(file.id) : _selected.add(file.id);
        _anchor = file.id;
      });
      return;
    }
    unawaited(_openFileMenu(file, position));
  }

  Future<void> _openFileMenu(FileEntry file, Offset position) async {
    final index = _index!;
    final originalThere = await _service.originalExists(file);
    if (!mounted) {
      return;
    }
    final error = Theme.of(context).colorScheme.error;
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    PopupMenuItem<VoidCallback> item(IconData icon, String label, VoidCallback? action, {bool danger = false, String? hint}) => PopupMenuItem(
      value: action,
      enabled: action != null,
      child: Row(
        spacing: 10,
        children: [
          Icon(icon, size: 20, color: danger && action != null ? error : null),
          Text(label, style: TextStyle(color: danger && action != null ? error : null)),
          if (hint != null) Muted(hint),
        ],
      ),
    );
    PopupMenuItem<VoidCallback> later(IconData icon, String label) =>
        PopupMenuItem(enabled: false, child: comingSoon(Row(mainAxisSize: MainAxisSize.min, spacing: 10, children: [Icon(icon, size: 20), Text(label)])));

    Future<void> delete(DeleteTarget target) =>
        _show(DeleteFileDialog(projectId: widget.projectId, projectName: index.name, file: file, target: target));

    final action = await showMenu<VoidCallback>(
      context: context,
      // Wide enough for the mockup's labels and their hints ("the original").
      constraints: const BoxConstraints(minWidth: 300, maxWidth: 380),
      position: RelativeRect.fromRect(position & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        PopupMenuItem(enabled: false, height: 32, child: Text(file.name, style: const TextStyle(fontWeight: FontWeight.w700))),
        later(Icons.visibility_outlined, 'Preview'),
        later(Icons.open_in_new, 'Edit in another app…'),
        item(Icons.sell_outlined, 'Edit tags…', () => _show(EditFileTagsDialog(projectId: widget.projectId, index: index, files: [file]))),
        item(Icons.edit_outlined, 'Rename…', () => _show(RenameFileDialog(projectId: widget.projectId, file: file))),
        later(Icons.ios_share, 'Export a readable copy…'),
        const PopupMenuDivider(),
        item(Icons.delete_outline, 'Delete from device', originalThere ? () => delete(DeleteTarget.device) : null, danger: true, hint: 'the original'),
        item(Icons.delete_outline, 'Delete from project', () => delete(DeleteTarget.project), danger: true, hint: 'the encrypted copy'),
        item(Icons.delete_outline, 'Delete from both', originalThere ? () => delete(DeleteTarget.both) : null, danger: true),
        if (!originalThere)
          PopupMenuItem(
            enabled: false,
            child: SizedBox(
              width: 340,
              child: Muted(
                file.originalPath == null
                    ? "The original's location isn't known, so only the project copy can be deleted."
                    : 'The original is no longer at ${file.originalPath}, so only the project copy can be deleted.',
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
    final visible = _visible(index);
    final untagged = index.files.where((f) => f.tags.isEmpty).length;
    final selectedFiles = index.files.where((f) => _selected.contains(f.id)).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(index.name),
        actions: [
          ProjectMenuButton(
            project: ProjectSummary(id: widget.projectId, index: index, cover: _cover),
            onAction: (dialog) => unawaited(_show(dialog)),
          ),
          comingSoon(const IconButton(onPressed: null, icon: Icon(Icons.settings_outlined))),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
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
                        FilledButton.icon(onPressed: () => _addFiles(index), icon: const Icon(Icons.add), label: const Text('Add files')),
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
                      onPressed: () => _show(EditFileTagsDialog(projectId: widget.projectId, index: index, files: selectedFiles)),
                      icon: const Icon(Icons.sell_outlined),
                      label: const Text('Edit tags…'),
                    ),
                    TextButton(onPressed: () => setState(_selected.clear), child: const Text('Clear')),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (index.files.isEmpty)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: Muted('No files yet. Use “Add files” to encrypt files into this project.', small: false)))
          else if (visible.isEmpty)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: Muted('No files match this filter.', small: false)))
          else
            GridView.extent(
              maxCrossAxisExtent: 190,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.82,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final file in visible)
                  _FileCard(
                    file: file,
                    selected: _selected.contains(file.id),
                    onTap: (position) => _tap(file, visible, position),
                    onMenu: (position) => unawaited(_openFileMenu(file, position)),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _FileCard extends StatelessWidget {
  const _FileCard({required this.file, required this.selected, required this.onTap, required this.onMenu});

  final FileEntry file;
  final bool selected;
  final void Function(Offset position) onTap;
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
        child: InkWell(
          onTapUp: (d) => onTap(d.globalPosition),
          onTap: () {},
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
                Wrap(spacing: 4, runSpacing: 4, children: [for (final tag in file.tags) TagChip(tag, small: true)]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
