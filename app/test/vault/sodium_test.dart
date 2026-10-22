import 'dart:convert';
import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/vault/aead.dart';
import 'package:portfolio_jockey/vault/errors.dart';
import 'package:portfolio_jockey/vault/ids.dart';
import 'package:portfolio_jockey/vault/kdf.dart';
import 'package:portfolio_jockey/vault/native/sodium.dart';
import 'package:portfolio_jockey/vault/secure_buffer.dart';

import 'known_answers.dart';

void main() {
  final sodium = Sodium.instance;

  test('loads libsodium 1.0.18 or newer', () {
    final parts = sodium.version.split('.').map(int.parse).toList();
    expect(parts[0] * 1000000 + parts[1] * 1000 + parts[2], greaterThanOrEqualTo(1000018));
  });

  test('sizes come from libsodium and match the formats', () {
    expect(sodium.aeadKeyBytes, 32);
    expect(sodium.aeadNonceBytes, 24);
    expect(sodium.aeadTagBytes, 16);
    expect(sodium.streamKeyBytes, 32);
    expect(sodium.streamHeaderBytes, 24);
    expect(sodium.streamTagBytes, 17);
    expect(sodium.pwhashSaltBytes, 16);
  });

  test('the default Argon2id settings are libsodium MODERATE', () {
    final params = KdfParams.moderate();
    expect(params.opsLimit, 3);
    expect(params.memLimit, 256 * 1024 * 1024);
  });

  group('known answers from libsodium 1.0.18 test suite', () {
    test('XChaCha20-Poly1305 encrypts to the expected ciphertext', () {
      final key = SecureBuffer.takeBytes(fromHex(aeadKeyHex));
      addTearDown(key.dispose);
      final ciphertext = aeadEncrypt(
        utf8.encode(aeadMessage),
        ad: fromHex(aeadAdHex),
        nonce: fromHex(aeadNonceHex),
        key: key,
      );
      expect(toHex(ciphertext), aeadCiphertextHex);

      final plaintext = aeadDecrypt(ciphertext, ad: fromHex(aeadAdHex), nonce: fromHex(aeadNonceHex), key: key);
      expect(utf8.decode(plaintext!), aeadMessage);
    });

    test('XChaCha20-Poly1305 rejects a changed ciphertext or associated data', () {
      final key = SecureBuffer.takeBytes(fromHex(aeadKeyHex));
      addTearDown(key.dispose);
      final ciphertext = fromHex(aeadCiphertextHex)..[0] ^= 1;
      expect(aeadDecrypt(ciphertext, ad: fromHex(aeadAdHex), nonce: fromHex(aeadNonceHex), key: key), isNull);

      final ad = fromHex(aeadAdHex)..[0] ^= 1;
      expect(aeadDecrypt(fromHex(aeadCiphertextHex), ad: ad, nonce: fromHex(aeadNonceHex), key: key), isNull);
    });

    for (final vector in argon2idVectors) {
      test('Argon2id vector ${vector.index}', () async {
        final password = SecureBuffer.takeBytes(fromHex(vector.passwordHex));
        addTearDown(password.dispose);
        final params = KdfParams(opsLimit: vector.opsLimit, memLimit: vector.memLimit);
        final derive = deriveKey(password, fromHex(vector.saltHex), params, length: vector.outLength);

        if (vector.expectedHex == null) {
          await expectLater(derive, throwsA(isA<VaultException>()));
          return;
        }
        final key = await derive;
        addTearDown(key.dispose);
        expect(key.use((p) => toHex(p.asTypedList(key.length))), vector.expectedHex);
      });
    }
  });
}
