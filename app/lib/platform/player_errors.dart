import '../bridge/player.dart';

/// mpv's error lines (media_kit's `error` stream), first match wins.
final _kinds = [
  (RegExp(r'HTTP error 403\b'), PlayerErrorKind.forbidden),
  (
    RegExp(
      r'connection refused|timed out|resolve hostname|unreachable|connection reset',
      caseSensitive: false,
    ),
    PlayerErrorKind.network,
  ),
  (
    RegExp(r'recognize file format|decod', caseSensitive: false),
    PlayerErrorKind.decode,
  ),
];

PlayerErrorKind classifyPlayerError(String mpvMessage) {
  for (final (pattern, kind) in _kinds) {
    if (pattern.hasMatch(mpvMessage)) return kind;
  }
  return PlayerErrorKind.other;
}
