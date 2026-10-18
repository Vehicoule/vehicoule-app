// Usage: dart run tool/check_log.dart playback-log.jsonl
// Passes with >= 3600 s listened and zero `error` events; prints the largest
// end -> next start gap (the preload of spec 3.1 aims to shrink it).
import 'dart:convert';
import 'dart:io';

class Summary {
  Summary({required this.listenedMs, required this.errors, required this.maxGapMs});
  final int listenedMs;
  final int errors;
  final int maxGapMs;
  bool get ok => listenedMs >= 3600 * 1000 && errors == 0;
}

Summary summarize(Iterable<String> lines) {
  var listened = 0, errors = 0, maxGap = 0, lastT = 0;
  int? startedAt, lastEnd;
  for (final line in lines.where((l) => l.trim().isNotEmpty)) {
    final e = jsonDecode(line) as Map<String, dynamic>;
    final t = e['t'] as int;
    lastT = t;
    switch (e['event']) {
      case 'start':
        startedAt = t;
        if (lastEnd != null && t - lastEnd > maxGap) maxGap = t - lastEnd;
        lastEnd = null;
      case 'end':
        if (startedAt != null) listened += t - startedAt;
        startedAt = null;
        lastEnd = t;
      case 'error':
        errors++;
    }
  }
  if (startedAt != null) listened += lastT - startedAt;
  return Summary(listenedMs: listened, errors: errors, maxGapMs: maxGap);
}

void main(List<String> args) {
  final s = summarize(File(args.single).readAsLinesSync());
  stdout.writeln('listened ${s.listenedMs ~/ 1000} s, errors ${s.errors}, max gap ${s.maxGapMs} ms');
  stdout.writeln(s.ok ? 'PASS' : 'FAIL');
  exitCode = s.ok ? 0 : 1;
}
