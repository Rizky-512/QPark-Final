# Hasil pengujian QPark 3 — revisi SRS

Tanggal: 13 Oktober 2026. Pemeriksaan dilakukan di Linux, Flutter 3.44.0, Dart 3.12.0, Python 3.12, serta Chromium headless. Dokumen ini menggantikan hasil v2; tes tunai/admin v2 tidak dihitung sebagai bukti SRS baru.

| Pemeriksaan | Hasil aktual |
|---|---|
| `flutter analyze` | Lulus; tidak ada masalah. |
| `flutter test --reporter expanded` | **7 tes lulus**: 5 tes service/domain dan 2 tes widget responsif. |
| `python -m unittest discover -s server/tests -v` | **27 tes lulus**. |
| `flutter build web --release --no-web-resources-cdn` | Berhasil; hasil build disertakan di `rilis/web`. |
| Tampilan/widget | Mode pengendara, login, halaman petugas, dan logout diperiksa pada 360×800 dan 1280×720; tidak ada overflow pada tes tersebut. |
| Launcher Python | Lulus dari folder dengan spasi, dipanggil dari luar folder proyek; tidak memerlukan Flutter untuk rilis yang belum diubah. |
| Penyajian aset rilis | 6 aset utama status 200 dan byte sama dengan berkas rilis, termasuk font lokal dan pustaka QR web. |
| Browser end-to-end | **Lulus**, tiga konteks browser independen; rincian di bawah. |
| Skrip BAT Windows | Ditinjau secara statis; belum dieksekusi pada Windows. |
| APK Android / perangkat fisik | Belum dibangun atau diuji; Android SDK/perangkat tidak tersedia. |
| iOS | Belum dibangun atau diuji; lingkungan bukan macOS/Xcode. |

## Cakupan aturan server

Tes memeriksa tarif minimum satu jam dan pembulatan ke bawah; kapasitas 20; verifikasi masuk wajib; penolakan penuh dan sesi aktif ganda; snapshot tagihan lima menit; hasil pembayaran menunggu/gagal/berhasil; idempotensi; jendela 15 menit; penalti satu jam tanpa penumpukan selama belum dilunasi; rotasi QR; izin 120 detik; konfirmasi keluar; pembatalan; serta batas waktu yang tepat.

Uji konkurensi mencakup 100 pasangan perebutan satu tempat terakhir, 100 permintaan pembayaran serentak, 10 permintaan tagihan, dan 10 permintaan izin keluar. Pemeriksaan autentikasi mencakup endpoint tanpa login, password bersalt, logout/revokasi, dan kedaluwarsa sesi petugas delapan jam. Restart dan backup/restore SQLite ikut diperiksa.

Tes Flutter memeriksa nopol lokal tetap tersimpan tanpa mengubah sesi server, normalisasi, retry dengan kunci operasi yang sama ketika respons hilang, logout offline lalu revokasi setelah tersambung, serta waktu tampilan yang mengacu jam server.

## Alur browser aktual

Tiga konteks Chromium independen mewakili pengendara desktop, keluarga pada viewport 360×800, dan petugas desktop 1280×720. Urutan berikut selesai tanpa JavaScript page error:

1. Pengendara dan keluarga menyimpan nopol yang sama.
2. Petugas memilih gambar uji, mengetik nopol, memverifikasi, dan menerima kendaraan.
3. Keluarga membayar simulasi Rp7.000; status lunas dan QR keluar muncul pada pengendara.
4. Petugas memeriksa token melalui bantuan input manual dan mencocokkan nopol. Izin gerbang belum melepas kapasitas.
5. Konfirmasi kendaraan lewat menutup sesi; kapasitas kembali 20 dan status selesai muncul pada klien pengendara.
6. Koneksi salah satu browser diputus untuk memeriksa indikator offline. Jaringan dipulihkan sesudahnya; status UI setelah tersambung kembali tidak dinilai terpisah dalam tes ini.

Font, tata letak halaman masuk, serta QR keluar diperiksa secara visual dari render browser. Berkas tema `lib/ui/common.dart` dibandingkan byte per byte dengan ZIP sumber dan tidak berubah. Bukti teks: `hasil/browser-flow-v3.json`. Tes memakai token manual, bukan kamera fisik, dan tidak membuktikan pembayaran dari rumah melalui internet.

## Profil HTTP

20 sesi aktif, 10 klien, 100 mutasi pada server lokal:

- p95 respons mutasi: **0,3429 detik**.
- 100/100 pembacaan sesudah commit selesai dalam tiga detik.
- Profil ini menggunakan percobaan pembayaran gagal dan pembacaan ulang. Angka tersebut **belum membuktikan 100 perubahan status terlihat pada UI** atau kinerja jaringan lapangan.

Log mentah: `hasil/server-tests.txt`.

## Batas validasi

- Belum ada uji kegunaan dengan peserta komuter/petugas; AT-35 dan NFR-06 belum dinyatakan lulus.
- Kamera CCTV nyata, pemindaian menggunakan kamera HP fisik, serta gerbang perangkat keras belum diuji. Foto uji dan token manual merupakan bantuan demonstrasi.
- Belum dilakukan pengujian pengendara/keluarga melalui dua jaringan internet berbeda dengan HTTPS; AT-38 belum dinyatakan lulus.
- Target sinkronisasi NFR-01/AT-33 untuk 100 perubahan UI dan 10 klien belum diukur sepenuhnya.
- QRIS dan gerbang adalah simulasi; tidak ada transaksi uang atau pembukaan gerbang nyata.
- Penambahan font lokal dilakukan agar teks tidak memerlukan unduhan font eksternal. Renderer dan pustaka QR web disertakan dalam rilis.

Hasil ini membuktikan pengujian yang disebutkan, bukan pernyataan bahwa seluruh acceptance test SRS telah lulus di lapangan. Checklist lanjutan terdapat di `UJI_MANUAL.md` dan keterlacakan di `TRACEABILITY_SRS.md`.
