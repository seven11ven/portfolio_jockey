/// The shortest passphrase a new vault accepts.
const int minimumPassphraseLength = 12;

/// How strong a new passphrase looks, from 0 (too short) to 4.
///
/// A rough guide for the strength bar, not a guarantee: length matters most,
/// then several words or a mix of character kinds.
int passphraseStrength(String passphrase) {
  final length = passphrase.runes.length;
  if (length < minimumPassphraseLength) {
    return 0;
  }
  var score = 1;
  if (length >= 16) {
    score++;
  }
  if (length >= 24) {
    score++;
  }
  final words = passphrase.trim().split(RegExp(r'\s+')).where((w) => w.length >= 3).length;
  final kinds = [
    RegExp('[a-z]'),
    RegExp('[A-Z]'),
    RegExp('[0-9]'),
    RegExp(r'[^a-zA-Z0-9\s]'),
  ].where((kind) => kind.hasMatch(passphrase)).length;
  if (words >= 3 || kinds >= 3) {
    score++;
  }
  return score > 4 ? 4 : score;
}

String strengthLabel(int strength) => switch (strength) {
  0 => 'Too short. Use at least $minimumPassphraseLength characters, or several words.',
  1 => 'Fair. Longer is better.',
  2 => 'Good.',
  3 => 'Strong.',
  _ => 'Very strong.',
};
