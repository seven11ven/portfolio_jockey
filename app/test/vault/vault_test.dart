import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/vault/errors.dart';
import 'package:portfolio_jockey/vault/kdf.dart';
import 'package:portfolio_jockey/vault/layout.dart';
import 'package:portfolio_jockey/vault/project_index.dart';
import 'package:portfolio_jockey/vault/vault.dart';
import 'package:portfolio_jockey/vault/vault_header.dart';

import 'test_helpers.dart';

void main() {
  test('create, lock and unlock with the right passphrase', () async {
    final root = await tempFolder();
    final vault = await Vault.create(root, 'correct horse', kdf: fastKdf);
    final id = await vault.createProject(ProjectIndex(name: 'Thesis'));
    vault.lock();
    expect(vault.isLocked, isTrue);

    final unlocked = await Vault.unlock(root, 'correct horse');
    addTearDown(unlocked.lock);
    expect((await unlocked.readIndex(id)).name, 'Thesis');
  });

  test('the vault file is exactly the documented header', () async {
    final root = await tempFolder();
    (await Vault.create(root, 'pass', kdf: fastKdf)).lock();
    final bytes = await VaultLayout(root).vaultFile.readAsBytes();
    expect(bytes.length, VaultHeader.length);
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'PJVT');
  });

  test('a wrong passphrase is refused', () async {
    final root = await tempFolder();
    (await Vault.create(root, 'right', kdf: fastKdf)).lock();
    await expectLater(Vault.unlock(root, 'wrong'), throwsA(isA<WrongPassphrase>()));
  });

  test('an empty passphrase is refused', () async {
    final root = await tempFolder();
    await expectLater(Vault.create(root, '', kdf: fastKdf), throwsArgumentError);
  });

  test('changing the salt, nonce or wrapped key makes unlocking fail', () async {
    final root = await tempFolder();
    (await Vault.create(root, 'pass', kdf: fastKdf)).lock();
    final file = VaultLayout(root).vaultFile;
    final original = await file.readAsBytes();
    for (final offset in [24, 40, 64, 111]) {
      await file.writeAsBytes(Uint8List.fromList(original)..[offset] ^= 1);
      await expectLater(Vault.unlock(root, 'pass'), throwsA(isA<WrongPassphrase>()), reason: 'byte $offset');
    }
  });

  test('changing the Argon2id settings makes unlocking fail', () async {
    final root = await tempFolder();
    (await Vault.create(root, 'pass', kdf: fastKdf)).lock();
    final file = VaultLayout(root).vaultFile;
    final changed = await file.readAsBytes();
    changed[8] = 2; // opslimit 1 -> 2: still in range, so only the integrity check catches it.
    await file.writeAsBytes(changed);
    await expectLater(Vault.unlock(root, 'pass'), throwsA(isA<WrongPassphrase>()));
  });

  test('out-of-range Argon2id settings are rejected before any work is done', () async {
    final root = await tempFolder();
    (await Vault.create(root, 'pass', kdf: fastKdf)).lock();
    final file = VaultLayout(root).vaultFile;
    final original = await file.readAsBytes();

    final hugeOps = Uint8List.fromList(original);
    ByteData.sublistView(hugeOps).setUint64(8, 1000000, Endian.little);
    await file.writeAsBytes(hugeOps);
    await expectLater(Vault.unlock(root, 'pass'), throwsA(isA<VaultFormatError>()));

    final hugeMemory = Uint8List.fromList(original);
    ByteData.sublistView(hugeMemory).setUint64(16, KdfParams.maxMemLimit + 1, Endian.little);
    await file.writeAsBytes(hugeMemory);
    await expectLater(Vault.unlock(root, 'pass'), throwsA(isA<VaultFormatError>()));
  });

  test('a damaged or foreign vault file is reported as such', () async {
    final root = await tempFolder();
    (await Vault.create(root, 'pass', kdf: fastKdf)).lock();
    final file = VaultLayout(root).vaultFile;
    final original = await file.readAsBytes();

    await file.writeAsBytes(original.sublist(0, 100));
    await expectLater(Vault.unlock(root, 'pass'), throwsA(isA<VaultFormatError>()));

    await file.writeAsBytes(Uint8List.fromList(original)..[0] = 0x58);
    await expectLater(Vault.unlock(root, 'pass'), throwsA(isA<VaultFormatError>()));

    await file.writeAsBytes(Uint8List.fromList(original)..[4] = 2);
    await expectLater(Vault.unlock(root, 'pass'), throwsA(isA<VaultFormatError>()));
  });

  test('a missing vault and a second vault are reported', () async {
    final root = await tempFolder();
    await expectLater(Vault.unlock(root, 'pass'), throwsA(isA<VaultNotFound>()));
    expect(await Vault.exists(root), isFalse);

    (await Vault.create(root, 'pass', kdf: fastKdf)).lock();
    expect(await Vault.exists(root), isTrue);
    await expectLater(Vault.create(root, 'other', kdf: fastKdf), throwsA(isA<VaultAlreadyExists>()));
  });

  test('changing the passphrase keeps existing projects readable', () async {
    final root = await tempFolder();
    final vault = await Vault.create(root, 'old', kdf: fastKdf);
    final id = await vault.createProject(ProjectIndex(name: 'Album'));
    vault.lock();

    await Vault.changePassphrase(root, 'old', 'new', kdf: fastKdf);

    await expectLater(Vault.unlock(root, 'old'), throwsA(isA<WrongPassphrase>()));
    final unlocked = await Vault.unlock(root, 'new');
    addTearDown(unlocked.lock);
    expect((await unlocked.readIndex(id)).name, 'Album');
  });

  test('changing the passphrase needs the current one', () async {
    final root = await tempFolder();
    (await Vault.create(root, 'old', kdf: fastKdf)).lock();
    await expectLater(Vault.changePassphrase(root, 'guess', 'new', kdf: fastKdf), throwsA(isA<WrongPassphrase>()));
    (await Vault.unlock(root, 'old')).lock();
  });

  test('a locked vault cannot read or write', () async {
    final root = await tempFolder();
    final vault = await Vault.create(root, 'pass', kdf: fastKdf);
    final id = await vault.createProject(ProjectIndex(name: 'P'));
    vault.lock();
    await expectLater(vault.readIndex(id), throwsStateError);
    await expectLater(vault.writeIndex(id, ProjectIndex(name: 'Q')), throwsStateError);
  });

  test('the default settings unlock with libsodium MODERATE', () async {
    final root = await tempFolder();
    (await Vault.create(root, 'moderate')).lock();
    final header = VaultHeader.parse(await File('${root.path}/.pj/vault').readAsBytes());
    expect(header.kdf.opsLimit, 3);
    expect(header.kdf.memLimit, 256 * 1024 * 1024);
    (await Vault.unlock(root, 'moderate')).lock();
  });
}
