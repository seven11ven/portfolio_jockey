import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:portfolio_jockey/ui/preview/preview_views.dart';

import '../vault/test_helpers.dart';

/// A short silent WAV file (8 kHz mono, 16-bit).
Uint8List silentWav({int samples = 8000}) {
  final data = ByteData(44 + samples * 2);
  void ascii(int at, String text) => text.codeUnits.asMap().forEach((i, c) => data.setUint8(at + i, c));
  ascii(0, 'RIFF');
  data.setUint32(4, 36 + samples * 2, Endian.little);
  ascii(8, 'WAVEfmt ');
  data
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, 8000, Endian.little)
    ..setUint32(28, 16000, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  return data.buffer.asUint8List();
}

void main() {
  test('libmpv accepts every lockdown option and plays a local file loaded with loadfile', () async {
    ensureMediaReady();
    final player = Player(configuration: const PlayerConfiguration(protocolWhitelist: ['file']));
    addTearDown(player.dispose);
    final native = player.platform! as NativePlayer;
    await native.setProperty('ao', 'null'); // the container has no sound card
    for (final MapEntry(:key, :value) in lockedDownMpvOptions.entries) {
      await native.setProperty(key, value);
    }
    expect(await native.getProperty('cache-on-disk'), 'no');
    expect(await native.getProperty('ytdl'), 'no');
    expect(await native.getProperty('access-references'), 'no');
    expect(await native.getProperty('load-unsafe-playlists'), 'no');
    expect(await native.getProperty('stream-lavf-o'), contains('protocol_whitelist=file'));
    expect(await native.getProperty('demuxer-lavf-o'), contains('protocol_whitelist=file'));
    expect(await native.getProperty('sub-auto'), 'no');
    expect(await native.getProperty('config'), 'no', reason: "the user's mpv config and scripts are never loaded");

    final wav = File('${(await tempFolder()).path}/tone.wav');
    await wav.writeAsBytes(silentWav());
    final duration = player.stream.duration.firstWhere((d) => d > Duration.zero);
    await native.command(['loadfile', wav.path, 'replace']);
    expect(await duration.timeout(const Duration(seconds: 10)), const Duration(seconds: 1));
  });
}
