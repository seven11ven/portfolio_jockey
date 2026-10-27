/// Base class for every failure the vault reports.
class VaultException implements Exception {
  const VaultException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// libsodium is missing, too old, or failed to start.
class SodiumUnavailable extends VaultException {
  const SodiumUnavailable(super.message);
}

/// The passphrase didn't unlock the vault.
///
/// A damaged vault file looks the same as a wrong passphrase: either way the
/// master key fails to decrypt.
class WrongPassphrase extends VaultException {
  const WrongPassphrase() : super('Wrong passphrase, or the vault file is damaged');
}

/// Encrypted data failed its integrity check: it was changed, cut short,
/// reordered or swapped with other data.
class TamperedData extends VaultException {
  const TamperedData(super.message);
}

/// A vault file isn't in a format this version of the app understands.
class VaultFormatError extends VaultException {
  const VaultFormatError(super.message);
}

/// No vault exists at the storage location.
class VaultNotFound extends VaultException {
  const VaultNotFound(super.message);
}

/// A vault already exists at the storage location.
class VaultAlreadyExists extends VaultException {
  const VaultAlreadyExists(super.message);
}
