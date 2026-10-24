// Spacing and radii only from the tokens (spec UI §2.7, §2.8).
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

const number = r'-?\d+(\.\d+)?';
final literal = RegExp(
  r'EdgeInsets(Directional)?\.\w+\([^)]*\b'
  '$number'
  r'\b|SizedBox(\.square)?\([^)]*\b(width|height|dimension)\s*:\s*'
  '$number'
  r'|\bGap\(\s*'
  '$number'
  r'|\b(Border)?Radius\.circular\(\s*'
  '$number',
);

void main() {
  test('no spacing literals outside design/', () {
    for (final bad in [
      'padding: EdgeInsets.all(16),',
      'padding: EdgeInsetsDirectional.only(start: 8),',
      'const EdgeInsets.symmetric(horizontal: 12.5)',
      'SizedBox(height: 24)',
      'SizedBox.square(dimension: 44)',
      'Gap(8)',
      'BorderRadius.circular(12)',
      'Radius.circular(28)',
    ]) {
      expect(offending([('sample', bad)], literal), hasLength(1), reason: bad);
    }
    for (final ok in [
      'padding: EdgeInsets.all(VSpace.s16),',
      'SizedBox(height: VSpace.s24)',
      'BorderRadius.circular(VRadius.small)',
    ]) {
      expect(offending([('sample', ok)], literal), isEmpty, reason: ok);
    }
    expect(offending(screens(), literal), isEmpty);
  });
}
