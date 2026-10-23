import 'dart:io';

import 'package:portfolio_jockey/vault/ids.dart';

/// Where everything lives under a storage location:
///
///     <root>/.pj/vault                      the wrapped master key
///     <root>/<project id>/index.enc         the project's encrypted index
///     <root>/<project id>/cover.enc         its cover art
///     <root>/<project id>/blobs/<id>.enc    each file's contents
///
/// Every ID is checked before it becomes part of a path.
final class VaultLayout {
  VaultLayout(this.root);

  final Directory root;

  Directory get metadataDir => Directory('${root.path}/.pj');

  /// Unfinished multi-step work, for clean-up after a crash (journal.dart).
  File get journalFile => File('${metadataDir.path}/journal.enc');

  /// Notices for the user until they're dismissed (inbox.dart).
  File get inboxFile => File('${metadataDir.path}/inbox.enc');
  File get vaultFile => File('${metadataDir.path}/vault');

  Directory projectDir(String projectId) {
    checkId(projectId);
    return Directory('${root.path}/$projectId');
  }

  File indexFile(String projectId) => File('${projectDir(projectId).path}/index.enc');
  /// `cover.enc`, or `cover-<coverId>.enc` for covers saved since 2026-10-23.
  File coverFile(String projectId, [String? coverId]) {
    if (coverId == null) {
      return File('${projectDir(projectId).path}/cover.enc');
    }
    checkId(coverId);
    return File('${projectDir(projectId).path}/cover-$coverId.enc');
  }
  Directory blobDir(String projectId) => Directory('${projectDir(projectId).path}/blobs');

  File blobFile(String projectId, String blobId) {
    checkId(blobId);
    return File('${blobDir(projectId).path}/$blobId.enc');
  }
}
