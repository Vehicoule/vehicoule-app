import 'package:flutter_test/flutter_test.dart';
import 'package:vehicoule/bridge/player.dart';
import 'package:vehicoule/platform/player_errors.dart';

void main() {
  test('classify_player_errors', () {
    const samples = {
      'https: HTTP error 403 Forbidden': PlayerErrorKind.forbidden,
      'Failed to open https://cdn.example/a.m4a: HTTP error 403 Forbidden':
          PlayerErrorKind.forbidden,
      'Failed to open https://cdn.example/a.m4a: Connection refused':
          PlayerErrorKind.network,
      'tcp: Connection to tcp://cdn.example:443 failed: Connection timed out':
          PlayerErrorKind.network,
      'tcp: Failed to resolve hostname cdn.example: Name does not resolve':
          PlayerErrorKind.network,
      'Failed to recognize file format.': PlayerErrorKind.decode,
      'Failed to open https://cdn.example/a.m4a.': PlayerErrorKind.other,
      // A 403 in a URL is no HTTP 403.
      'Failed to open https://cdn.example/track/4031.m4a.':
          PlayerErrorKind.other,
      'Something odd.': PlayerErrorKind.other,
    };
    for (final MapEntry(key: line, value: kind) in samples.entries) {
      expect(classifyPlayerError(line), kind, reason: line);
    }
  });
}
