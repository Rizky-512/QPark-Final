# Keamanan dan keandalan prototipe — 31 Oktober 2026

Pembayaran QR dan gerbang tetap simulasi. Perubahan ini melindungi tiket,
mengurangi pembacaan berulang, dan menyediakan pemulihan yang dapat diuji.

## Mengaktifkan versi ini

1. Backup database sebelum pemasangan.
2. Untuk Supabase, pasang migrasi berurutan sampai
   `supabase/migrations/202610310001_customer_access.sql` melalui SQL Editor
   atau alur migrasi proyek. Migrasi `202610290005_fast_forecast_samples.sql`
   yang sudah ada tetap dipertahankan. **Pengujian lokal tidak memasang migrasi
   ke Supabase online.**
3. Gunakan build Flutter terbaru. Frontend lama tidak menyediakan kode
   penghubung. Pasang backend dan frontend dalam satu jadwal pembaruan.
4. Untuk server Python, perubahan tabel dibuat saat server dijalankan ulang.
   Data lama tidak dihapus. `buka_web.bat` memeriksa kesesuaian build.

## Alur pelanggan dan petugas

- Pelanggan menyimpan/memilih nopol lalu menekan **Buat kode untuk petugas**
  pada Beranda. Kode berlaku 15 menit dan terikat pada nopol tersebut.
- Petugas mencatat masuk seperti biasa. Pada bagian **Hubungkan tiket pelanggan**
  di halaman Masuk, petugas memasukkan nopol dan kode, mencocokkan kendaraan
  secara fisik, lalu menekan **Verifikasi & hubungkan tiket**.
- Pelanggan memuat ulang Beranda atau menunggu sinkronisasi berikutnya.
  Tiket, tagihan dan riwayat hanya tersedia untuk pemilik yang sudah dihubungkan.
- Akun Google terikat pada `auth.uid()`. Demo terikat pada rahasia acak perangkat
  (192 bit), disimpan lokal; backend menyimpan hash-nya. Demo di perangkat lain
  atau setelah penyimpanan browser dihapus tidak mewarisi akses.
- Nopol bukan kredensial. Menambahkan nopol akun lain tidak membuka tiketnya.
  Menghubungkan ulang tiket ke pemilik lain ditolak. Tiket lama yang belum
  terhubung tetap dapat dilayani secara manual oleh petugas; riwayat lama tidak
  otomatis diberikan kepada siapa pun yang mengetik nopolnya.
- Kode yang masih berlaku dapat dikirim ulang untuk pemilik yang sama setelah
  respons hilang. Kode baru menggantikan kode sebelumnya. Jangan membagikan kode
  kepada orang selain petugas yang memeriksa kendaraan.

RPC bisnis lama diubah menjadi fungsi privat `qpark_request_core`; role `anon`
dan `authenticated` tidak dapat memanggilnya langsung. Tabel penghubung
menggunakan RLS dan tidak dapat dibaca/diubah klien. API HTTP Python selalu
memeriksa identitas `X-QPark-Customer`; pemanggilan Store langsung adalah API
internal tepercaya, bukan endpoint publik.

## Sinkronisasi dan kegagalan jaringan

- Petugas atau tiket aktif: setiap 5 detik setelah sinkronisasi selesai.
- Kondisi tanpa tiket aktif: setiap 30 detik. Riwayat diperbarui setiap 30 detik
  hanya saat halaman aktif, aplikasi di depan, dan koneksi terakhir berhasil.
- Aplikasi di latar belakang menghentikan polling; kembali ke depan langsung
  menyinkronkan. Permintaan yang sudah berjalan dapat selesai, tetapi respons
  dari akun/nopol sebelumnya tidak diterapkan ke akun/nopol baru.
- Kegagalan berturut-turut menambah jeda menjadi 5, 10, 20, 40, lalu 60 detik.
  Keberhasilan mengembalikan interval normal. Tombol muat ulang tetap tersedia.
- Permintaan API dibatasi 12 detik; timeout tidak membuktikan operasi gagal
  di server. Pembacaan paralel lewat `sync()` berbagi satu proses.
- Klik mutasi identik yang bersamaan berbagi satu permintaan. Operasi idempoten
  yang timeout, terkena 408/429 atau error server mempertahankan kunci operasi.
  Tekan **Periksa & coba ulang** untuk mengirim kunci yang sama. Pembayaran
  tidak dicoba ulang otomatis tanpa tindakan pengguna.
- Antrean pelanggan dipisahkan per akun/perangkat dan dapat dipulihkan setelah
  restart. Antrean petugas hanya di memori dan dibersihkan saat logout; setelah
  restart petugas harus memeriksa hasil di monitor/riwayat sebelum mengulang.
  Antrean versi lama tanpa identitas tidak diputar ulang otomatis.
- Respons sukses mutasi ditampilkan tanpa menunggu pembacaan ulang selesai.
  Ketersediaan menampilkan waktu data terakhir; data lama bukan jaminan slot.

## Pemantauan

Ikon **Status koneksi** pada app bar petugas/admin menampilkan jumlah permintaan,
kegagalan, timeout, p95 durasi 100 permintaan terakhir, interval sinkronisasi,
dan kode error terakhir. Angka hanya untuk sesi aplikasi ini dan bukan SLA server.
Tidak ada pengiriman telemetri ke layanan pihak ketiga.

Server Python mencatat JSON dengan request ID, status HTTP, durasi dan kode
error, tanpa URL/query, nopol, body, token atau rahasia perangkat. Header
`X-Request-ID` membantu penelusuran. Untuk Supabase gunakan log proyek dan
metrik database yang sudah tersedia; konfigurasi alarm eksternal belum dipasang.

## Backup dan pemulihan

Server Python membuat backup saat mulai dan setiap 24 jam selama proses hidup,
ke folder `backups` di sebelah database. Backup menggunakan SQLite online backup
dan memeriksa integritas, termasuk transaksi WAL yang sudah committed.

```powershell
python -m server.app --backup-dir backup --backup-interval-hours 24
python scripts/backup_database.py data/qpark_server_v3.db backup/manual.db
python scripts/restore_database.py backup/manual.db data/qpark_restored.db
```

Pemulihan hanya ke nama baru dan menolak penimpaan database. Setelah valid,
hentikan server lama lalu jalankan dengan `--db data/qpark_restored.db`.
Backup gagal dicatat sebagai `backup_failed`; berhasil sebagai `backup_ok`.
Pantau ruang disk: backup tidak dihapus otomatis. Salin backup penting ke media
lain; backup pada disk yang sama tidak melindungi kerusakan disk.
`--backup-interval-hours 0` menonaktifkan backup otomatis.

Backup ini khusus SQLite lokal. Backup terjadwal/PITR Supabase harus diaktifkan
dan diuji pada proyek online sesuai fasilitas yang tersedia; belum diubah oleh
pekerjaan ini. Jangan menjalankan utilitas SQLite pada database Supabase.

## Pengujian

```powershell
flutter analyze
flutter test
python -m unittest discover -s server/tests -v
python scripts/test_supabase_local.py --container NAMA_CONTAINER_POSTGRES_UJI
```

Skrip SQL membuat database uji bernama acak, menjalankan semua migrasi dan tes
akses, lalu menghapus hanya database uji yang dibuatnya. Gunakan container
PostgreSQL khusus pengujian. Mock `auth.uid()` menguji aturan kepemilikan;
pengujian OAuth Google nyata masih perlu dilakukan pada staging.

Skenario mencakup akses lintas pelanggan, tiket tanpa penghubung, manipulasi
scope riwayat, kode kedaluwarsa, akun nonaktif, pembayaran berulang, respons
hilang, 429, timeout, pergantian akun/nopol saat permintaan berjalan, polling
latar belakang, perebutan slot terakhir, pemakaian ulang QR, backup WAL, dan
penolakan backup rusak. Tidak ada transaksi uang nyata.

Hasil validasi lokal pada 31 Oktober 2026:
- `flutter analyze`: tidak ada masalah.
- `flutter test`: 88 tes lolos.
- Tes Python: 72 tes dijalankan; 71 lolos, 1 tes ML opsional dilewati
  karena dependensi ML tidak terpasang. Tes pemulihan juga dijalankan ulang
  setelah penambahan backup otomatis dan lolos.
- Seluruh 9 migrasi berhasil dipasang pada PostgreSQL 17 dalam container uji;
  regresi akses tiket, izin RPC, pembayaran berulang, isolasi riwayat dan
  kedaluwarsa kode lolos. Database uji dihapus oleh skrip; container dihentikan.
- Ini bukan hasil uji beban produksi atau pengujian OAuth langsung di Supabase online.
- Build web release berhasil; manifest `rilis/source_manifest.json` cocok dengan source terbaru.
