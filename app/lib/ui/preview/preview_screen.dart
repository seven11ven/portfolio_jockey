import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:portfolio_jockey/app/theme.dart';
import 'package:portfolio_jockey/services/private_folder.dart';
import 'package:portfolio_jockey/services/project_service.dart';
import 'package:portfolio_jockey/ui/common.dart';
import 'package:portfolio_jockey/ui/export/readable_copy_dialog.dart';
import 'package:portfolio_jockey/ui/preview/edit_dialogs.dart';
import 'package:portfolio_jockey/ui/preview/preview_views.dart';
import 'package:portfolio_jockey/vault/project_index.dart';

/// Scenes 1, 2, 6 and 7: one file of a project, with previous/next through
/// [files] (the project screen's current filter) and a details panel.
///
/// Images, text, Markdown and PDF are decrypted fully into memory before
/// anything is shown; audio and video play from a memory-only copy. Nothing
/// readable is written to disk.
class PreviewScreen extends StatefulWidget {
  const PreviewScreen({required this.projectId, required this.projectName, required this.files, required this.initial, super.key});

  final String projectId;
  final String projectName;
  final List<FileEntry> files;
  final int initial;

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  late int _at = widget.initial;
  Object? _content; // Uint8List, File (media copy), or an error message String.
  String? _detail;
  int _loadToken = 0;

  FileEntry get _file => widget.files[_at];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    final file = _file;
    final kind = previewKind(file.name);
    final controller = AppScope.read(context);
    setState(() {
      _content = null;
      _detail = null;
    });
    Object content;
    try {
      content = switch (kind) {
        PreviewKind.none => "This type of file can't be previewed. Use “Edit in another app” to open it.",
        PreviewKind.media => await controller.edits.mediaCopy(controller.projects, widget.projectId, file),
        _ => await controller.projects.readFile(widget.projectId, file, maxBytes: kind.maxBytes),
      };
    } on TooLargeToPreview catch (e) {
      content = 'This file is too large to preview (${formatBytes(e.size)}; the limit is ${formatBytes(e.limit)}). Use “Edit in another app” to open it.';
    } on NoPrivateFolder catch (e) {
      content = "This file can't be played: there's no private memory-only folder on this system ($e), so a readable copy can't be made safely.";
    } on Exception catch (e) {
      content = "This file can't be shown. It may be damaged. ($e)";
    }
    if (!mounted || token != _loadToken) {
      await _drop(content);
      return;
    }
    setState(() => _content = content);
  }

  /// Wipes content that will never be shown.
  static Future<void> _drop(Object content) async {
    if (content is Uint8List) {
      content.fillRange(0, content.length, 0);
    } else if (content is File) {
      await PrivateFolders.wipe(content.parent);
    }
  }

  void _go(int delta) {
    final next = _at + delta;
    if (next < 0 || next >= widget.files.length) {
      return;
    }
    setState(() => _at = next);
    unawaited(_load());
  }

  void _setDetail(String detail) {
    if (mounted && _detail != detail) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _detail = detail);
        }
      });
    }
  }

  Future<void> _edit() => editInAnotherApp(context, projectId: widget.projectId, projectName: widget.projectName, file: _file);

  Widget _stage() {
    final file = _file;
    return switch (_content) {
      null => const Center(child: CircularProgressIndicator()),
      final String message => Center(child: Padding(padding: const EdgeInsets.all(24), child: Notice(message))),
      final File copy => MediaPreview(key: ValueKey(copy.path), copy: copy, onDuration: (d) => _setDetail(formatDuration(d))),
      final Uint8List bytes => switch (previewKind(file.name)) {
        PreviewKind.image => ImagePreview(key: ValueKey(file.id), bytes: bytes, onSize: (w, h) => _setDetail('$w × $h')),
        PreviewKind.markdown => MarkdownPreview(key: ValueKey(file.id), bytes: bytes),
        PreviewKind.pdf => PdfPreview(key: ValueKey(file.id), bytes: bytes, onPageCount: (n) => _setDetail(plural(n, 'page'))),
        _ => TextPreview(key: ValueKey(file.id), bytes: bytes),
      },
      _ => const SizedBox.shrink(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    final colors = PjColors.of(context);
    final details = _Details(file: file, detail: _detail, onEdit: _edit);
    return Scaffold(
      appBar: AppBar(
        title: Text(file.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(tooltip: 'Previous file', onPressed: _at > 0 ? () => _go(-1) : null, icon: const Icon(Icons.chevron_left)),
          IconButton(tooltip: 'Next file', onPressed: _at < widget.files.length - 1 ? () => _go(1) : null, icon: const Icon(Icons.chevron_right)),
          PopupMenuButton<VoidCallback>(
            tooltip: 'More',
            icon: const Icon(Icons.more_horiz),
            onSelected: (action) => action(),
            itemBuilder: (_) => [
              PopupMenuItem(value: () => unawaited(_edit()), child: const Row(spacing: 10, children: [Icon(Icons.open_in_new, size: 20), Flexible(child: Text('Edit in another app…', maxLines: 1, overflow: TextOverflow.ellipsis))])),
              PopupMenuItem(
                value: () => unawaited(
                  showDialog<bool>(
                    context: context,
                    builder: (_) => ReadableCopyDialog(projectId: widget.projectId, projectName: widget.projectName, file: _file),
                  ),
                ),
                child: const Row(spacing: 10, children: [Icon(Icons.ios_share, size: 20), Flexible(child: Text('Export a readable copy…', maxLines: 1, overflow: TextOverflow.ellipsis))]),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: withEditBanner(
        LayoutBuilder(
          builder: (context, constraints) {
            final stage = ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ColoredBox(color: colors.surface2, child: _stage()),
            );
            if (constraints.maxWidth >= 760) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 16,
                  children: [
                    Expanded(child: stage),
                    SizedBox(width: 280, child: Card(child: SingleChildScrollView(child: details))),
                  ],
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SizedBox(height: constraints.maxHeight * 0.62, child: stage),
                const SizedBox(height: 12),
                Card(child: details),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.file, required this.detail, required this.onEdit});

  final FileEntry file;
  final String? detail;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, Widget value) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        SizedBox(width: 64, child: Muted(label)),
        Expanded(child: value),
      ],
    );
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Text(file.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (file.tags.isNotEmpty) row('Tags', Wrap(spacing: 4, runSpacing: 4, children: [for (final tag in file.tags) TagChip(tag, small: true)])),
          row('Size', Text(detail == null ? formatBytes(file.size) : '${formatBytes(file.size)} · $detail')),
          row('Added', Text(formatDate(file.addedAt))),
          if (file.shownOriginal case final path?) row('Original', Text(path, style: pathStyle)),
          const SizedBox(height: 2),
          OutlinedButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit_outlined), label: const Text('Edit in another app…')),
        ],
      ),
    );
  }
}
