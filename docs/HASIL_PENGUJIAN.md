> Arsip pengujian v4. Laporan terbaru: [HASIL_PENGUJIAN_V5.md](HASIL_PENGUJIAN_V5.md).

# Hasil pengujian QPark 4

Tanggal: 13 Oktober 2026. Lingkungan Linux, Flutter 3.44.0 / Dart 3.12.0, Python 3.12. Pengujian versi sebelumnya tersimpan sebagai arsip dan tidak dihitung ulang sebagai kelulusan v4.

| Pemeriksaan | Hasil |
|---|---|
| Analisis Flutter | Tidak ada masalah. |
| Tes Flutter | **9 lulus**: 5 service/domain; 4 widget mencakup peran Petugas dan Admin pada 360×800 serta 1280×720. |
| Tes Python/server | **38 lulus**: regresi 27 tes v3 ditambah 11 tes revisi v4. |
| Build web release | Berhasil; renderer dan font lokal disertakan. |
| Browser tiga peran | Lulus: pengendara, petugas, admin dalam tiga konteks Chromium independen. |
| Launcher | Lulus pada Linux dari folder yang mengandung spasi, dipanggil dari luar direktori proyek, tanpa membutuhkan Flutter. |
| Penyajian HTTP rilis | Enam aset utama cocok byte per byte, termasuk renderer, font dan pustaka QR. |

## Cakupan tambahan v4

- Login admin/admin123 dan petugas/petugas123; peran Petugas ditolak oleh endpoint admin.
- Masuk manual tanpa kamera, jenis Motor, dan verifikasi wajib.
- Tagihan motor Rp2.000; manual dengan uang Rp10.000 dan kembalian Rp8.000; retry tidak menggandakan pelunasan.
- Pembayaran QR dan manual bersamaan menghasilkan satu pelunasan dan satu jendela.
- QR yang sudah lunas menolak tagihan manual lama; setelah muat ulang, izin keluar dapat diberikan tanpa menagih lagi.
- Uang kurang/nopol salah/tanpa verifikasi/tanpa autentikasi ditolak.
- Tarif/penalti memakai snapshot sesi, meskipun admin mengganti tarif sesudah kendaraan masuk.
- Riwayat pelanggan harus mempunyai nopol; staf mempunyai akses seluruh sesi, filter dan pagination.
- Reset password mencabut token lama dan password baru bertahan setelah restart.
- Migrasi dari skema v3 mempertahankan ID sesi aktif, jenis Mobil, dan tarif Rp7.000.
- Pembayaran manual tetap bekerja jika simulator QR dinonaktifkan.

## Batas bukti

Windows BAT diperiksa secara statis, belum dijalankan di Windows. APK/Android fisik, iOS, kamera fisik/CCTV, palang nyata, QRIS bank, dan jaringan internet berbeda belum diuji. Tidak ada uji dengan peserta komuter. Data browser merupakan data sintetis. Benchmark HTTP lokal bukan pengganti pengukuran sinkronisasi 100 perubahan UI pada jaringan lapangan.

Profil HTTP 20 sesi, 10 klien, 100 mutasi: p95 **0,1311 detik**; 100/100 pembacaan setelah commit selesai dalam tiga detik. Angka berasal dari log `hasil/server-tests-v4.txt` dan dapat berubah menurut perangkat.

## Alur browser yang selesai

Viewport pengendara 360×800 dan staf 1280×800. Login default dilakukan melalui UI. Mobil dicatat tanpa foto, ditagih manual Rp7.000 dengan uang Rp10.000 dan kembalian Rp3.000, kemudian dikonfirmasi lewat. Riwayat pelanggan dan petugas menampilkan transaksinya. Admin mengubah tarif motor melalui UI; motor baru kemudian dikenai tarif tersebut dan dibayar melalui QR simulasi. Petugas memverifikasi token keluar serta nopol, lalu mengonfirmasi lewat. Riwayat admin mencakup kedua jenis dan metode. Kapasitas kembali 20 dan tidak ada JavaScript page error.

Pemindai pada uji browser memakai bantuan token manual; kamera fisik tidak diujikan. Field browser diisi menggunakan paste input dan diverifikasi nilainya sebelum melanjutkan. Log ringkas: `hasil/browser-v4.json`. Render halaman admin dan riwayat mobile diperiksa secara visual. Tema `lib/ui/common.dart` dibandingkan dengan ZIP v3 dan identik byte per byte.
