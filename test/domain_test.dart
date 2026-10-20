import 'package:flutter_test/flutter_test.dart';
import 'package:qpark/domain/errors.dart';
import 'package:qpark/domain/models.dart';
import 'package:qpark/domain/rules.dart';
import 'package:qpark/logic/security.dart';

void main() {
  test(
    'AT-04 pelat kapital tanpa spasi',
    () => expect(normalizePlate(' ab\t1234\ncd '), 'AB1234CD'),
  );
  for (final value in ['', '  ', 'A1', 'AB-123', 'ABCDEFGHIJKLM', 'à123']) {
    test(
      'AT-05 pelat tidak valid "$value"',
      () => expect(() => normalizePlate(value), throwsA(isA<QParkException>())),
    );
  }
  test('AT-07 format rupiah sah', () {
    for (final text in ['5000', '5.000', 'Rp5.000', ' rp 5.000 ']) {
      expect(parseRupiah(text), 5000);
    }
  });
  for (final value in [
    '1.5',
    '1,5',
    '-1',
    '',
    '1.00',
    '1 000',
    '0.000',
    '9007199254740992',
  ]) {
    test(
      'AT-07 rupiah tidak valid "$value"',
      () => expect(() => parseRupiah(value), throwsA(isA<QParkException>())),
    );
  }
  test('AT-11 kapasitas integer dan batas aman web', () {
    expect(parseInteger('0', 'Kapasitas'), 0);
    expect(parseInteger('$maxInteger', 'Kapasitas'), maxInteger);
    for (final v in ['-1', '1.1', '1e3', '9007199254740992']) {
      expect(
        () => parseInteger(v, 'Kapasitas'),
        throwsA(isA<QParkException>()),
      );
    }
  });
  final visit = Visit(
    id: 'TEST',
    plate: 'B123ABC',
    vehicle: Vehicle.motor,
    enteredAt: DateTime(2026, 10, 4, 23, 30),
    hourlyRate: 2000,
    entryOfficerId: 2,
    entryOfficerName: 'Petugas',
  );
  for (final (minutes, hours) in [(0, 1), (60, 1), (61, 2), (1440, 24)]) {
    test('AT-06 $minutes menit = $hours jam termasuk tengah malam', () {
      final q = calculateQuote(
        visit,
        visit.enteredAt.add(Duration(minutes: minutes)),
      );
      expect(q.hours, hours);
      expect(q.total, hours * 2000);
    });
  }
  test(
    'AT-06 satu milidetik lewat jam dibulatkan',
    () => expect(
      calculateQuote(
        visit,
        visit.enteredAt.add(const Duration(hours: 1, milliseconds: 1)),
      ).hours,
      2,
    ),
  );
  test(
    'AT-06 jam mundur ditolak',
    () => expect(
      () => calculateQuote(
        visit,
        visit.enteredAt.subtract(const Duration(milliseconds: 1)),
      ),
      throwsA(isA<QParkException>()),
    ),
  );
  test(
    'AT-10 rentang terbalik ditolak',
    () => expect(
      () => validateFilter(
        HistoryFilter(start: DateTime(2026, 10, 5), end: DateTime(2026, 10, 4)),
      ),
      throwsA(isA<QParkException>()),
    ),
  );
  test('AT-12 hash bersalt dan password salah ditolak', () async {
    final s = PasswordSecurity(iterations: 1000);
    final a = await s.hash('Petugas123!'), b = await s.hash('Petugas123!');
    expect(a, isNot(b));
    expect(a, isNot(contains('Petugas123!')));
    expect(await s.verify('Petugas123!', a), true);
    expect(await s.verify('salah', a), false);
    expect(await s.verify('salah', 'rusak'), false);
    expect(PasswordSecurity().iterations, 600000);
  });
}
