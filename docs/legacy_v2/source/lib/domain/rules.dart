import 'errors.dart';
import 'models.dart';

// Batas integer eksak JavaScript: hasil sama di HP dan web.
const maxInteger = 9007199254740991;
String normalizePlate(String value) {
  final plate = value.toUpperCase().replaceAll(
    RegExp(r'\s', unicode: true),
    '',
  );
  if (!RegExp(r'^[A-Z0-9]{3,12}$').hasMatch(plate)) {
    throw const QParkException(
      'Nomor polisi harus berisi 3–12 huruf atau angka, tanpa tanda baca.',
    );
  }
  return plate;
}

int parseInteger(String value, String field) {
  final text = value.trim();
  final number = int.tryParse(text);
  if (!RegExp(r'^[0-9]{1,16}$').hasMatch(text) ||
      number == null ||
      number > maxInteger) {
    throw QParkException(
      '$field harus berupa bilangan bulat minimal 0 dan tidak terlalu besar.',
    );
  }
  return number;
}

int parseRupiah(String value, [String field = 'Uang diterima']) {
  final text = value.trim().replaceFirst(
    RegExp(r'^rp\s*', caseSensitive: false),
    '',
  );
  if (!RegExp(r'^(?:[0-9]+|[1-9][0-9]{0,2}(?:\.[0-9]{3})+)$').hasMatch(text)) {
    throw QParkException(
      '$field harus bulat, misalnya 5000 atau Rp5.000; tanpa pecahan.',
    );
  }
  return parseInteger(text.replaceAll('.', ''), field);
}

void validateFilter(HistoryFilter filter) {
  if (filter.from.isAfter(
    DateTime(filter.end.year, filter.end.month, filter.end.day),
  )) {
    throw const QParkException(
      'Tanggal akhir tidak boleh sebelum tanggal awal.',
    );
  }
}

/// Pembulatan milidetik: 60 menit + 1 ms menjadi dua jam.
Quote calculateQuote(Visit visit, DateTime now) {
  final duration = now.difference(visit.enteredAt);
  if (duration.isNegative) {
    throw const QParkException(
      'Waktu keluar tidak boleh sebelum waktu masuk. Periksa jam perangkat.',
    );
  }
  final hours = duration.inMilliseconds == 0
      ? 1
      : (duration.inMilliseconds + 3599999) ~/ 3600000;
  final total = hours * visit.hourlyRate;
  if (hours < 1 || total > maxInteger) {
    throw const QParkException('Total biaya terlalu besar untuk disimpan.');
  }
  return Quote(visit, now, duration, hours, total);
}
