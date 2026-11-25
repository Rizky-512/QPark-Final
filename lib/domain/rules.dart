import 'errors.dart';

/// Nopol mengikuti kontrak server: 1–32 huruf/angka kapital tanpa spasi.
String normalizePlate(String value) {
  final plate = value.toUpperCase().replaceAll(
    RegExp(r'\s', unicode: true),
    '',
  );
  if (!RegExp(r'^[A-Z0-9]{1,32}$').hasMatch(plate)) {
    throw const QParkException(
      'Nomor polisi harus berisi 1–32 huruf atau angka, tanpa tanda baca.',
    );
  }
  return plate;
}
