# Keputusan migrasi Flutter

Permintaan terbaru mengganti Python/Flet desktop dengan Flutter untuk HP dan web. `launcher.py` dan dependensi Python aplikasi diganti dengan `lib/main.dart`, `pubspec.yaml`, konfigurasi VS Code, serta skrip menjalankan Flutter. Python hanya digunakan sebagai server statis opsional untuk mencoba build web.

UI → QParkService → ParkingRepository → SqliteParkingRepository. Domain berisi tipe data dan aturan murni. Service tidak mengimpor Flutter/SQLite; repository tidak mengimpor UI/service. Bootstrap memilih backend dan melakukan seed. SQLite native dan web memakai `assets/schema.sql` yang sama. API SQL Drift eksplisit tidak memerlukan code generation. Perubahan skema berikutnya harus menambah schemaVersion dan migrasi.

Sesi memiliki token acak dalam memori; login membuat sesi dan logout mencabutnya. Setiap tindakan memeriksa user aktif terkini dan role. Mutasi repository memeriksa aktor lagi di dalam transaksi. Password memakai PBKDF2-HMAC-SHA256 600.000 iterasi dan salt acak 24 byte; fixture tes memakai 1.000 iterasi tanpa mengubah default aplikasi.

Unique index parsial mencegah pelat aktif ganda. Kapasitas dihitung dari transaksi aktif; trigger menjaga batas kapasitas serta melarang perubahan/penghapusan riwayat lunas. Validasi, penulisan, dan pembacaan bukti terjadi sebelum commit. Error menyebabkan rollback. UI memiliki busy state; UPDATE bersyarat melindungi dari pembayaran ganda. Biaya dihitung ulang, dan perubahan total mengharuskan konfirmasi ulang.

Timestamp adalah epoch milidetik. Batas tanggal riwayat mengikuti waktu lokal perangkat dan mencakup seluruh hari terakhir. Satu lokasi diasumsikan memakai zona waktu yang sama dan jam perangkat yang benar. UI tidak mengizinkan edit waktu. Pergantian zona waktu perangkat bisa mengubah pengelompokan hari. Durasi 60 menit + 1 ms menjadi dua jam.

Uang dan kapasitas dibatasi pada integer eksak JavaScript 9.007.199.254.740.991 agar hasil HP/web sama. Uang bulat saja; `5000`, `5.000`, `Rp5.000` diterima. Pendapatan dihitung dari total biaya, bukan uang diterima.

Penyimpanan bersifat lokal, tanpa sinkronisasi antardevice. Browser menggunakan origin/profil terpisah. Mode in-memory dan IndexedDB multitab tidak aman ditolak. Menghapus data browser/uninstall aplikasi dapat menghapus database.

Database Python lama tidak dimigrasikan otomatis. Jika kelak dibutuhkan, backup terlebih dahulu, tetapkan zona waktu asal, konversikan timestamp ke epoch, petakan user/hash, dan validasi saldo/kapasitas dalam transaksi import atomik. Jangan menimpa file lama.

Konfirmasi form belum disimpan berlaku pada logout, perpindahan menu, dan navigasi balik dalam aplikasi. Penutupan paksa aplikasi/tab atau refresh browser tidak dijamin menampilkan konfirmasi; form yang belum disimpan tidak dipersistenkan. Transaksi yang sudah commit tetap tersimpan.
