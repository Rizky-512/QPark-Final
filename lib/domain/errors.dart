/// Pesan aman yang dapat ditampilkan langsung kepada pengguna.
class QParkException implements Exception {
  const QParkException(this.message);
  final String message;
  @override
  String toString() => message;
}
