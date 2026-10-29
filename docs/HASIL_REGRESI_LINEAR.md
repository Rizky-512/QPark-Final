# Verifikasi penambahan regresi linear QPark

Tanggal pengerjaan: 29 Oktober 2026, WIB. Perubahan berupa modul riset opsional
di `qpark_ml/`, tes tambahan, dokumentasi dan SQL schema simulasi terpisah.
Tidak ada berkas implementasi aplikasi lama yang diubah oleh pekerjaan ini.

## Hasil eksperimen yang dijalankan

Data **SIMULASI**, generator versi 1, seed 512: 8.155 kunjungan selama 56 hari,
24 Agustus 2026 00.00 sampai 19 Oktober 2026 00.00 WIB. Asumsi pola generator bukan
hasil observasi QPark. Tanggal 18 Oktober 00.00 menjadi cutoff target untuk
pelatihan/evaluasi; satu hari berikutnya dicadangkan untuk demo prediksi.

Dataset: 5.277 sampel pada 24 Agustus 00.30 sampai target 18 Oktober 00.00 WIB.
Split: 3.164 latih, 1.053 validasi, 1.056 uji; empat sampel dipurge untuk mencegah
label melintasi batas split. Tidak ada jendela ditolak karena perubahan kapasitas
pada simulasi berkapasitas tetap 20 ini.

Validasi: MAE model 1,536059; RMSE 2,003993; R² 0,919131.
Baseline persistence: MAE 1,636277; RMSE 2,376483; R² 0,886275.

Uji: 6 Oktober 2026 23.45 sampai target 18 Oktober 2026 00.00 WIB.
MAE model **1,532155 kendaraan**, RMSE **2,002128**, R² **0,920786**.
Baseline persistence: MAE **1,707386**, RMSE **2,448910**, R² **0,881488**.
R² bukan persentase akurasi. Semua metrik dihitung pada prediksi mentah.
Laporan lengkap, termasuk kelompok hari kerja/akhir pekan dan versi dependensi,
tersimpan di `docs/hasil/regresi_linear_simulation.json`.

Inferensi terpisah pada 19 Oktober 00.00 untuk target 00.30 menghasilkan
0,594549 kendaraan, dari keterisian saat itu 1. Ini hanya keluaran estimasi model
simulasi; label masa depan tidak dipakai atau diklaim tersedia.

Database operasional lokal diperiksa read-only: **0 sesi**, 0 audit perubahan
kapasitas, konfigurasi kapasitas 20. Tidak ada coverage lengkap yang diklaim.
Pipeline mengembalikan `insufficient_data`, 0 sampel, periode null, metrik null,
dan tidak membuat model operasional.

## Pemeriksaan aplikasi dan data

- `flutter test --no-pub`: **66 tes lulus**. Tes meliputi domain, layanan, HTTP
  repository, sinkronisasi customer, UI/UX, verifikasi keluar dan pembayaran.
  Terdapat warning Drift dari tes lama yang membuat beberapa instance database;
  warning tersebut tidak dihilangkan atau disembunyikan.
- `flutter analyze --no-pub`: **No issues found**, 34,9 detik.
- Tes baru `python -m unittest server.tests.test_linear_regression -q` memakai
  environment ML: **16 tes lulus**, tanpa skip. Mencakup batas interval, sesi
  menginap, WIB, coverage/jeda, kapasitas, data invalid, read-only, split/purge,
  ketahanan terhadap perubahan label uji, kesetaraan inferensi dengan sklearn,
  baseline gate, model simulasi/operasional dan larangan menimpa output.
- Dengan Python standar tanpa sklearn: 15 tes baru lulus, satu tes pelatihan
  **skip** sesuai desain dependensi opsional; ini bukan bukti pelatihan lulus.

Percobaan awal rangkaian server menjalankan 63 tes: 47 tes lama lulus, tetapi satu
tes baru gagal saat cleanup Windows karena koneksi SQLite belum ditutup eksplisit.
Modul dan fixture baru diperbaiki menggunakan `contextlib.closing`; pengujian ulang
16 tes baru lulus. Hasil rangkaian server setelah koreksi dicatat di bawah.

Pengujian ulang penuh `python -m unittest discover -s server/tests -v` dalam
environment ML: **63 tes lulus**, tanpa skip, 163,790 detik. Profil HTTP:
10 klien, 20 sesi, 100 mutasi; p95 0,5721 detik, seluruh 100 pembacaan setelah
commit terlihat dalam 3 detik. Tes model juga dijalankan ulang setelah penguatan
validasi bentuk JSON/model. `git diff --cached --check` tidak menemukan kesalahan
whitespace. Diff staged hanya penambahan berkas pekerjaan ini.

Hash SHA256 `data/qpark_server_v3.db` sebelum/sesudah pemeriksaan sama:
`FC1ECF7C1F6FF0EDF0A2DF5EAEFE28C4504D7E359A03C9F2CA1FD2071EFCD361`.
Tidak ada perubahan schema, transaksi, akun atau data dummy pada database tersebut.

## Supabase dan batas verifikasi

Proyek tujuan teridentifikasi dari konfigurasi lokal dan linked project reference:
`ekuwuqqskdyxzoflzlgz`. SQL schema `supabase/ml/001_simulation.sql` dan SQL unggah
untuk run `qpark-linear-sim-v1-seed512` telah disiapkan. Snapshot dan SQL hasil
generator disimpan di folder sementara di luar Git; dapat dibuat ulang dari CLI.

**Belum diunggah:** belum tersedia koneksi plugin Supabase berhak membuat schema,
dan browser automation tidak menyediakan browser/dashboard yang dapat diakses.
Publishable key yang tersedia tidak dipakai untuk mencoba melewati hak akses.
Eksekusi SQL, constraint/idempotensi PostgreSQL, RLS dan pembacaan balik di Supabase
belum diuji. Status `prepared` dari generator SQL bukan bukti unggahan.

Tidak menjalankan build, instalasi, unduhan, emulator atau aplikasi Android.
Tidak menjalankan uji browser E2E, OAuth nyata, kamera/gerbang, atau pembayaran nyata.
Tidak ada klaim bahwa simulasi membuktikan kualitas prediksi operasional.

## Git

Remote diverifikasi: `https://github.com/Rizky-512/QPark-Final.git`; branch saat
pengerjaan `main`. Author terkonfigurasi `Rizky-512` dengan email noreply GitHub
yang sudah ada; identitas tidak diganti. Perubahan lokal awal
`android/gradle.properties` dan `.vscode/settings.json` tidak disertakan.
Commit hanya mencakup penambahan pekerjaan regresi ini; tidak melakukan push.
