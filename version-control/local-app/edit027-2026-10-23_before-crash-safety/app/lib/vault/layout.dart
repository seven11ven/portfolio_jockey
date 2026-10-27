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
  File get vaultFile => File('${metadataDir.path}/vault');

  Directory projectDir(String projectId) {
    checkId(projectId);
    return Directory('${root.path}/$projectId');
  }

  File indexFile(String projectId) => File('${projectDir(projectId).path}/index.enc');
  File coverFile(String projectId) => File('${projectDir(projectId).path}/cover.enc');
  Directory blobDir(String projectId) => Directory('${projectDir(projectId).path}/blobs');

  File blobFile(String projectId, String blobId) {
    checkId(blobId);
    return File('${blobDir(projectId).path}/$blobId.enc');
  }
}
