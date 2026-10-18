import 'package:test/test.dart';

import '../tool/check_log.dart';

String ev(int t, String event, int index, [String detail = '']) =>
    '{"t": $t, "event": "$event", "index": $index, "detail": "$detail"}';

void main() {
  test('sums listened time and measures the gap between tracks', () {
    final s = summarize([
      ev(0, 'load', 0),
      ev(500, 'start', 0),
      ev(200500, 'end', 0),
      ev(200500, 'load', 1),
      ev(201300, 'start', 1),
      ev(401300, 'end', 1),
    ]);
    expect(s.listenedMs, 400000);
    expect(s.errors, 0);
    expect(s.maxGapMs, 800);
  });

  test('counts errors and an unfinished last track up to the last event', () {
    final s = summarize([
      ev(0, 'start', 0),
      ev(1000, 'error', 0, 'boom'),
      ev(5000, 'slow_load', 0, '2500'),
    ]);
    expect(s.errors, 1);
    expect(s.listenedMs, 5000);
  });

  test('passes only with an hour of listening and no error', () {
    expect(Summary(listenedMs: 3600000, errors: 0, maxGapMs: 0).ok, isTrue);
    expect(Summary(listenedMs: 3599999, errors: 0, maxGapMs: 0).ok, isFalse);
    expect(Summary(listenedMs: 3600000, errors: 1, maxGapMs: 0).ok, isFalse);
  });
}
