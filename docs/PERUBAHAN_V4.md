# Addendum kebutuhan QPark 4 — 13 Oktober 2026

Permintaan pengguna terbaru menjadi acuan untuk perbedaan terhadap PRD/SRS yang disertakan. Implementasi merupakan revisi proyek Flutter existing, bukan proyek baru. Tema, kartu, tombol, warna hijau, sidebar, serta navigasi HP dipertahankan. Navigasi sidebar kini dapat digulir agar menu admin tidak terpotong.

| Aspek | Keputusan v4 |
|---|---|
| Aktor | Admin, Petugas, Pengendara |
| Akun awal | admin/admin123 dan petugas/petugas123; pelanggan tanpa akun |
| Jenis kendaraan | Mobil dan Motor |
| Input masuk | Manual tanpa foto atau gambar dari kamera/pemilihan berkas; verifikasi fisik petugas tetap wajib |
| Pembayaran | QR simulasi tetap tersedia; tambah konfirmasi pembayaran manual oleh staf |
| Keluar manual | Pelunasan + izin keluar setelah uang diterima dan nopol cocok; konfirmasi lewat tetap terpisah |
| Riwayat | Staf seluruh sesi; pelanggan berdasarkan nopol yang dipilih; filter tanggal masuk WIB, jenis, metode, dan pagination |
| Admin | Kelola tarif/kapasitas serta akun/password/peran/status aktif; tidak dapat menonaktifkan atau menurunkan perannya sendiri |
| Tarif awal | Mobil Rp7.000 dari kesepakatan terbaru; Motor Rp2.000 dari source versi lama |
| Kapasitas | Asumsi kerja 20 gabungan, karena pembagian kapasitas mobil/motor belum ditentukan; dapat diedit admin |
| Aturan waktu | Minimum satu jam, pembulatan jam penuh ke bawah; snapshot 5 menit; jendela pembayaran 15 menit; izin 120 detik |

## Arsitektur dan konsistensi

- Flutter tetap menjadi antarmuka; HTTP server Python/SQLite menjadi sumber transaksi bersama.
- `server/management.py` menambahkan migrasi, riwayat, manajemen admin, serta pembayaran manual pada repository yang sama.
- Peran diperiksa pada endpoint admin oleh server, bukan hanya melalui menu tersembunyi.
- Tagihan yang dipakai QR dan manual sama. Indeks unik pelunasan dan transaksi SQLite menghindari pembayaran ganda. Jika QR lebih dulu melunasi, petugas wajib memuat ulang sebelum menerima pembayaran manual.
- Manual mencatat metode, uang diterima, kembalian, waktu, dan ID petugas. Pelunasan, jendela, serta izin ditulis dalam satu transaksi. Retry dengan kunci sama tidak menambah pembayaran atau izin baru.
- Tarif disalin ke sesi saat masuk. Penalti mengikuti tarif sesi tersebut, termasuk jika admin kemudian mengubah tarif.
- Riwayat server memakai filter SQL dan batas 50 sesi per halaman. UI hanya memperbarui halaman riwayat yang sedang terbuka setiap lima detik. Status tiket/kapasitas tetap dipolling dua detik.
- Customer tetap tanpa akun sesuai keputusan sebelumnya. Pembatasan riwayat berdasarkan nopol tidak memverifikasi kepemilikan, sehingga data uji terkendali digunakan untuk prototipe.
- Pending operasi admin/petugas tidak dibawa sebagai operasi aktif setelah logout/restart. Password disimpan PBKDF2 bersalt; token sesi berupa digest pada database.

## Migrasi

Nama database v3 dipertahankan. Migrasi skema menambah kolom tanpa menghapus sesi/tagihan/QR. Akun default disetel sekali pada migrasi skema 2. Login sebelumnya milik admin/petugas default dicabut. Migrasi tidak mengulang reset password ketika server dinyalakan kembali. Riwayat tunai v2 tetap merupakan arsip terpisah, bukan sesi aktif yang ditebak statusnya.

## Batas

QRIS dan palang merupakan simulasi; kamera CCTV nyata dan deployment internet bukan bagian revisi ini. Kapasitas gabungan serta tarif motor merupakan asumsi yang dinyatakan dan dapat disesuaikan admin. Admin menggunakan penonaktifan akun untuk mempertahankan keterlacakan transaksi, bukan penghapusan catatan petugas permanen.
