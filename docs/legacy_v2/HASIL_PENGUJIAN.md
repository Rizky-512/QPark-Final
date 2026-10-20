# Hasil pengujian Flutter

Tanggal pemeriksaan: 4 Oktober 2026. Lingkungan Linux, Flutter stable 3.47.6, Dart 3.13.5. Hasil berikut berasal dari kode Flutter dalam paket ini, bukan dari tes Python sebelumnya.

| Pemeriksaan | Hasil |
|---|---|
| flutter analyze --no-pub | Lulus, tidak ada masalah |
| flutter test --no-pub --reporter expanded | **51 lulus, 0 gagal** |
| flutter build web --release --no-pub --no-web-resources-cdn | Berhasil, rilis/web berisi salinan hasil build |
| Widget semua halaman utama | Lulus pada 1366×768, 390×844, dan 320×640; tidak ada overflow |
| UI login/logout form kotor | Lulus; batal mempertahankan isian |
| UI biaya berubah | Lulus; total diperbarui dan perlu konfirmasi kedua sebelum lunas |
| UI database gagal | Lulus; menampilkan error, tanpa slot kosong palsu |
| Penyajian HTTP aset web | 6/6 aset utama status 200, isi utuh, MIME WASM dan COOP/COEP benar |
| Browser nyata end-to-end | Belum terverifikasi; pembatasan socket Chromium dan localhost browser terkelola |
| Build APK / pengujian Android fisik | Belum; Android SDK/perangkat tidak tersedia |
| Build iOS / perangkat iPhone | Belum; lingkungan bukan macOS/Xcode |
| .bat langsung di Windows | Belum; ditelusuri secara statis, host pengujian Linux |

Tes mencakup AT-01–AT-11 serta aspek AT-12: password bersalt, sesi, peran, akun nonaktif, persistensi, aturan uang/waktu, rollback, kapasitas, dan immutability. Test widget memeriksa render dan interaksi Flutter headless, bukan pengganti uji browser/perangkat nyata. Checklist penerimaan lengkap tetap ada pada UJI_MANUAL.md.

## Benchmark NFR-02

1.000 transaksi awal, 20 iterasi per operasi, database SQLite sementara native. Angka ini tidak membuktikan kinerja jaringan/browser/HP pengguna.

```text
NFR-02 dashboard: 20/20 <=3s; p95=1ms; max=4ms
NFR-02 riwayat: 20/20 <=3s; p95=15ms; max=33ms
NFR-02 pendapatan: 20/20 <=3s; p95=0ms; max=1ms
NFR-02 masuk_bayar: 20/20 <=3s; p95=2ms; max=7ms
```

## Catatan lingkungan

Pemeriksaan awal SDK sempat ditolak otomatis karena Flutter mencoba deteksi Azure melalui metadata lingkungan. Pemeriksaan kode SDK menunjukkan mode CI melewati deteksi tersebut; semua validasi berikutnya dijalankan dengan CI=true dan FLUTTER_SUPPRESS_ANALYTICS=true. Tidak ada metadata/credential cloud yang digunakan oleh aplikasi.

SDK sempat memiliki berkas ekstraksi tidak utuh dan permission executable yang hilang; diperbaiki dari arsip resmi dengan checksum SHA-256 sebelum tes. Lingkungan sementara juga pernah direset; kode dipulihkan dan 51 tes dijalankan ulang sebelum hasil akhir.

Peringatan debug Drift pada tes persistensi berasal dari dua instance database dengan executor dan file berbeda (fixture in-memory serta file sementara). Tes menggunakan file terpisah dan menutup koneksi; aplikasi normal memakai satu repository dari bootstrap.

Log aktual tersedia pada direktori hasil/.
