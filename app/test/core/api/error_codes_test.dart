import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/error_codes.dart';

void main() {
  test('ErrorCodes lists every code in contract section 2', () {
    final contract = File('../docs/api/contract.md').readAsStringSync();
    final start = contract.indexOf('## 2. Error codes');
    final end = contract.indexOf('\n## 3.', start);
    final section = contract.substring(start, end);
    final codes = RegExp(
      r'^\| `([a-z_]+)` \| \d{3} \|',
      multiLine: true,
    ).allMatches(section).map((m) => m[1]!).toSet();

    expect(codes, isNotEmpty);
    expect(ErrorCodes.contractCodes, codes);
  });
}
