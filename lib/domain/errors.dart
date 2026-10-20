import 'models.dart';

/// Pesan aman yang dapat ditampilkan langsung kepada pengguna.
class QParkException implements Exception {
  const QParkException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SessionExpired extends QParkException {
  const SessionExpired()
    : super(
        'Sesi telah berakhir atau akun dinonaktifkan. Silakan masuk kembali.',
      );
}

class PriceChanged extends QParkException {
  const PriceChanged(this.quote)
    : super(
        'Biaya berubah karena durasi bertambah. Periksa total dan konfirmasi kembali.',
      );
  final Quote quote;
}

class StorageException extends QParkException {
  const StorageException()
    : super(
        'Data tidak dapat dibaca atau disimpan. Coba lagi dan periksa penyimpanan perangkat.',
      );
}
