import 'package:flutter_test/flutter_test.dart';
import 'package:qpark/domain/errors.dart';
import 'package:qpark/domain/rules.dart';

void main() {
  test(
    'AT-04 pelat kapital tanpa spasi',
    () => expect(normalizePlate(' ab\t1234\ncd '), 'AB1234CD'),
  );
  for (final value in ['', '  ', 'AB-123', 'A' * 33, 'à123']) {
    test(
      'AT-05 pelat tidak valid "$value"',
      () => expect(() => normalizePlate(value), throwsA(isA<QParkException>())),
    );
  }
  test('Pelat mengikuti kontrak server 1–32 karakter', () {
    for (final value in ['A', 'A1', 'ABCDEFGHIJKLM', 'A' * 32]) {
      expect(normalizePlate(value), value);
    }
  });
}
