# Arsitektur dan asumsi

QPark adalah aplikasi Flutter untuk HP dan web yang selalu terhubung ke server terpusat. Tidak ada database transaksi di perangkat.

```
UI (lib/ui) → RemoteService (lib/logic/remote_service.dart)
            → RemoteRepository  → HTTP /api/*   → server/ (Python stdlib + SQLite)
            → SupabaseRemoteRepository → RPC qpark_request → supabase/migrations (PostgreSQL)
```

- `lib/bootstrap.dart` memilih backend: Supabase jika `SUPABASE_URL` dan `SUPABASE_PUBLISHABLE_KEY` diberikan saat build, selain itu server lokal (`API_BASE_URL`, default origin web atau `10.0.2.2:7357` di emulator).
- `lib/domain` berisi aturan dan model murni tanpa Flutter (nopol, biaya, status pelanggan, bukti transaksi, QR penghubung).
- `lib/data` berisi akses jaringan dan penyimpanan preferensi; `lib/logic` berisi state aplikasi, polling adaptif, retry idempoten, dan autentikasi pelanggan.
- Waktu, tarif, kapasitas, dan nominal dihitung di server. Klien tidak mengirim jam atau jumlah uang untuk pembayaran QR.
- Mutasi penting membawa `operation_key`. Jika respons hilang (timeout/5xx), klien mengulang dengan kunci yang sama sehingga transaksi tidak tercatat dua kali.
- Transaksi yang belum terkonfirmasi disimpan di SharedPreferences per akun dan dapat dikirim ulang.

## Pembersihan kode lama

Versi awal Flutter menyimpan transaksi lokal melalui Drift/SQLite (`QParkService`, `ParkingRepository`, `SqliteParkingRepository`, `assets/schema.sql`, `web/sqlite3.wasm`, `web/drift_worker.dart.js`) beserta halaman riwayat/pengaturan/petugas lama. Sejak v3 jalur tersebut tidak lagi dipanggil oleh aplikasi dan telah dihapus bersama dependensi `drift`, `drift_flutter`, `path_provider`, `cryptography`, `cryptography_flutter`, `cupertino_icons`, dan `sqlite3`. Riwayat Git (commit `d983183` dan sebelumnya) menyimpan implementasi tersebut.

## Asumsi

- Satu lokasi parkir dengan zona waktu yang sama; waktu bersumber dari server.
- Pembayaran QRIS dan gerbang bersifat simulasi.
- Uang dan kapasitas adalah bilangan bulat.
- Konfirmasi form belum disimpan berlaku pada logout dan perpindahan menu dalam aplikasi; penutupan paksa tab tidak dijamin menampilkan konfirmasi.
