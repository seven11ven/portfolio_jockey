import 'package:flutter/material.dart';
import 'package:portfolio_jockey/app/theme.dart';
import 'package:portfolio_jockey/services/tag_changes.dart';
import 'package:portfolio_jockey/ui/common.dart';
import 'package:portfolio_jockey/ui/home/project_dialogs.dart';
import 'package:portfolio_jockey/vault/project_index.dart';

class _TagRow {
  _TagRow(this.original, this.fileCount) : name = original;

  final String original;
  final int fileCount;
  String name;
  bool editing = false;
  bool removed = false;
}

/// "Manage tags": edits are listed, reviewed, then saved together with one
/// confirmation. Deleting a tag only removes the label; files are never deleted.
class ManageTagsDialog extends StatefulWidget {
  const ManageTagsDialog({required this.projectId, required this.index, super.key});

  final String projectId;
  final ProjectIndex index;

  @override
  State<ManageTagsDialog> createState() => _ManageTagsDialogState();
}

class _ManageTagsDialogState extends WriteDialogState<ManageTagsDialog> {
  late final List<_TagRow> _rows = [
    for (final tag in widget.index.tags) _TagRow(tag, widget.index.files.where((f) => f.tags.contains(tag)).length),
  ];
  final List<String> _added = [];
  final _newTag = TextEditingController();
  final Map<_TagRow, TextEditingController> _editors = {};
  bool _reviewing = false;
  String? _problem;

  @override
  void dispose() {
    _newTag.dispose();
    for (final c in _editors.values) {
      c.dispose();
    }
    super.dispose();
  }

  Iterable<String> get _currentNames => [
    for (final row in _rows)
      if (!row.removed) row.name,
    ..._added,
  ];

  TagChanges get _changes => TagChanges(
    renames: {
      for (final row in _rows)
        if (!row.removed && row.name != row.original) row.original: row.name,
    },
    added: [..._added],
    removed: {
      for (final row in _rows)
        if (row.removed) row.original,
    },
  );

  void _add() {
    final name = cleanTagName(_newTag.text);
    if (name == null) {
      return;
    }
    if (hasTag(_currentNames, name)) {
      setState(() => _problem = 'There is already a tag called “$name”.');
      return;
    }
    setState(() {
      _added.add(name);
      _newTag.clear();
      _problem = null;
    });
  }

  void _finishRename(_TagRow row) {
    final name = cleanTagName(_editors[row]!.text);
    final others = _currentNames.where((n) => n != row.name);
    if (name == null) {
      setState(() => _problem = 'A tag needs a name.');
      return;
    }
    if (hasTag(others, name)) {
      setState(() => _problem = 'There is already a tag called “$name”.');
      return;
    }
    setState(() {
      row
        ..name = name
        ..editing = false;
      _problem = null;
    });
  }

  @override
  Widget build(BuildContext context) => _reviewing ? _review(context) : _edit(context);

  Widget _edit(BuildContext context) {
    final editing = _rows.any((r) => r.editing);
    return PjDialog(
      title: 'Tags in “${widget.index.name}”',
      content: [
        if (_rows.isEmpty && _added.isEmpty) const Muted('This project has no tags yet.', small: false),
        for (final row in _rows) _rowWidget(context, row),
        for (final name in _added)
          Row(
            children: [
              TagChip(name),
              const SizedBox(width: 8),
              const Muted('new'),
              const Spacer(),
              IconButton(tooltip: 'Remove', icon: const Icon(Icons.close), onPressed: () => setState(() => _added.remove(name))),
            ],
          ),
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: TextField(
                key: const Key('new-tag'),
                controller: _newTag,
                decoration: const InputDecoration(hintText: 'New tag name'),
                onSubmitted: (_) => _add(),
              ),
            ),
            OutlinedButton(onPressed: _add, child: const Text('Add')),
          ],
        ),
        if (_problem case final problem?) Notice(problem, danger: true),
      ],
      actions: [
        cancelButton(),
        FilledButton(
          onPressed: _changes.isEmpty || editing ? null : () => setState(() => _reviewing = true),
          child: const Text('Review changes…'),
        ),
      ],
    );
  }

  Widget _rowWidget(BuildContext context, _TagRow row) {
    final muted = PjColors.of(context).muted;
    if (row.removed) {
      return Opacity(
        opacity: 0.55,
        child: Row(
          children: [
            Text(row.original, style: const TextStyle(decoration: TextDecoration.lineThrough)),
            const Spacer(),
            const Muted('to be removed'),
            IconButton(tooltip: 'Undo', icon: const Icon(Icons.undo), onPressed: () => setState(() => row.removed = false)),
          ],
        ),
      );
    }
    final count = Text(plural(row.fileCount, 'file'), style: TextStyle(color: muted, fontSize: 12.5));
    if (row.editing) {
      final editor = _editors.putIfAbsent(row, () => TextEditingController(text: row.name));
      return Row(
        spacing: 8,
        children: [
          Expanded(child: TextField(controller: editor, autofocus: true, onSubmitted: (_) => _finishRename(row))),
          count,
          IconButton(tooltip: 'Done', icon: const Icon(Icons.check), onPressed: () => _finishRename(row)),
        ],
      );
    }
    return Row(
      spacing: 4,
      children: [
        TagChip(row.name),
        if (row.name != row.original) Muted('was ${row.original}'),
        const Spacer(),
        count,
        IconButton(tooltip: 'Rename', icon: const Icon(Icons.edit_outlined), onPressed: () => setState(() => row.editing = true)),
        IconButton(tooltip: 'Delete tag', icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => row.removed = true)),
      ],
    );
  }

  Widget _review(BuildContext context) {
    final changes = _changes;
    int countOf(String tag) => _rows.firstWhere((r) => r.original == tag).fileCount;
    return PjDialog(
      title: 'Save these tag changes?',
      content: [
        SummaryBox(
          children: [
            for (final MapEntry(key: from, value: to) in changes.renames.entries)
              Row(spacing: 8, children: [const Icon(Icons.edit_outlined, size: 18), Expanded(child: ChangeArrow(from, to, prefix: 'Rename '))]),
            for (final name in changes.added) _ChangeRow(Icons.add, 'Add “$name”'),
            for (final name in changes.removed)
              _ChangeRow(
                Icons.delete_outline,
                countOf(name) == 0 ? 'Remove “$name”' : 'Remove “$name” from ${plural(countOf(name), 'file')}',
              ),
          ],
        ),
        const Muted('Removing a tag never deletes files. Files left with no tags appear under “Untagged”.'),
        ?errorNotice(),
      ],
      actions: [
        OutlinedButton(onPressed: busy ? null : () => setState(() => _reviewing = false), child: const Text('Back')),
        confirmButton(
          'Confirm changes',
          enabled: true,
          onConfirm: () => AppScope.read(context).projects.applyTagChanges(widget.projectId, changes),
        ),
      ],
    );
  }
}

/// One line of the tag review, with an icon (not an emoji, which some fonts lack).
class _ChangeRow extends StatelessWidget {
  const _ChangeRow(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(spacing: 8, children: [Icon(icon, size: 18), Expanded(child: Text(text))]);
}

/// "Edit tags" for one file or several: toggle chips, then confirm.
class EditFileTagsDialog extends StatefulWidget {
  const EditFileTagsDialog({required this.projectId, required this.index, required this.files, super.key});

  final String projectId;
  final ProjectIndex index;
  final List<FileEntry> files;

  @override
  State<EditFileTagsDialog> createState() => _EditFileTagsDialogState();
}

/// For several files, a tag can be on all of them, none, or some ([_mixed]).
enum _TagState { on, off, mixed }

class _EditFileTagsDialogState extends WriteDialogState<EditFileTagsDialog> {
  late final List<String> _tags = [...widget.index.tags];
  final List<String> _newTags = [];
  late final Map<String, _TagState> _initial = {for (final tag in _tags) tag: _stateOf(tag)};
  late final Map<String, _TagState> _state = {..._initial};
  final _newTag = TextEditingController();
  bool _addingTag = false;

  @override
  void dispose() {
    _newTag.dispose();
    super.dispose();
  }

  _TagState _stateOf(String tag) {
    final count = widget.files.where((f) => f.tags.contains(tag)).length;
    return count == 0 ? _TagState.off : (count == widget.files.length ? _TagState.on : _TagState.mixed);
  }

  void _toggle(String tag) => setState(() => _state[tag] = _state[tag] == _TagState.on ? _TagState.off : _TagState.on);

  void _addTag() {
    final name = cleanTagName(_newTag.text);
    if (name != null && !hasTag(_tags, name)) {
      setState(() {
        _tags.add(name);
        _newTags.add(name);
        _initial[name] = _TagState.off;
        _state[name] = _TagState.on;
      });
    }
    setState(() {
      _newTag.clear();
      _addingTag = false;
    });
  }

  Map<String, List<String>> get _result => {
    for (final file in widget.files)
      file.id: [
        for (final tag in _tags)
          if (_state[tag] == _TagState.on || (_state[tag] == _TagState.mixed && file.tags.contains(tag))) tag,
      ],
  };

  bool get _changed => _tags.any((t) => _state[t] != _initial[t]);

  @override
  Widget build(BuildContext context) {
    final single = widget.files.length == 1;
    final added = [for (final t in _tags) if (_state[t] == _TagState.on && _initial[t] != _TagState.on) t];
    final removed = [for (final t in _tags) if (_state[t] == _TagState.off && _initial[t] != _TagState.off) t];
    String list(Iterable<String> tags) => tags.isEmpty ? 'no tags' : tags.join(', ');
    return PjDialog(
      title: single ? 'Tags for ${widget.files.single.name}' : 'Tags for ${plural(widget.files.length, 'file')}',
      content: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in _tags)
              TagChip(
                _state[tag] == _TagState.mixed ? '$tag (some)' : tag,
                selected: _state[tag] == _TagState.on,
                onTap: busy ? null : () => _toggle(tag),
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
              TagChip('New tag', icon: Icons.add, onTap: busy ? null : () => setState(() => _addingTag = true)),
          ],
        ),
        if (_changed)
          SummaryBox(
            children: [
              if (single)
                Text('Was: ${list(widget.files.single.tags)} · Now: ${list(_result[widget.files.single.id]!)}')
              else ...[
                if (added.isNotEmpty) Text('Add to every file: ${added.join(', ')}'),
                if (removed.isNotEmpty) Text('Remove from every file: ${removed.join(', ')}'),
              ],
            ],
          ),
        ?errorNotice(),
      ],
      actions: [
        cancelButton(),
        confirmButton(
          'Confirm tags',
          enabled: _changed,
          onConfirm: () => AppScope.read(context).projects.setFileTags(widget.projectId, _result, newTags: _newTags),
        ),
      ],
    );
  }
}
