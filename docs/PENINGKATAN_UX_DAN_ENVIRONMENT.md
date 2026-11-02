# Perbaikan alur dan lingkungan QPark

Urutan pekerjaan: pemisahan lingkungan dan pemeriksaan otomatis (6), kemudian QR penghubung (1), beranda pelanggan (2), rincian biaya (3), monitor petugas (4), dan bukti transaksi (5).

## Demo dan pengujian

Build lama tetap memakai lingkungan `demo`. Identitas pelanggan, sesi, dan antrean transaksi demo tetap menggunakan kunci penyimpanan sebelumnya. Lingkungan `test` memakai namespace penyimpanan tersendiri, termasuk sesi Supabase, dan menampilkan pita **PENGUJIAN**.

Untuk pengujian lokal:

```powershell
python scripts/build_environment.py --environment test --config config/test.example.json
python -m server.app --environment test --open
```

Server pengujian menggunakan port 7367, database `data/test/qpark.db`, backup `data/test/backups`, dan build `build/environments/test/web`. Demo tetap memakai port 7357 dan database sebelumnya. Database memiliki penanda lingkungan; membuka database demo sebagai test atau sebaliknya ditolak. Header lingkungan dari aplikasi juga diperiksa oleh server lokal. Klien lama tanpa header tetap kompatibel.

`scripts/build_release.py` hanya menulis build demo ke `rilis/web`; konfigurasi test ditolak. `build_environment.py` menyimpan build web/APK di `build/environments/<lingkungan>/`. Contoh APK:

```powershell
python scripts/build_environment.py --environment test --config config/test.local.json --target apk
```

Untuk emulator Android, atur `API_BASE_URL` menjadi `http://10.0.2.2:7367`. Untuk HP fisik gunakan alamat server yang dapat dijangkau HP. `localhost` pada HP mengarah ke HP itu sendiri. APK demo dan test masih menggunakan application ID yang sama, sehingga instalasi saling menggantikan; penyimpanan aplikasi tetap dibedakan berdasarkan lingkungan.

Untuk Supabase, sediakan **proyek pengujian yang berbeda** dan salin konfigurasi ke `config/test.local.json`. Isi `QPARK_ENV=test`, `SUPABASE_URL`, dan `SUPABASE_PUBLISHABLE_KEY`. Build melalui:

```powershell
python scripts/build_environment.py --environment test --config config/test.local.json --demo-config config/demo.local.json
```

Berkas pembanding harus memiliki `QPARK_ENV=demo` dan endpoint proyek demo. Script menolak endpoint yang sama. Migrasi dan pengaturan OAuth perlu dipasang pada proyek pengujian secara terpisah. Perubahan ini tidak membuat proyek cloud atau memindahkan data. Gunakan script build di atas agar pemeriksaan profil berjalan; pemanggilan Flutter langsung tidak menjalankan pemeriksaan pembanding tersebut. Jangan menaruh service-role key di aplikasi. Berkas `config/*.local.json` diabaikan Git.

Workflow `.github/workflows/quality.yml` menjalankan analisis Flutter, tes Flutter, build web, tes Python, serta migrasi dan tes SQL pada database PostgreSQL sementara. Workflow berjalan setelah perubahan di-push ke GitHub; tidak melakukan deploy otomatis.

## Alur pengguna

1. Pelanggan memilih **Hubungkan tiket** dan menunjukkan QR kepada petugas. Petugas memilih **Pindai QR pelanggan**, mencocokkan kendaraan, lalu menghubungkan tiket. Kode manual tetap tersedia. QR penghubung dan QR keluar memakai format berbeda; kode kedaluwarsa ditolak dan server tetap menentukan kepemilikan tiket.
2. Beranda menampilkan tindakan utama sesuai kondisi: tambah kendaraan, hubungkan tiket, bayar, tampilkan QR keluar, periksa transaksi, atau buka riwayat. Saat offline, data lama ditandai dan pengguna diarahkan memperbarui status.
3. Rincian biaya menampilkan tarif sesi, durasi, perkiraan/tagihan server, pembayaran tercatat, serta batas keluar. Perhitungan mengikuti server yang sudah ada: minimum satu jam dan pembulatan ke bawah ke jam penuh. Contoh 1 jam 40 menit dihitung satu jam; tepat dua jam dihitung dua jam. Tagihan server yang masih berlaku mengalahkan perkiraan. Keterlambatan keluar mengikuti tagihan tambahan server.
4. Monitor petugas menyediakan pencarian nopol dan filter belum bayar, sudah bayar, atau diizinkan keluar. Tombol pada kendaraan membuka transaksi kendaraan tersebut. Verifikasi kendaraan fisik, konfirmasi pembayaran, dan konfirmasi kendaraan benar-benar lewat tetap diperlukan.
5. **Lihat bukti transaksi** tersedia setelah pembayaran terkonfirmasi, pada pembayaran, layanan manual, dan riwayat. Pengguna dapat menyalin teks atau membuka menu berbagi perangkat. Bukti hanya memuat tagihan berstatus PAID; QR akses dan rahasia pelanggan tidak disertakan. Pembayaran QR simulasi ditandai jelas sebagai tidak memindahkan uang nyata.

Kamera memerlukan izin perangkat dan dukungan platform; pada web gunakan localhost atau HTTPS. Jika kamera atau menu berbagi tidak tersedia, gunakan kode manual dan salin teks. Pengujian otomatis tidak menggantikan uji kamera serta menu berbagi pada HP fisik.

## Verifikasi lokal 2 November 2026

- `flutter analyze`: bersih.
- Suite Flutter: 99 tes lulus, ditambah 2 tes widget baru untuk pemilihan tiket dan salin bukti. Setelah penyempurnaan fixture, 10 tes alur/widget terkait dijalankan ulang dan lulus.
- Suite Python: 74 tes dijalankan, 73 lulus dan 1 tes model opsional dilewati. Tes penolakan lingkungan HTTP kemudian ditambahkan; ketiga tes lingkungan lulus.
- Build web release demo dan pengujian berhasil. Manifest `rilis/source_manifest.json` cocok dengan source.
- Build Android release berhasil: `build/app/outputs/flutter-apk/app-release.apk`, sekitar 76,2 MB (APK universal). APK memakai konfigurasi demo lokal dan signing debug yang sudah ada, untuk pengujian prototipe. Ini bukan ukuran unduhan Play Store.
- Build Android memberi peringatan kompatibilitas mendatang pada plugin `cryptography_flutter` (Kotlin Gradle Plugin) dan versi metadata Android SDK. Keduanya tidak menggagalkan build saat ini.
- Screenshot tes ukuran ponsel diperiksa. Uji kamera dan menu berbagi pada HP fisik belum dilakukan.
- Workflow GitHub belum dijalankan di GitHub. Regresi SQL tidak dijalankan ulang pada sesi ini karena Docker daemon tidak aktif; file migrasi tidak berubah.
