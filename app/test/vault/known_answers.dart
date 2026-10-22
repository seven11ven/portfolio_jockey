// Known-answer values copied by script from libsodium 1.0.18's own test suite
// (test/default/pwhash_argon2id.c/.exp and aead_xchacha20poly1305.c/.exp), taken
// from the official release tarball after its minisign signature was verified
// (SHA-256 6f504490b342a4f8a4c4a02fc9b866cbef8622d5df4e5452b46be121e46636c1).

final class Argon2idVector {
  const Argon2idVector({required this.index, required this.passwordHex, required this.saltHex, required this.outLength, required this.opsLimit, required this.memLimit, required this.expectedHex});

  final int index;
  final String passwordHex;
  final String saltHex;
  final int outLength;
  final int opsLimit;
  final int memLimit;

  /// Null when libsodium is expected to refuse the settings.
  final String? expectedHex;
}

const List<Argon2idVector> argon2idVectors = [
  Argon2idVector(
    index: 0,
    passwordHex: 'a347ae92bce9f80f6f595a4480fc9c2fe7e7d7148d371e9487d75f5c23008ffae065577a928febd9b1973a5a95073acdbeb6a030cfc0d79caa2dc5cd011cef02c08da232d76d52dfbca38ca8dcbd665b17d1665f7cf5fe59772ec909733b24de97d6f58d220b20c60d7c07ec1fd93c52c31020300c6c1facd77937a597c7a6',
    saltHex: '5541fbc995d5c197ba290346d2c559de',
    outLength: 155,
    opsLimit: 5,
    memLimit: 7256678,
    expectedHex: '18acec5d6507739f203d1f5d9f1d862f7c2cdac4f19d2bdff64487e60d969e3ced615337b9eec6ac4461c6ca07f0939741e57c24d0005c7ea171a0ee1e7348249d135b38f222e4dad7b9a033ed83f5ca27277393e316582033c74affe2566a2bea47f91f0fd9fe49ece7e1f79f3ad6e9b23e0277c8ecc4b313225748dd2a80f5679534a0700e246a79a49b3f74eb89ec6205fe1eeb941c73b1fcf1',
  ),
  Argon2idVector(
    index: 3,
    passwordHex: '027b6d8e8c8c474e9b69c7d9ed4f9971e8e1ce2f6ba95048414c3970f0f09b70e3b6c5ae05872b3d8678705b7d381829c351a5a9c88c233569b35d6b0b809df44b6451a9c273f1150e2ef8a0b5437eb701e373474cd44b97ef0248ebce2ca0400e1b53f3d86221eca3f18eb45b702b9172440f774a82cbf1f6f525df30a6e293c873cce69bb078ed1f0d31e7f9b8062409f37f19f8550aae',
    saltHex: 'eb2a3056a09ad2d7d7f975bcd707598f',
    outLength: 5,
    opsLimit: 4,
    memLimit: 1397645,
    expectedHex: null,
  ),
  Argon2idVector(
    index: 4,
    passwordHex: '4a857e2ee8aa9b6056f2424e84d24a72473378906ee04a46cb05311502d5250b82ad86b83c8f20a23dbb74f6da60b0b6ecffd67134d45946ac8ebfb3064294bc097d43ced68642bfb8bbbdd0f50b30118f5e',
    saltHex: '39d82eef32010b8b79cc5ba88ed539fb',
    outLength: 190,
    opsLimit: 3,
    memLimit: 1432947,
    expectedHex: '08d8cd330c57e1b4643241d05bb468ba4ee4e932cd0858816be9ef15360b27bbd06a87130ee92222be267a29b81f5ae8fe8613324cfc4832dc49387fd0602f1c57b4d0f3855db94fb7e12eb05f9a484aed4a4307abf586cd3d55c809bc081541e00b682772fb2066504ff935b8ebc551a2083882f874bc0fae68e56848ae34c91097c3bf0cca8e75c0797eef3efde3f75e005815018db3cf7c109a812264c4de69dcb22322dbbcfa447f5b00ecd1b04a7be1569c8e556adb7bba48adf81d',
  ),
];

const String aeadKeyHex = '808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f';
const String aeadNonceHex = '07000000404142434445464748494a4b4c4d4e4f50515253';
const String aeadAdHex = '50515253c0c1c2c3c4c5c6c7';
const String aeadMessage = "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.";
const String aeadCiphertextHex = 'f8ebea4875044066fc162a0604e171feecfb3d20425248563bcfd5a155dcc47bbda70b86e5ab9b55002bd1274c02db35321acd7af8b2e2d25015e136b7679458e9f43243bf719d639badb5feac03f80a19a96ef10cb1d15333a837b90946ba3854ee74da3f2585efc7e1e170e17e15e563e77601f4f85cafa8e5877614e143e68420';
