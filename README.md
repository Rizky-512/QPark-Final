# QPark v5 — Login Customer & Analisis Parkir

Revisi lanjutan dari QPark Flutter yang sama. Styling hijau dan komponen tema dipertahankan. Pembayaran QR tetap tersedia; input kendaraan manual, pembayaran manual, admin, dan riwayat dipulihkan sesuai permintaan terbaru.

Tambahan v5: login customer sebagai halaman awal, opsi admin/petugas di bawah, dan menu **Analisis** khusus admin. Login Google dan penyimpanan nopol per akun melalui Supabase tersedia saat build diberi konfigurasi project. Lihat [panduan Supabase](docs/SUPABASE_MIGRASI.md), [perubahan v5](docs/PERUBAHAN_V5.md), dan [pengujian v5](docs/HASIL_PENGUJIAN_V5.md).

## Jalankan tanpa IDE

1. Ekstrak seluruh ZIP ke folder biasa.
2. Pasang Python **3.10+** dan pastikan perintah `py` atau `python` tersedia.
3. Buka **`buka_web.bat`**. Biarkan terminal terbuka.
4. Browser membuka `http://localhost:7357`. Halaman pertama adalah Login customer. Pilih Coba sebagai customer demo untuk melanjutkan.
5. Pilih **Login admin / petugas** untuk masuk menggunakan akun berikut.

| Peran | Username | Password awal |
|---|---|---|
| Admin | `admin` | `admin123` |
| Petugas | `petugas` | `petugas123` |
| Customer demo | Tanpa akun | Pilih tombol demo |

Password awal ini merupakan akun demo yang diminta untuk prototipe. Admin dapat mengubah password melalui **Kelola → Ubah akun**. Password disimpan sebagai hash bersalt. Perubahan password/peran/status mencabut sesi login akun yang bersangkutan.

Paket menyertakan build web terbaru. Flutter SDK tidak diperlukan untuk menjalankan build bawaan yang belum diubah. Jika source diubah, launcher meminta Flutter SDK untuk membangun ulang. Linux/macOS: `python3 scripts/launch.py --open`. Port alternatif: `py -3 scripts/launch.py --port 7360 --open`.

## Fitur setiap peran

| Peran | Fitur |
|---|---|
| Pengendara | Login Google dan nopol tersinkron lewat Supabase (atau mode demo lokal), lihat ketersediaan, tiket otomatis, pembayaran QR simulasi, QR keluar, riwayat nopol yang dipilih |
| Petugas | Catat mobil/motor, input manual atau gambar, verifikasi kendaraan, monitor aktif, konfirmasi pembayaran manual, uang diterima/kembalian, verifikasi QR keluar, konfirmasi lewat, seluruh riwayat |
| Admin | Semua fitur operasional petugas dan riwayat; pengaturan tarif/kapasitas; tambah/ubah akun admin atau petugas, password, dan status aktif |

Riwayat menyediakan pencarian nopol untuk staf, filter jenis kendaraan/metode pembayaran/tanggal masuk, total pembayaran, dan halaman berikut/sebelumnya. Pelanggan hanya melihat nopol yang dipilih pada Beranda. Pada tahap integrasi ini, daftar nopol akun dilindungi RLS Supabase, sedangkan endpoint riwayat/tiket pada API Python masih berbasis nopol; lihat batas migrasi pada panduan Supabase.

## Alur manual paling mudah

1. Petugas masuk dengan `petugas / petugas123`.
2. Menu **Masuk** → pilih **Mobil** atau **Motor** → ketik nopol → centang verifikasi → **Verifikasi & terima kendaraan**.
3. Foto tidak wajib pada mode manual. Jika ingin memakai kamera/foto uji, aktifkan **Gunakan gambar kendaraan**, pilih gambar, dan centang gambar terbaca.
4. Menu **Keluar → Bayar manual** → pilih kendaraan aktif → **Muat tagihan manual**.
5. Isi uang diterima dengan angka tanpa titik, misalnya `10000`. Kembalian dihitung otomatis.
6. Ketik nopol kendaraan fisik dan centang pencocokan. Pilih **Bayar manual & izinkan keluar**, lalu konfirmasi setelah uang diterima.
7. Gerbang disimulasikan terbuka. Setelah kendaraan lewat, klik **Kendaraan sudah keluar → Ya, sudah keluar**. Kapasitas baru dilepas pada tahap ini.

Jika pembayaran QR sudah berhasil, muat ulang tagihan manual: jumlah baru menjadi nol dan petugas cukup memverifikasi lalu memberi izin. Sistem menolak tagihan manual lama yang telah dilunasi melalui QR agar pembayaran tidak tercatat dua kali.

## Alur QR tetap tersedia

Pengendara menyimpan nopol → petugas mencatat masuk → tiket muncul → buka **Tiket** → centang siap keluar → buka tagihan → **Simulasi berhasil**. Pengendara memperoleh QR keluar. Petugas membuka **Keluar → QR keluar**, memindai atau memakai bantuan token manual, mencocokkan nopol, memberi izin, lalu mengonfirmasi kendaraan lewat.

Pembayaran QRIS dan gerbang masih **simulasi**, tanpa perpindahan uang nyata. Input uang manual adalah pencatatan pembayaran yang diterima petugas di luar aplikasi.

## Tarif dan kapasitas awal

- Mobil: **Rp7.000/jam**; Motor: **Rp2.000/jam**.
- Jumlah jam penuh dibulatkan ke bawah, minimum satu jam: 40 menit = 1 jam; 1 jam 40 menit = 1 jam; tepat 2 jam = 2 jam.
- Kapasitas awal **20 kendaraan gabungan**. Penuh berarti menolak kendaraan baru.
- Admin dapat mengubah tarif dan kapasitas. Tarif tersimpan ketika kendaraan masuk; perubahan tarif tidak mengubah sesi aktif secara retroaktif.
- Snapshot tagihan dasar berlaku 5 menit.
- Pembayaran berhasil memberi 15 menit; lewat batas dikenakan tambahan satu jam sesuai tarif sesi. Pelunasan tambahan memberi 15 menit baru; tagihan tambahan yang belum lunas tidak menumpuk.
- Izin petugas berlaku 120 detik. Pembayaran manual langsung memberikan izin setelah verifikasi. Kapasitas tetap terpakai sampai kendaraan lewat; batal/kedaluwarsa izin tidak menghapus sesi atau pembayaran.

## Memakai data versi sebelumnya

Database pusat tetap `data/qpark_server_v3.db` agar data v3 dapat dilanjutkan. Untuk pindah ke folder ZIP baru: hentikan server, buat backup, lalu salin **folder `data`** dari proyek v3 ke folder proyek baru sebelum dijalankan.

Migrasi v4 menambahkan peran, jenis kendaraan, tarif sesi, dan rincian metode pembayaran. Sesi lama tetap Mobil dengan tarif Rp7.000. Transaksi tidak dihapus. Pada migrasi v4 pertama, akun bernama `admin` dan `petugas` disetel sesuai password awal di tabel di atas; sesi login lama kedua akun dicabut. Setelah itu, restart tidak mereset password yang sudah diubah admin.

Backup: `py -3 scripts/backup_database.py data/qpark_server_v3.db backup/qpark.db`. Database v2 berbasis transaksi tunai tidak otomatis diubah menjadi sesi v3/v4. Utilitas `scripts/import_legacy.py` tetap tersedia untuk arsip transaksi lama.

## Akses dari HP atau perangkat lain

Semua klien harus menuju server yang sama. Untuk demo Wi-Fi/LAN: `py -3 -m server.app --host 0.0.0.0`, lalu buka `http://IP_KOMPUTER:7357` dari HP. Browser kamera memerlukan localhost atau HTTPS; pada HTTP LAN gunakan input manual/foto uji/token bantuan. Akses dari rumah melalui jaringan berbeda memerlukan server HTTPS yang dapat dijangkau; paket tidak membuat tunnel publik otomatis.

## Development dan pengujian

```sh
flutter pub get
flutter analyze
flutter test
python -m unittest discover -s server/tests -v
python scripts/build_release.py
```

Pada Windows, `jalankan_web.bat`, `jalankan_android.bat`, dan `buka_web.bat` otomatis mencari Flutter di PATH, `FLUTTER_ROOT`, lalu `%USERPROFILE%\development\flutter`. Jadi instalasi standar pada `C:\Users\NAMA\development\flutter` tidak perlu ditambahkan ke PATH terlebih dahulu.

Untuk mengaktifkan Supabase, salin `dart_defines.example.json` menjadi `dart_defines.json`, isi URL dan publishable key, lalu tambahkan `--dart-define-from-file=dart_defines.json` pada perintah run/build. Konfigurasi Google Cloud, redirect URL, skema database, dan checklist produksi dijelaskan di [docs/SUPABASE_MIGRASI.md](docs/SUPABASE_MIGRASI.md).

Prediksi jumlah kendaraan dan peluang keterisian ≥80% pada 30 menit mendatang tersedia di Analisis Parkir. Tidak membutuhkan API AI. Terapkan migrasi backend baru sebelum deploy; lihat [panduan prediksi, model, dan aktivasi](docs/PREDIKSI_PARKIR.md).

Backend menggunakan pustaka standar Python dan SQLite. Build web menyalin renderer, font lokal, dan pustaka pemindai QR. File tema `lib/ui/common.dart` tidak berubah.

Android: jalankan server kemudian `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:7357` untuk emulator. APK release memakai alamat server HTTPS: `flutter build apk --release --dart-define=API_BASE_URL=https://ALAMAT_SERVER`. SDK Android diperlukan; APK tidak disertakan. iOS memerlukan macOS/Xcode/signing.

Untuk APK dengan backend Supabase, gunakan `flutter build apk --debug --dart-define-from-file=dart_defines.json`. Hasilnya berada di `build/app/outputs/flutter-apk/app-debug.apk`; konfigurasi lokal tidak perlu dimasukkan ke Git. Ini APK pengujian, bukan paket bertanda tangan untuk distribusi Play Store.

Jika build Android berhenti pada `compileDebugJavaWithJavac` dengan pesan `Cannot query the value of this provider because it has no value available`, jalankan `flutter doctor -v` terlebih dahulu. Pada komputer pengembangan QPark, SDK Platform 36 tercatat terpasang tetapi `platforms/android-36/android.jar` dan `core-for-system-modules.jar` hilang. Memasang ulang platform SDK memulihkan berkas tersebut. Periksa kelengkapan SDK sebelum mengganti versi Gradle atau Kotlin. Gunakan Android Studio SDK Manager untuk memasang ulang **Android SDK Platform 36**, atau pindahkan instalasi platform yang tidak lengkap ke cadangan di luar direktori SDK lalu jalankan `sdkmanager "platforms;android-36"` dari Android SDK Command-line Tools. Jangan menghapus seluruh SDK atau data aplikasi untuk memperbaiki paket platform ini.

`docs/PERUBAHAN_V4.md` menjelaskan perubahan kebutuhan terhadap SRS sebelumnya. `docs/HASIL_PENGUJIAN.md` mencatat hasil nyata dan batas pengujian. Dokumentasi lama berada di `docs/legacy_v2` dan `docs/legacy_v3`.

Smoke test browser opsional untuk developer: pasang Node.js dan Playwright (`npm install --no-save playwright` serta `npx playwright install chromium`), lalu `node scripts/browser_smoke.cjs`. Tes memakai database sementara dan port 7367; `PYTHON`, `QPARK_TEST_PORT`, dan `PLAYWRIGHT_CHROMIUM_EXECUTABLE` dapat dikonfigurasi. Node/Playwright tidak diperlukan untuk menjalankan aplikasi biasa.
