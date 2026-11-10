# Polesan tampilan QPark — 10 November 2026

Urutan implementasi: tema dan komponen, transisi, respons interaksi, lalu verifikasi.

## Tampilan dan gerakan

Identitas hijau `#166534` dipertahankan dengan latar netral `#F7F8FA`, kartu putih, teks `#182230`, teks sekunder `#667085`, serta garis pemisah `#E4E7EC`. Status tertunda memakai amber; kegagalan memakai merah. Status tetap disertai teks dan ikon agar maknanya tidak bergantung pada warna. Ukuran judul, isi, fokus input, dialog, serta navigasi diseragamkan.

Tab utama menggunakan fade 200 ms. Halaman tetap berada dalam IndexedStack, sehingga formulir dan posisi scroll tidak dibuat ulang saat berpindah tab. Menekan tab yang sudah aktif tidak memulai transisi baru. Halaman yang dibuka lewat Navigator pada Android/desktop menggunakan fade dan pergeseran vertikal ringan; platform Apple tetap memakai transisi Cupertino. Transisi kustom melewati animasi saat pengaturan disableAnimations aktif.

Teks aturan biaya yang panjang dipindahkan ke bagian **Rincian biaya** yang dapat dibuka. Nominal, tarif sesi, durasi, penanda perkiraan, dan batas keluar tetap terlihat.

## Respons dan keandalan

- Sinkronisasi menampilkan indikator kecil sambil mempertahankan data sebelumnya. Pemberitahuan awal dijadwalkan setelah future sinkronisasi bersama tersimpan agar listener tidak memicu permintaan ganda.
- Tombol pemuatan tagihan dan pembayaran manual menampilkan progres; pembuatan tagihan menolak panggilan tambahan ketika sedang sibuk.
- Pesan baru menggantikan snackbar sebelumnya agar pesan lama tidak menumpuk.
- Kegagalan akses clipboard memberi petunjuk menyalin teks secara manual.
- Ticker animasi tab yang tersembunyi dinonaktifkan. Timer tampilan tiket dan keluar tidak melakukan rebuild ketika tab tidak aktif atau aplikasi berada di latar belakang.

## Verifikasi dan batas pengujian

Tes mencakup rasio kontras minimal 4,5:1 untuk pasangan teks/status utama, perubahan tab cepat, persistensi formulir dan scroll, pengurangan animasi, serta sinkronisasi tanpa request ganda. Suite yang sudah ada tetap memeriksa transaksi berulang, pemulihan koneksi, isolasi akun, sesi kedaluwarsa, pembayaran, dan tampilan ponsel dengan teks besar/keyboard.

Hasil lokal: `flutter analyze` tanpa masalah dan `flutter test` berhasil dengan 105 tes. Backend serta migrasi database tidak diubah pada polesan ini.

Build web release berhasil dan tersedia di `rilis/web`; manifest telah diperiksa sesuai source. Build APK release juga berhasil di `build/app/outputs/flutter-apk/app-release.apk` (sekitar 76,2 MB, universal, signing debug prototipe yang sudah ada). Build Android masih memberi peringatan kompatibilitas KGP dari `cryptography_flutter` dan metadata SDK; peringatan tersebut tidak menggagalkan build.

Screenshot widget pada ukuran ponsel dan desktop diperiksa. Tidak ada perangkat Android yang terhubung melalui ADB saat pengerjaan; frame time/FPS, kamera, dan menu berbagi pada HP fisik belum diukur. Tidak ada klaim performa perangkat fisik dari tes widget atau keberhasilan build.

Untuk uji perangkat berikutnya, gunakan build profile pada HP sasaran: berpindah tab cepat saat jaringan lambat, mengisi formulir lalu berpindah halaman, memutus jaringan saat pembayaran, membuka ulang aplikasi, menolak izin kamera, dan mengaktifkan pengaturan hapus animasi. Periksa frame time dengan Flutter DevTools serta pastikan transaksi tetap mengikuti konfirmasi server.
