# Rencana Supabase — belum diimplementasikan

Implementasikan `SupabaseParkingRepository` sesuai `ParkingRepository`, lalu pilih melalui `DB_BACKEND` di bootstrap. UI tetap memanggil layanan yang sama. Tujuan migrasi adalah berbagi data satu lokasi antara HP dan web.

## Skema PostgreSQL

Gunakan `assets/schema.sql` sebagai acuan users/profiles, tarif_parkir, kapasitas_parkir, transaksi_parkir. Ganti primary key auto increment dengan identity/UUID, uang BIGINT dengan batas integer eksak web, dan waktu timestamptz UTC. Batas tanggal laporan memakai zona waktu lokasi yang ditetapkan. Pertahankan CHECK rincian aktif/lunas, foreign key, indeks pelat aktif unik parsial, indeks status/jenis/waktu keluar, serta trigger transaksi lunas immutable.

Gunakan Supabase Auth dan profil role/aktif server. Jangan menjadikan hash lokal di browser sebagai autentikasi server; lakukan reset/migrasi akun secara aman.

## Transaksi atomik melalui RPC

`record_entry(plate, vehicle, request_id)`: ambil identitas dari auth.uid(), cek petugas aktif, normalisasi pelat, kunci baris konfigurasi jenis dengan SELECT FOR UPDATE, cek kapasitas/duplikat, ambil waktu server, snapshot tarif, INSERT dan kembalikan bukti dalam satu transaksi.

`complete_payment(id, cash, expected_total, request_id)`: cek aktor, kunci kunjungan aktif FOR UPDATE, hitung ulang menggunakan waktu server dan tarif snapshot. Jika biaya berbeda, kembalikan quote terbaru tanpa perubahan data. Setelah konfirmasi baru, validasi tunai dan UPDATE seluruh rincian lunas atomik, lalu kembalikan bukti. Request ID unik/idempotensi mencegah pembayaran ganda saat retry jaringan.

Perubahan kapasitas mengunci baris yang sama dengan RPC masuk; tidak boleh di bawah jumlah aktif. Tarif baru hanya memengaruhi kunjungan baru. Pendapatan adalah SUM(total_biaya) pada transaksi selesai, dengan filter tanggal keluar/jenis.

## Row Level Security

Aktifkan RLS semua tabel. Identitas dan role diverifikasi di server; menu UI bukan batas keamanan. Petugas aktif membaca ringkasan/kunjungan sesuai lokasi, mutasi sensitif melalui RPC; Admin mengelola pengaturan/petugas dan agregasi pendapatan. Status aktif harus diperiksa pada setiap operasi termasuk sesi lama.

Batasi EXECUTE fungsi, tetapkan search_path, audit SECURITY DEFINER bila dipakai. Service-role key hanya pada server/Edge Function, tidak di Dart, `.env` klien, hasil build, atau ZIP. Kunci publishable/anon baru digunakan setelah kebijakan RLS diuji. Uji dua perangkat serentak, offline/retry, role ditolak, dan deaktivasikan akun sebelum backend produksi diaktifkan.
