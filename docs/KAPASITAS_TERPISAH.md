# Kapasitas Mobil/Motor dan beranda publik

Beranda awal menampilkan kapasitas, jumlah terisi, dan sisa slot Mobil dan Motor tanpa login. Data yang belum berhasil diperbarui ditandai sebagai data lama. Angka ketersediaan bukan reservasi; server memvalidasi lagi ketika kendaraan masuk.

Admin mengatur kapasitas kedua kategori melalui pengaturan. Nilai nol menutup kategori tersebut. Kapasitas tidak dapat diturunkan di bawah jumlah kendaraan aktif. Pembayaran tidak melepaskan slot: petugas harus mengonfirmasi kendaraan sudah keluar.

Pelanggan memilih Mobil atau Motor saat menyimpan nopol. Nopol lama yang belum memiliki kategori dapat dilengkapi melalui edit kendaraan. Pendaftaran dan login tidak diwajibkan untuk parkir. Petugas mengetik nopol; kategori tersimpan digunakan otomatis, sedangkan nopol belum terdaftar memerlukan pilihan Masuk Mobil atau Masuk Motor. Verifikasi nopol dan kendaraan fisik tetap diperlukan. Kategori kendaraan aktif tidak dapat diubah.

Registri kategori tidak memberikan akses tiket. Akses tiket pelanggan tetap mengikuti kode penghubung dan pemeriksaan kepemilikan yang sudah ada.

## Migrasi

Supabase membutuhkan `202610310001_customer_access.sql` dan `202611220001_vehicle_capacity.sql`, berurutan. Keduanya telah diterapkan ke project QPark pada 22 November 2026. Backend Python memigrasikan pengaturan saat inisialisasi.

Kapasitas gabungan lama dibagi menjadi dua, dengan penyesuaian agar masing-masing kategori tetap menampung kendaraan aktif. Database kosong dengan kapasitas lama 20 menjadi 10 Mobil dan 10 Motor. Admin dapat mengubah pembagian ini. Transaksi lama tidak dihapus.

## Verifikasi

- Flutter: 112 tes lulus; tiga tes UI kategori diuji ulang setelah penyesuaian pilihan kendaraan tidak terdaftar. Analisis Dart tanpa masalah.
- Python: suite 77 tes lulus dengan satu dilewati; tiga tes kategori terakhir lulus, termasuk kapasitas nol dan perebutan slot terakhir.
- PostgreSQL: seluruh migrasi serta tes akses pelanggan dan kapasitas terpisah lulus pada database pengujian sementara.
- API Supabase publik merespons tanpa login dengan dua kategori terpisah.

## Perapian repository

Direktori prototipe Flet `QPark`, `docs/legacy_v2`, dan `docs/legacy_v3` tidak digunakan oleh aplikasi aktif dan dikeluarkan dari Git versi terbaru (98 berkas). Arsip tetap tersedia pada [commit f71d823](https://github.com/Rizky-512/QPark-Final/tree/f71d823). Data lokal tidak dihapus.

Source aktif berada di `lib`, backend lokal di `server`, dan backend cloud di `supabase`. `rilis/web` tetap disimpan karena digunakan oleh Vercel dan launcher tanpa Flutter SDK. Perapian arsip terutama menyederhanakan repository; arsip tersebut sebelumnya tidak termasuk APK.
