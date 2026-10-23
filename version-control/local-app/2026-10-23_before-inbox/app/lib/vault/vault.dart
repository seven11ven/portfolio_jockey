import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:portfolio_jockey/vault/aead.dart';
import 'package:portfolio_jockey/vault/atomic_write.dart';
import 'package:portfolio_jockey/vault/blob_stream.dart';
import 'package:portfolio_jockey/vault/errors.dart';
import 'package:portfolio_jockey/vault/ids.dart';
import 'package:portfolio_jockey/vault/journal.dart';
import 'package:portfolio_jockey/vault/kdf.dart';
import 'package:portfolio_jockey/vault/layout.dart';
import 'package:portfolio_jockey/vault/native/libc.dart';
import 'package:portfolio_jockey/vault/native/sodium.dart';
import 'package:portfolio_jockey/vault/project_index.dart';
import 'package:portfolio_jockey/vault/secure_buffer.dart';
import 'package:portfolio_jockey/vault/vault_header.dart';

/// Creating, unlocking and re-keying the vault at a storage location.
///
/// None of these ask for confirmation: the interface (plan phase 5) shows the
/// confirm/cancel step before calling anything that writes to disk.
abstract final class Vault {
  static const int _masterKeyLength = 32;

  static Future<bool> exists(Directory root) => VaultLayout(root).vaultFile.exists();

  /// Creates a vault with a new random master key, protected by [passphrase].
  static Future<UnlockedVault> create(Directory root, String passphrase, {KdfParams? kdf}) async {
    final layout = VaultLayout(root);
    if (await layout.vaultFile.exists()) {
      throw VaultAlreadyExists('A vault already exists in ${root.path}');
    }
    final masterKey = SecureBuffer.random(_masterKeyLength);
    var ok = false;
    try {
      final header = await _wrap(masterKey, passphrase, kdf ?? KdfParams.moderate());
      await layout.metadataDir.create(recursive: true);
      await writeBytesAtomically(layout.vaultFile, header.toBytes());
      ok = true;
      return UnlockedVault._(layout, masterKey);
    } finally {
      if (!ok) {
        masterKey.dispose();
      }
    }
  }

  /// Unlocks the vault. Throws [WrongPassphrase] if [passphrase] is wrong or
  /// the vault file was changed, and [VaultNotFound] if there is no vault.
  static Future<UnlockedVault> unlock(Directory root, String passphrase) async {
    final layout = VaultLayout(root);
    final header = VaultHeader.parse(await _readVaultFile(layout));
    final masterKey = SecureBuffer.allocate(_masterKeyLength);
    var ok = false;
    try {
      final passphraseKey = await _passphraseKey(passphrase, header.salt, header.kdf);
      try {
        ok = aeadDecryptSecret(masterKey, header.wrappedKey, ad: header.associatedData, nonce: header.nonce, key: passphraseKey);
      } finally {
        passphraseKey.dispose();
      }
      if (!ok) {
        throw const WrongPassphrase();
      }
      return UnlockedVault._(layout, masterKey);
    } finally {
      if (!ok) {
        masterKey.dispose();
      }
    }
  }

  /// Re-wraps the master key under [replacement]. Files and indexes aren't
  /// re-encrypted, because the master key itself doesn't change.
  static Future<void> changePassphrase(Directory root, String current, String replacement, {KdfParams? kdf}) async {
    final vault = await unlock(root, current);
    try {
      final header = await _wrap(vault._masterKey, replacement, kdf ?? KdfParams.moderate());
      await writeBytesAtomically(vault.layout.vaultFile, header.toBytes());
    } finally {
      vault.lock();
    }
  }

  static Future<VaultHeader> _wrap(SecureBuffer masterKey, String passphrase, KdfParams kdf) async {
    final sodium = Sodium.instance;
    final salt = sodium.randomBytes(sodium.pwhashSaltBytes);
    final nonce = sodium.randomBytes(sodium.aeadNonceBytes);
    final unwrapped = VaultHeader(kdf: kdf, salt: salt, nonce: nonce, wrappedKey: Uint8List(0));
    final passphraseKey = await _passphraseKey(passphrase, salt, kdf);
    try {
      final wrappedKey = aeadEncryptSecret(masterKey, ad: unwrapped.associatedData, nonce: nonce, key: passphraseKey);
      return VaultHeader(kdf: kdf, salt: salt, nonce: nonce, wrappedKey: wrappedKey);
    } finally {
      passphraseKey.dispose();
    }
  }

  // A Dart String can't be wiped, so the passphrase is copied into guarded
  // memory straight away, the UTF-8 copy is wiped, and the guarded copy is
  // freed (and wiped) as soon as the key is derived.
  static Future<SecureBuffer> _passphraseKey(String passphrase, Uint8List salt, KdfParams kdf) async {
    if (passphrase.isEmpty) {
      throw ArgumentError.value('', 'passphrase', 'must not be empty');
    }
    final buffer = SecureBuffer.takeBytes(utf8.encode(passphrase));
    try {
      return await deriveKey(buffer, salt, kdf, length: Sodium.instance.aeadKeyBytes);
    } finally {
      buffer.dispose();
    }
  }

  static Future<Uint8List> _readVaultFile(VaultLayout layout) async {
    try {
      return await layout.vaultFile.readAsBytes();
    } on PathNotFoundException {
      throw VaultNotFound('No vault in ${layout.root.path}');
    }
  }
}

/// An unlocked vault. The master key stays in guarded memory until [lock].
final class UnlockedVault {
  UnlockedVault._(this.layout, this._masterKey);

  final VaultLayout layout;
  final SecureBuffer _masterKey;

  bool get isLocked => _masterKey.isDisposed;

  /// Wipes the master key. The vault must be unlocked again to use it.
  void lock() => _masterKey.dispose();

  /// The same unlocked vault, read from [root] instead, after its files were
  /// copied there (see `StorageMove`). The master key moves to the returned
  /// object; this one must not be used or locked afterwards.
  UnlockedVault relocatedTo(Directory root) => UnlockedVault._(VaultLayout(root), _masterKey);

  /// The IDs of every project folder that has an index.
  Future<List<String>> projectIds() async {
    final ids = <String>[];
    await for (final entry in layout.root.list()) {
      final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      if (entry is Directory && isValidId(name) && await layout.indexFile(name).exists()) {
        ids.add(name);
      }
    }
    ids.sort();
    return ids;
  }

  /// Creates a project folder and its encrypted index. Returns the new ID.
  /// Creates a project with a new ID, or with [id] when the caller has
  /// already listed it in the journal (imports).
  Future<String> createProject(ProjectIndex index, {String? id}) async {
    final projectId = id ?? newId();
    checkId(projectId);
    if (await layout.projectDir(projectId).exists()) {
      throw StateError('Project $projectId already exists');
    }
    await layout.blobDir(projectId).create(recursive: true);
    await writeIndex(projectId, index);
    return projectId;
  }

  /// The unfinished work listed in the journal; empty if there's none.
  Future<List<JournalEntry>> readJournal() async {
    _checkUnlocked();
    final file = layout.journalFile;
    if (!await file.exists()) {
      return [];
    }
    return decryptJournal(await file.readAsBytes(), masterKey: _masterKey);
  }

  /// Replaces the journal, atomically. An empty journal removes the file.
  Future<void> writeJournal(List<JournalEntry> entries) async {
    _checkUnlocked();
    final file = layout.journalFile;
    if (entries.isEmpty) {
      if (await file.exists()) {
        await file.delete();
        Libc.instance.syncDirectory(file.parent.path);
      }
      return;
    }
    await writeBytesAtomically(file, encryptJournal(entries, masterKey: _masterKey));
  }

  Future<ProjectIndex> readIndex(String projectId) async =>
      decryptIndex(await layout.indexFile(projectId).readAsBytes(), projectId: projectId, masterKey: _masterKey);

  Future<void> writeIndex(String projectId, ProjectIndex index) async {
    await writeBytesAtomically(layout.indexFile(projectId), encryptIndex(index, projectId: projectId, masterKey: _masterKey));
  }

  /// Permanently deletes a project folder: its index, cover and every file.
  /// The index goes first, so an interrupted delete never leaves a project
  /// that lists files it no longer has.
  Future<void> deleteProject(String projectId) async {
    _checkUnlocked();
    final index = layout.indexFile(projectId);
    if (await index.exists()) {
      await index.delete();
    }
    await layout.projectDir(projectId).delete(recursive: true);
  }

  /// Encrypts [plaintext] as file [blobId] of the project, with [key].
  Future<void> writeBlob(String projectId, String blobId, Stream<List<int>> plaintext, SecureBuffer key) {
    _checkUnlocked();
    return encryptToFile(plaintext, layout.blobFile(projectId, blobId), key);
  }

  /// Decrypts file [blobId] of the project. See [decryptFile] for how errors
  /// are reported.
  Stream<Uint8List> readBlob(String projectId, String blobId, SecureBuffer key) {
    _checkUnlocked();
    return decryptFile(layout.blobFile(projectId, blobId), key);
  }

  /// Deletes file [blobId] of the project. A file that's already gone is fine.
  Future<void> deleteBlob(String projectId, String blobId) async {
    _checkUnlocked();
    final file = layout.blobFile(projectId, blobId);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Encrypts [image] as the project's cover with [key].
  Future<void> writeCover(String projectId, Uint8List image, SecureBuffer key, {String? coverId}) {
    _checkUnlocked();
    return encryptToFile(Stream.value(image), layout.coverFile(projectId, coverId), key);
  }

  /// The project's decrypted cover image, or null if it has none.
  Future<Uint8List?> readCover(String projectId, SecureBuffer key, {String? coverId}) async {
    _checkUnlocked();
    final file = layout.coverFile(projectId, coverId);
    if (!await file.exists()) {
      return null;
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in decryptFile(file, key)) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Future<void> deleteCover(String projectId, {String? coverId}) async {
    _checkUnlocked();
    final file = layout.coverFile(projectId, coverId);
    if (await file.exists()) {
      await file.delete();
    }
  }

  void _checkUnlocked() {
    if (isLocked) {
      throw StateError('The vault is locked');
    }
  }
}
