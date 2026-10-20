/// Konfigurasi publik; jangan menyimpan secret backend di aplikasi klien.
abstract final class AppConfig {
  static const backend = String.fromEnvironment(
    'DB_BACKEND',
    defaultValue: 'sqlite',
  );
  static const databaseName = 'qpark_flutter_v1';
}
