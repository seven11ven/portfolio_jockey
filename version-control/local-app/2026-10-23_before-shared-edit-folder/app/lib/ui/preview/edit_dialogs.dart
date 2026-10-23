import 'dart:async';

import 'package:flutter/material.dart';
import 'package:portfolio_jockey/app/edit_session.dart';
import 'package:portfolio_jockey/app/theme.dart';
import 'package:portfolio_jockey/services/native/gio_apps.dart';
import 'package:portfolio_jockey/services/private_folder.dart';
import 'package:portfolio_jockey/ui/common.dart';
import 'package:portfolio_jockey/ui/home/project_dialogs.dart';
import 'package:portfolio_jockey/vault/project_index.dart';

const TextStyle _bold = TextStyle(fontWeight: FontWeight.w700);

/// "Edit in another app": confirms, decrypts the file into a private
/// memory-only folder and opens it. Shows [CantOpenDialog] instead when
/// there's no such folder, and refuses while another file is being edited.
Future<void> editInAnotherApp(BuildContext context, {required String projectId, required String projectName, required FileEntry file}) async {
  final edits = AppScope.read(context).edits;
  if (edits.active case final active?) {
    await showDialog<void>(
      context: context,
      builder: (_) => PjDialog(
        title: 'Finish the current edit first',
        content: [Text('${active.info.fileName} is still being edited. Only one file can be edited at a time: save or discard it first.')],
        actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
      ),
    );
    return;
  }
  final failure = await showDialog<NoPrivateFolder>(
    context: context,
    builder: (_) => EditInDialog(projectId: projectId, projectName: projectName, file: file),
  );
  if (failure != null && context.mounted) {
    await showDialog<void>(context: context, builder: (_) => CantOpenDialog(fileName: file.name, reason: failure));
  }
}

/// Scene 3 (the app list) and scene 8 (the desktop's chooser, in a Flatpak).
/// Pops true when the file was opened, or the [NoPrivateFolder] failure.
class EditInDialog extends StatefulWidget {
  const EditInDialog({required this.projectId, required this.projectName, required this.file, super.key});

  final String projectId;
  final String projectName;
  final FileEntry file;

  @override
  State<EditInDialog> createState() => _EditInDialogState();
}

class _EditInDialogState extends State<EditInDialog> {
  List<InstalledApp>? _apps;
  InstalledApp? _chosen;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadApps());
  }

  Future<void> _loadApps() async {
    final launcher = AppScope.read(context).edits.launcher;
    try {
      final apps = await launcher.appsFor(widget.file.name);
      if (mounted) {
        setState(() {
          _apps = apps;
          _chosen = apps.firstOrNull;
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _apps = const [];
          _error = "Couldn't list your apps: $e";
        });
      }
    }
  }

  Future<void> _open() async {
    final controller = AppScope.read(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await controller.edits.start(
        service: controller.projects,
        projectId: widget.projectId,
        projectName: widget.projectName,
        file: widget.file,
        app: _chosen,
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on NoPrivateFolder catch (e) {
      if (mounted) {
        Navigator.of(context).pop(e);
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Nothing was opened, and no readable copy was kept. $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final launcher = AppScope.read(context).edits.launcher;
    final chooser = launcher.usesDesktopChooser;
    final apps = _apps;
    final noApps = !chooser && apps != null && apps.isEmpty;
    return PjDialog(
      title: 'Edit ${widget.file.name} in another app?',
      content: [
        if (chooser)
          const Text('Your desktop will ask which app to open it with.')
        else if (apps == null)
          const Center(child: CircularProgressIndicator())
        else if (noApps)
          const Notice('No installed app says it can open this type of file.')
        else ...[
          const FieldLabel('Open with'),
          RadioGroup<InstalledApp>(
            groupValue: _chosen,
            onChanged: (app) => setState(() => _chosen = app),
            child: Column(
              children: [
                for (final app in apps)
                  RadioListTile<InstalledApp>(
                    value: app,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(app.name),
                    subtitle: app.isDefault ? const Text('Default for this file type') : null,
                  ),
              ],
            ),
          ),
        ],
        Notice(
          chooser
              ? "While you edit, a readable copy of this file exists in a private memory-only folder. It's wiped when you save or discard your changes. The other app may keep its own history of the file."
              : "While you edit, a readable copy of this file exists in a private memory-only folder. It's wiped when you save or discard your changes.",
        ),
        if (_error case final error?) Notice(error, danger: true),
      ],
      actions: [
        OutlinedButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy || (!chooser && _chosen == null) ? null : _open,
          child: _busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Decrypt and open'),
        ),
      ],
    );
  }
}

/// Scene 12: no private memory-only folder, so nothing is decrypted.
class CantOpenDialog extends StatelessWidget {
  const CantOpenDialog({required this.fileName, required this.reason, super.key});

  final String fileName;
  final NoPrivateFolder reason;

  @override
  Widget build(BuildContext context) => PjDialog(
    title: "Can't open $fileName",
    content: [
      Text(
        "There's no private memory-only folder on this system (${reason.message}), so a readable copy can't be made safely.",
      ),
      const Muted('This usually means the app was started outside a normal desktop login.'),
    ],
    actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
  );
}

/// Scene 5: save the edited copy into the project. Pops true when saved (or
/// when an unchanged edit was finished).
class SaveEditDialog extends StatefulWidget {
  const SaveEditDialog({required this.session, super.key});

  final EditSession session;

  @override
  State<SaveEditDialog> createState() => _SaveEditDialogState();
}

class _SaveEditDialogState extends WriteDialogState<SaveEditDialog> {
  FileEntry? _current;
  int? _editedSize;
  DateTime? _editedAt;
  bool? _changed;
  bool _missing = false;

  /// Set when a save was refused because the copy isn't ready (scenes 5c, 5d).
  EditNotReadyReason? _notReady;

  @override
  void initState() {
    super.initState();
    unawaited(_compare());
  }

  Future<void> _compare() async {
    final controller = AppScope.read(context);
    final session = widget.session;
    try {
      final current = await controller.edits.entryFor(controller.projects, session);
      final copyThere = await session.copy.exists();
      final changed = current != null && copyThere && await controller.edits.hasChanges(controller.projects, session);
      if (mounted) {
        setState(() {
          _current = current;
          _missing = current == null || !copyThere;
          _editedSize = copyThere ? session.copy.lengthSync() : null;
          _editedAt = copyThere ? session.copy.lastModifiedSync() : null;
          _changed = changed;
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() => error = "Couldn't compare the versions. $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.read(context);
    final session = widget.session;
    final name = session.info.fileName;
    final changed = _changed;
    final current = _current;
    final notReady = _notReady;
    return PjDialog(
      title: changed == false && !_missing ? 'No changes to $name' : 'Save your changes to $name?',
      content: [
        if (changed == null && error == null && !_missing)
          const Center(child: CircularProgressIndicator())
        else if (_missing)
          Notice(
            current == null
                ? '$name is no longer in ${session.info.projectName}, so the edit can\'t be saved into it. You can only discard it.'
                : 'The edited copy is gone (the other app may have moved or deleted it), so there is nothing to save. You can only discard it.',
            danger: true,
          )
        else if (notReady == EditNotReadyReason.stillWriting)
          Notice(const EditNotReady(EditNotReadyReason.stillWriting).toString())
        else ...[
          SummaryBox(
            children: [
              Row(children: [const Expanded(child: Text('Current version')), Muted('${formatBytes(current!.size)} · added ${formatDate(current.addedAt)}')]),
              Row(
                children: [
                  const Expanded(child: Text('Edited version', style: _bold)),
                  Muted('${formatBytes(_editedSize ?? 0)} · ${_editedAt == null ? '' : formatAgo(_editedAt!)}'),
                ],
              ),
            ],
          ),
          if (notReady == EditNotReadyReason.empty)
            Notice(const EditNotReady(EditNotReadyReason.empty).toString())
          else if (changed!) ...[
            const Text('The edited version is encrypted and replaces the current one. The temporary readable copy is then wiped.'),
            const Muted(_closeItFirst),
          ] else ...[
            const Text('The edited copy is the same as the current version. Finishing the edit wipes the temporary readable copy.'),
            const Muted(
              'If you did save in the other app, it may have saved to a different place, or it wasn\'t allowed to save this file. '
              'Save it there again with its normal Save, not "Save As".',
            ),
          ],
        ],
        ?errorNotice(),
      ],
      actions: [
        cancelButton(),
        if (_missing)
          confirmButton('Discard', danger: true, enabled: true, onConfirm: () => controller.edits.discard(session))
        else if (changed == false)
          confirmButton('Finish editing', enabled: true, onConfirm: () => controller.edits.discard(session))
        else if (notReady == EditNotReadyReason.empty)
          _saveButton('Save the empty file', danger: true, allowEmpty: true)
        else if (notReady == EditNotReadyReason.stillWriting)
          _saveButton('Try again')
        else
          _saveButton('Encrypt and replace', enabled: changed == true),
      ],
    );
  }

  /// Saves, unless the copy isn't ready: then it stays open in scene 5c or 5d
  /// instead of showing a generic error.
  Widget _saveButton(String label, {bool enabled = true, bool danger = false, bool allowEmpty = false}) {
    final controller = AppScope.read(context);
    return FilledButton(
      style: danger ? dangerButtonStyle(context) : null,
      onPressed: enabled && !busy
          ? () async {
              setState(() {
                busy = true;
                error = null;
              });
              try {
                await controller.edits.save(controller.projects, widget.session, allowEmpty: allowEmpty);
                if (mounted) {
                  Navigator.of(context).pop(true);
                }
              } on EditNotReady catch (e) {
                if (mounted) {
                  setState(() {
                    busy = false;
                    _notReady = e.reason;
                  });
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
          : null,
      child: busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(label),
    );
  }
}

const String _closeItFirst = "Close the file in the other app first. Changes it makes later won't be saved.";

/// Scene 9: discard the edited copy. Pops true when discarded.
class DiscardEditDialog extends StatefulWidget {
  const DiscardEditDialog({required this.session, super.key});

  final EditSession session;

  @override
  State<DiscardEditDialog> createState() => _DiscardEditDialogState();
}

class _DiscardEditDialogState extends WriteDialogState<DiscardEditDialog> {
  @override
  Widget build(BuildContext context) {
    final info = widget.session.info;
    return PjDialog(
      title: 'Discard your changes to ${info.fileName}?',
      danger: true,
      content: [
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'The edited copy is wiped. The version in '),
              TextSpan(text: info.projectName, style: _bold),
              const TextSpan(text: ' stays as it was.'),
            ],
          ),
        ),
        const Muted(_closeItFirst),
        ?errorNotice(),
      ],
      actions: [
        cancelButton(label: 'Keep editing'),
        confirmButton('Discard changes', danger: true, enabled: true, onConfirm: () => AppScope.read(context).edits.discard(widget.session)),
      ],
    );
  }
}

/// Saves (with confirmation) or discards (with confirmation) [session].
/// Returns true if the edit was finished.
Future<bool> finishEdit(BuildContext context, EditSession session, {required bool save}) async =>
    await showDialog<bool>(context: context, builder: (_) => save ? SaveEditDialog(session: session) : DiscardEditDialog(session: session)) ?? false;

/// Locks the vault, unless a file is being edited: then scene 10 asks to save
/// or discard it first.
Future<void> requestLock(BuildContext context) async {
  final controller = AppScope.read(context);
  final session = controller.edits.active;
  if (session == null) {
    controller.lock();
    return;
  }
  final save = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => PjDialog(
      title: 'Finish editing before locking',
      content: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: session.info.fileName, style: _bold),
              TextSpan(
                text: session.info.appName == null
                    ? ' is still open in another app. Save or discard your changes, then lock.'
                    : ' is still open in ${session.info.appName}. Save or discard your changes, then lock.',
              ),
            ],
          ),
        ),
      ],
      actions: [
        OutlinedButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
        OutlinedButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Discard…')),
        FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Save changes…')),
      ],
    ),
  );
  if (save == null || !context.mounted) {
    return;
  }
  if (await finishEdit(context, session, save: save) && controller.canLock) {
    controller.lock();
  }
}

/// Scene 11: an edit left by a crash, found at unlock.
class LeftoverEditDialog extends StatelessWidget {
  const LeftoverEditDialog({required this.session, super.key});

  final EditSession session;

  @override
  Widget build(BuildContext context) {
    final info = session.info;
    return PjDialog(
      title: "An edit wasn't finished",
      content: [
        SummaryBox(
          children: [
            Text(info.fileName, style: _bold),
            Muted('in ${info.projectName} · edited ${formatAgo(info.startedAt)}'),
          ],
        ),
        const Text('Save it into the project, or discard it. Either way the readable copy is then wiped.'),
      ],
      actions: [
        OutlinedButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Discard')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Save into project…')),
      ],
    );
  }
}

/// Scene 4: the banner above every screen while a file is being edited.
class EditBanner extends StatefulWidget {
  const EditBanner({required this.session, required this.onSave, required this.onDiscard, super.key});

  final EditSession session;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  @override
  State<EditBanner> createState() => _EditBannerState();
}

class _EditBannerState extends State<EditBanner> {
  DateTime? _changed;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => unawaited(_refresh()));
  }

  Future<void> _refresh() async {
    final changed = await widget.session.lastChanged();
    if (mounted) {
      setState(() => _changed = changed);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.session.info;
    final colors = PjColors.of(context);
    final changed = _changed;
    final where = info.appName == null ? '' : ' in ${info.appName}';
    final when = changed == null || !changed.isAfter(info.startedAt.add(const Duration(seconds: 2))) ? 'Not changed yet' : 'Changed ${formatAgo(changed)}';
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.warnSoft, border: Border(bottom: BorderSide(color: colors.border))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 6,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                Icon(Icons.edit_outlined, size: 18, color: colors.warn),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Editing ${info.fileName}$where. $when.', style: TextStyle(color: colors.warn, fontWeight: FontWeight.w600)),
                      const Muted("If the other app couldn't open or save the file, choose Discard. The project still has its own copy."),
                    ],
                  ),
                ),
              ],
            ),
            OutlinedButton(onPressed: widget.onDiscard, child: const Text('Discard')),
            FilledButton(onPressed: widget.onSave, child: const Text('Save changes')),
          ],
        ),
      ),
    );
  }
}

/// The [EditBanner] while a file is being edited, nothing otherwise. Each
/// screen puts it at the top of its body, under its app bar.
class EditBannerSlot extends StatelessWidget {
  const EditBannerSlot({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppScope.read(context).edits,
    builder: (context, _) {
      final session = AppScope.read(context).edits.active;
      if (session == null) {
        return const SizedBox.shrink();
      }
      return SizedBox(
        width: double.infinity,
        child: EditBanner(
          key: ValueKey(session.folder.path),
          session: session,
          onSave: () => unawaited(finishEdit(context, session, save: true)),
          onDiscard: () => unawaited(finishEdit(context, session, save: false)),
        ),
      );
    },
  );
}

/// Wraps a screen's body with the [EditBannerSlot] above it.
Widget withEditBanner(Widget body) => Column(children: [const EditBannerSlot(), Expanded(child: body)]);
