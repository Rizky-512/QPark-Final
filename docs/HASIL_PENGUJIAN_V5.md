# Hasil pengujian QPark v5

16 Oktober 2026. Revisi dari ZIP v4, menggunakan Flutter 3.44.0 / Dart 3.12.0 dan Python pada Linux. Hasil v4 tetap disimpan sebagai arsip terpisah.

| Pemeriksaan | Hasil |
|---|---|
| Analisis statis Dart/Flutter | Tidak ditemukan masalah. |
| Tes server | 47 lulus: 38 regresi sebelumnya dan 9 tes analisis baru. |
| Tes Flutter | 12 lulus: 6 service/domain dan 6 widget. |
| Build web release JavaScript | Berhasil; renderer dan font lokal disertakan. |
| Launcher | Berhasil dijalankan dari luar direktori proyek, dengan database uji terpisah. |
| Konsistensi rilis | Manifest cocok dengan source final. Lima aset utama yang disajikan lewat HTTP cocok byte per byte dengan berkas rilis. |
| Tema dan dependensi | `lib/ui/common.dart` dan `pubspec.lock` identik dengan ZIP v4. |

## Cakupan

- Halaman pertama Login customer; tombol Google nonaktif; akses demo tidak membuat akun Google palsu atau memanggil cloud.
- Login langsung admin/petugas dari halaman customer, logout kembali ke halaman login, nopol tetap tersimpan, sesi demo tidak dipulihkan otomatis setelah restart.
- Layout dan navigasi pada 360×800 dan 1280×720; admin dapat membuka Analisis, petugas tidak mempunyai menu tersebut.
- API analisis menolak tanpa autentikasi (401) dan petugas (403).
- Agregasi masuk menurut jam/hari, mobil/motor, rata-rata dan median yang berbeda, durasi nol, sesi aktif dikecualikan.
- Pembayaran dihitung berdasarkan waktu pelunasan; hanya tagihan PAID, dengan QR/manual dipisah.
- Keterisian berbobot waktu, kendaraan menginap, hari parsial, perubahan kapasitas, periode tanpa pengamatan, dan kendaraan diizinkan keluar yang masih memakai slot.
- Regresi server mencakup QR, pembayaran manual, kembalian, verifikasi petugas, konfirmasi keluar, penalti, riwayat, akun, migrasi dan konkurensi.

Log tersedia pada `docs/hasil/*v5*`.

## Batas pengujian

Uji browser end-to-end v5 belum dinyatakan lulus: percobaan Chromium pada lingkungan pengerjaan diblokir oleh izin Unix socket. Skrip `scripts/browser_smoke.cjs` sudah disesuaikan untuk v5 dan dapat dijalankan pada komputer dengan Playwright/Chromium. Tes widget, server dan penyajian HTTP di atas tidak menggantikan pengujian browser nyata.

Build Android/APK, emulator Android, kamera fisik, gerbang fisik, pembayaran QRIS nyata, serta Google/Supabase belum diuji atau diintegrasikan pada revisi ini. Android scaffold tetap disertakan. Build yang disertakan adalah web JavaScript; pemeriksaan tambahan Wasm tidak berhasil pada lingkungan ini dan kompatibilitas Wasm tidak diklaim.

Data pengujian memakai database sementara dan tidak disertakan sebagai data operasional. Laporan ini merupakan validasi teknis prototipe, bukan penelitian pengguna atau bukti kinerja produksi.
