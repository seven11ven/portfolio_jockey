import 'package:portfolio_jockey/vault/project_index.dart';

enum SortKey { name, size, date }

/// How the project screen lists things. Kept for the whole session, so it
/// carries over from one project to the next.
final class ExplorerPrefs {
  bool listView = false;
  SortKey sortKey = SortKey.name;
  bool ascending = true;
}

/// A folder or a file, as one card or row.
final class ExplorerItem {
  ExplorerItem.folder(FolderEntry this.folder, FolderStats this.stats) : file = null;
  ExplorerItem.file(FileEntry this.file) : folder = null, stats = null;

  final FolderEntry? folder;
  final FileEntry? file;

  /// What a folder holds, including everything inside it.
  final FolderStats? stats;

  bool get isFolder => folder != null;
  String get id => folder?.id ?? file!.id;
  String get name => folder?.name ?? file!.name;

  /// The folder it's in, or null at the top level.
  String? get parentId => folder != null ? folder!.parentId : file!.folderId;

  /// A folder's size is its total.
  int get size => stats?.bytes ?? file!.size;

  /// When a file was added, or a folder was created.
  DateTime get date => folder?.createdAt ?? file!.addedAt;
}

/// Sorts folders and files by [key], with folders always first.
List<ExplorerItem> sortItems(Iterable<ExplorerItem> items, SortKey key, {required bool ascending}) {
  int byName(ExplorerItem a, ExplorerItem b) {
    final lower = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return lower != 0 ? lower : a.name.compareTo(b.name);
  }

  return [...items]..sort((a, b) {
    if (a.isFolder != b.isFolder) {
      return a.isFolder ? -1 : 1;
    }
    final primary = switch (key) {
      SortKey.name => byName(a, b),
      SortKey.size => a.size.compareTo(b.size),
      SortKey.date => a.date.compareTo(b.date),
    };
    if (primary != 0) {
      return ascending ? primary : -primary;
    }
    final tie = byName(a, b);
    return tie != 0 ? tie : a.id.compareTo(b.id);
  });
}

/// Whether [name] contains [query], ignoring case. An empty query matches everything.
bool nameMatches(String name, String query) => query.isEmpty || name.toLowerCase().contains(query.toLowerCase());

/// Where a folder is, for results from the whole project: "Kitchen Remodel / Invoices / 2026".
String folderPathLabel(ProjectIndex index, String? folderId) => [index.name, ...index.pathTo(folderId).map((f) => f.name)].join(' / ');

/// What's being dragged: files and folders by ID.
final class DragItems {
  const DragItems({this.fileIds = const [], this.folderIds = const []});

  final List<String> fileIds;
  final List<String> folderIds;

  int get count => fileIds.length + folderIds.length;
}
