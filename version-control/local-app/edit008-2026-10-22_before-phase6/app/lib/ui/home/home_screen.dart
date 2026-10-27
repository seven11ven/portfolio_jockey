import 'dart:async';

import 'package:flutter/material.dart';
import 'package:portfolio_jockey/app/theme.dart';
import 'package:portfolio_jockey/services/project_service.dart';
import 'package:portfolio_jockey/ui/common.dart';
import 'package:portfolio_jockey/ui/home/project_dialogs.dart';
import 'package:portfolio_jockey/ui/project/project_screen.dart';

/// The project grid.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ProjectListing? _listing;
  String? _loadError;
  String _search = '';

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final listing = await AppScope.read(context).projects.listProjects();
      if (mounted) {
        setState(() {
          _listing = listing;
          _loadError = null;
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _loadError = 'Projects could not be loaded: $e');
      }
    }
  }

  /// Shows [dialog]; reloads the projects if it changed anything.
  Future<void> _show(Widget dialog) async {
    final changed = await showDialog<bool>(context: context, builder: (_) => dialog);
    if (changed ?? false) {
      await _reload();
    }
  }

  Future<void> _open(ProjectSummary project) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProjectScreen(projectId: project.id)));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final listing = _listing;
    final query = _search.trim().toLowerCase();
    final projects = listing?.projects.where((p) => p.index.name.toLowerCase().contains(query)).toList() ?? [];
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          spacing: 16,
          children: [
            const _Brand(),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: TextField(
                  key: const Key('search'),
                  onChanged: (v) => setState(() => _search = v),
                  decoration: const InputDecoration(hintText: 'Search projects…', prefixIcon: Icon(Icons.search)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          comingSoon(const IconButton(onPressed: null, icon: Icon(Icons.download_outlined))),
          IconButton(tooltip: 'Lock', onPressed: () => AppScope.read(context).lock(), icon: const Icon(Icons.lock_outline)),
          comingSoon(const IconButton(onPressed: null, icon: Icon(Icons.settings_outlined))),
          const SizedBox(width: 8),
        ],
      ),
      body: listing == null
          ? Center(child: _loadError == null ? const CircularProgressIndicator() : Notice(_loadError!, danger: true))
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Row(
                  children: [
                    Text('Projects', style: Theme.of(context).textTheme.headlineSmall),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: () => _show(const NewProjectDialog()),
                      icon: const Icon(Icons.add),
                      label: const Text('New project'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (listing.unreadable.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Notice(
                      '${plural(listing.unreadable.length, 'project')} could not be read: '
                      'the index is damaged or from another vault. They are left untouched.',
                      danger: true,
                    ),
                  ),
                GridView(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 300,
                    mainAxisExtent: 270,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                  ),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final project in projects)
                      _ProjectCard(project: project, onOpen: () => _open(project), onAction: (dialog) => _show(dialog)),
                    if (query.isEmpty) _NewProjectCard(onTap: () => _show(const NewProjectDialog())),
                  ],
                ),
                if (projects.isEmpty && query.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 24), child: Center(child: Muted('No projects match “$_search”.', small: false))),
              ],
            ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 10,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(8)),
          child: Text('PJ', style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w800)),
        ),
        const Text('Portfolio Jockey', style: TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.onOpen, required this.onAction});

  final ProjectSummary project;
  final VoidCallback onOpen;
  final void Function(Widget dialog) onAction;

  @override
  Widget build(BuildContext context) {
    final index = project.index;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 6,
            children: [
              CoverView(name: index.name, image: project.cover),
              Row(
                children: [
                  Expanded(
                    child: Text(index.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                  ),
                  ProjectMenuButton(project: project, onAction: onAction),
                ],
              ),
              Expanded(
                child: Text(index.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: PjColors.of(context).muted)),
              ),
              Muted('${plural(index.files.length, 'file')} · ${formatChanged(index.changedAt)}'),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "…" menu next to a project's name (home grid and project view).
class ProjectMenuButton extends StatelessWidget {
  const ProjectMenuButton({required this.project, required this.onAction, super.key});

  final ProjectSummary project;
  final void Function(Widget dialog) onAction;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return MenuAnchor(
      menuChildren: [
        _Title(project.index.name),
        MenuItemButton(
          leadingIcon: const Icon(Icons.edit_outlined),
          onPressed: () => onAction(RenameProjectDialog(projectId: project.id, currentName: project.index.name)),
          child: const Text('Rename'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.image_outlined),
          onPressed: () => onAction(EditDetailsDialog(projectId: project.id, index: project.index, cover: project.cover)),
          child: const Text('Change cover art and description'),
        ),
        const Divider(height: 8),
        comingSoon(const MenuItemButton(leadingIcon: Icon(Icons.archive_outlined), child: Text('Export as ZIP…'))),
        comingSoon(const MenuItemButton(leadingIcon: Icon(Icons.archive_outlined), child: Text('Export as TAR…'))),
        const Divider(height: 8),
        MenuItemButton(
          leadingIcon: Icon(Icons.delete_outline, color: error),
          onPressed: () => onAction(DeleteProjectDialog(projectId: project.id, index: project.index)),
          child: Text('Delete project…', style: TextStyle(color: error)),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: 'Project actions',
        icon: const Icon(Icons.more_horiz),
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
    child: Text(text, style: TextStyle(fontWeight: FontWeight.w700, color: PjColors.of(context).muted)),
  );
}

class _NewProjectCard extends StatelessWidget {
  const _NewProjectCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final extra = PjColors.of(context);
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: extra.border, width: 2)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              Icon(Icons.add, color: extra.muted),
              Text('New project', style: TextStyle(color: extra.muted, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
