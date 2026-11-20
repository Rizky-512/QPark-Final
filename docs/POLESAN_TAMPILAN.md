# Polesan tampilan QPark — 10 November 2026

## UI interaktif — 20 November 2026

Kartu kendaraan menggunakan ilustrasi vektor lokal, pilihan lewat swipe/tombol panah pada ponsel, dan susunan kartu pada desktop. Jenis kendaraan mengikuti tiket server; kendaraan tanpa tiket memakai simbol parkir agar tidak menebak jenisnya. Warna hijau QPark tetap menjadi aksen utama. Respons tekan, hover, fokus keyboard, dan pengaturan pengurangan animasi didukung.

Mengetuk kendaraan terpilih membuka detail dengan transisi identitas kendaraan: panel bawah pada ponsel dan panel kanan pada layar lebar. Desktop juga menampilkan ringkasan dan rincian berdampingan. Tombol tindakan utama tetap tersedia di bawah beranda. Panel detail memeriksa pemilik akun dan kendaraan agar tiket lama tidak ditampilkan setelah pilihan berubah.

Pembayaran yang dikonfirmasi server menampilkan animasi centang singkat, terpisah dari QR keluar yang tetap statis. Pembayaran yang belum pasti karena koneksi terputus tidak menampilkan animasi sukses. Halaman pembayaran memakai dua kolom pada layar lebar. Tarif, otorisasi keluar, API, dan logika transaksi tidak diubah.

Tes tambahan mencakup pemilihan melalui swipe/panah, detail tiket, perubahan kendaraan saat panel terbuka, perubahan ukuran desktop ke ponsel, serta pembayaran terkonfirmasi dan koneksi gagal. Screenshot pengujian tersimpan di `build/ux_checks/interactive-*.png`. Animasi dan FPS pada HP fisik tetap perlu diuji langsung; tes widget tidak mengukur kelancaran perangkat.

Verifikasi lokal: suite lengkap 109 tes lulus. Pemeriksaan screenshot kemudian menemukan posisi carousel yang keluar batas setelah resize; penyimpanan posisi halaman dinonaktifkan karena pilihan kendaraan sudah dikelola oleh service. Keempat tes interaksi dijalankan ulang dan lulus, termasuk pemeriksaan batas posisi kartu. `flutter analyze` dan pemeriksaan akhir `dart analyze lib test` tidak menemukan masalah. Build web release berhasil dan seluruh 71 entri manifest cocok dengan source.

APK release terbaru berhasil dibuat di `build/app/outputs/flutter-apk/app-release.apk` dengan konfigurasi lokal yang sudah ada. Tidak ada perangkat Android terhubung melalui ADB saat verifikasi. Vercel menggunakan hasil build `rilis/web` melalui integrasi GitHub.

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
