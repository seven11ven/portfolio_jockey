/// A batch of tag edits from "Manage tags", reviewed and confirmed together.
final class TagChanges {
  TagChanges({Map<String, String>? renames, List<String>? added, Set<String>? removed})
    : renames = renames ?? {},
      added = added ?? [],
      removed = removed ?? {};

  /// Old name → new name.
  final Map<String, String> renames;
  final List<String> added;
  final Set<String> removed;

  bool get isEmpty => renames.isEmpty && added.isEmpty && removed.isEmpty;
}

/// Trims a tag name. Returns null if nothing is left.
String? cleanTagName(String name) {
  final trimmed = name.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// True if [name] matches one of [existing], ignoring case.
bool hasTag(Iterable<String> existing, String name) => existing.any((t) => t.toLowerCase() == name.toLowerCase());
