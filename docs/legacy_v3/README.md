# QPark 3 — revisi PRD/SRS

Revisi proyek Flutter QPark yang sudah ada. Tema hijau, warna, tipografi, kartu, tombol, layout responsif, sidebar desktop, dan navigasi bawah HP tetap dipakai. Sumber kebutuhan: `docs/PRD_SRS_Prototipe_Aplikasi_Parkir.docx`.

## Mulai paling mudah di Windows

1. Ekstrak **seluruh ZIP** ke folder biasa, misalnya `D:\QPark`. Jangan menjalankan BAT dari dalam ZIP.
2. Pastikan Python **3.10 atau lebih baru** terpasang dan dikenali perintah `py` atau `python`.
3. Klik dua kali **`buka_web.bat`**.
4. Pada pemakaian pertama, terminal menampilkan username **petugas** beserta password acak. **Catat password tersebut**, karena hanya ditampilkan sekali. Password disimpan sebagai hash bersalt pada server.
5. Browser membuka `http://localhost:7357`. Halaman pertama adalah mode pengendara, tanpa akun.
6. Biarkan terminal tetap terbuka selama demo. Tekan Ctrl+C untuk menghentikan server.

Paket menyertakan hasil build web terbaru, sehingga menjalankan rilis ini tidak memerlukan IDE atau Flutter SDK. Jika source diedit setelah build, launcher mendeteksi perbedaan dan memerlukan Flutter SDK untuk membangun ulang. Server hanya memakai pustaka standar Python, tanpa `pip install`.

Jika port 7357 dipakai aplikasi lain:

```sh
python scripts/launch.py --port 7360 --open
```

Untuk Linux/macOS: `python3 scripts/launch.py --open` atau `./mulai.sh`.

## Coba alur lengkap

1. Buka satu jendela browser sebagai pengendara. Tambahkan **B 123 AB**.
2. Buka browser/profil lain sebagai petugas, pilih **Login petugas**, dan gunakan akun dari terminal.
3. Menu **Masuk** → pilih `samples/kendaraan_uji.png`. Ini gambar ilustrasi uji, bukan foto kamera lapangan.
4. Baca nopol pada gambar, isi **B 123 AB**, centang gambar terbaca serta verifikasi kendaraan, lalu terima kendaraan.
5. Beranda pengendara menampilkan tiket otomatis. Kapasitas menjadi 19 kosong.
6. Menu **Tiket** → centang siap keluar → buka tagihan → pilih **Simulasi berhasil**. Tersedia waktu keluar 15 menit.
7. Petugas membuka **Keluar** lalu memindai QR keluar pengendara. Untuk bantuan demo, salin token dari halaman QR dan tempel ke input token petugas.
8. Petugas mengetik nopol kendaraan fisik, mencentang cocok, lalu **Izinkan keluar**. Indikator gerbang terbuka, tetapi kapasitas tetap 19.
9. Pilih **Kendaraan sudah keluar** setelah mobil disimulasikan lewat, lalu konfirmasi. Kapasitas kembali 20, tiket selesai, QR tidak berlaku.

Perangkat keluarga dapat menyimpan nopol yang sama dan membayar tiket yang sama. Daftar nopol bukan bukti kepemilikan. Dalam prototipe, akses tiket berdasarkan nopol mengikuti keputusan SRS; gunakan data uji terkendali.

## Aturan revisi

- Satu area, hanya mobil, kapasitas 20.
- Tarif Rp7.000 × maksimum(1, jumlah jam penuh). 1 jam 40 menit = Rp7.000; tepat 2 jam = Rp14.000.
- Tagihan dasar dikunci 5 menit. Tepat batas 5 menit sudah kedaluwarsa.
- Hanya pembayaran berhasil yang memberikan 15 menit. Tepat batas 15 menit masih diterima saat petugas mengizinkan keluar.
- Lewat 15 menit: satu tambahan Rp7.000. Pelunasan tambahan memberi 15 menit baru. Tidak menumpuk selama tambahan belum dibayar.
- Izin gerbang berlaku sebelum 120 detik; tepat 120 detik sudah habis. Tidak timbul penalti selama izin masih aktif.
- Kapasitas baru dilepas setelah konfirmasi mobil lewat.
- QR pembayaran `QPP.SIMULASI...` berbeda dari QR keluar `QPX...`. Keduanya bukan QR merchant sungguhan.
- Pembayaran serta gerbang hanya simulasi. Source mendukung `QPARK_SIMULATION=false` untuk menyembunyikan kontrol pembayaran dan `--disable-simulator` untuk menolak endpoint simulator; tidak ada pengganti gateway nyata.

## Dua perangkat / HP

Semua perangkat harus mengakses server yang sama. Data transaksi bukan lagi SQLite terpisah di masing-masing browser.

Untuk demo **LAN tepercaya**, jalankan:

```sh
python -m server.app --host 0.0.0.0 --port 7357
```

Cari alamat IPv4 komputer server melalui `ipconfig`, misalnya `192.168.1.10`, lalu buka `http://192.168.1.10:7357` pada HP yang tersambung Wi-Fi sama. `localhost` pada HP berarti HP itu sendiri, bukan komputer server. Firewall mungkin meminta izin jaringan privat.

Browser biasanya memerlukan HTTPS atau localhost untuk kamera. Pada LAN HTTP, gunakan pemilihan foto dan token manual sebagai bantuan demonstrasi. Untuk kamera browser HP serta akses lintas jaringan, gunakan HTTPS dengan sertifikat tepercaya. Server menerima `--cert path/cert.pem --key path/key.pem`, atau dapat ditempatkan di belakang reverse proxy HTTPS. Tidak ada tunnel atau deployment publik yang dibuat otomatis.

Pembayaran dari rumah membutuhkan alamat server HTTPS yang dapat dijangkau dari kedua jaringan. Pengujian klien lokal tidak membuktikan akses internet dari rumah. Lihat batas pengujian aktual di `docs/HASIL_PENGUJIAN.md`.

## Mengembangkan / membangun ulang

Flutter SDK, Git, dan internet untuk mengambil dependensi diperlukan hanya untuk development/build.

```sh
flutter pub get
flutter analyze
flutter test
python -m unittest discover -s server/tests -v
python scripts/build_release.py
```

`build_release.py` memperbarui `rilis/web` dan manifest sumber hanya setelah build sukses. Untuk development browser Chrome:

```sh
python -m server.app --allow-origin http://localhost:7359
flutter run -d chrome --web-port 7359 --dart-define=API_BASE_URL=http://localhost:7357
```

Jalankan kedua perintah pada terminal terpisah. Origin harus sama persis dengan alamat yang ditampilkan Flutter; tambahkan `--allow-origin` untuk origin lain yang diperlukan. CORS tidak memakai wildcard.

Android emulator:

```sh
python -m server.app
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:7357
```

Untuk HP fisik, ganti API_BASE_URL dengan alamat server yang dapat dijangkau. Debug Android mengizinkan HTTP untuk demo LAN; release Android memakai HTTPS. Build APK:

```sh
flutter build apk --release --dart-define=API_BASE_URL=https://ALAMAT_SERVER_ANDA
```

Build iOS memerlukan macOS, Xcode, dan signing. Jangan memakai URL contoh sebagai server nyata. `API_BASE_URL` adalah konfigurasi publik; jangan menyertakan password.

## Akun dan data

- Tambah akun petugas melalui `python -m server.app --add-officer`. Tidak ada akun admin wajib atau password tetap yang ditanam di aplikasi.
- Jika lupa password awal, tambahkan username petugas baru dengan perintah tersebut. Jangan menghapus database untuk mereset akun.
- Database pusat: `data/qpark_server_v3.db`. File dibuat pada pemakaian pertama; data uji dan kredensial tidak dimasukkan ke ZIP.
- Nopol lokal menggunakan key preferensi `qpark_*_v3`. SQLite versi lama bernama `qpark_flutter_v1` tetap dibiarkan utuh.
- Tidak ada konversi otomatis transaksi tunai lama menjadi sesi atau pelunasan QRIS baru.
- Untuk file SQLite lama yang sudah diekspor: `python scripts/import_legacy.py lokasi/database_lama.db`. Data dipindahkan ke tabel arsip terpisah, bukan menjadi sesi aktif.
- Backup: `python scripts/backup_database.py data/qpark_server_v3.db backup/qpark_2026.db`.
- Pemulihan: hentikan server, simpan salinan database sekarang, lalu jalankan `python -m server.app --db backup/qpark_2026.db`. Jangan mengganti database saat server berjalan.

## Struktur revisi

- `lib/ui/common.dart`: tema dan komponen visual existing, dipertahankan.
- `lib/ui/app.dart`: shell existing yang disesuaikan untuk pengendara/petugas.
- `lib/ui/pages/`: layar existing yang direvisi dan tambahan pengendara/keluar.
- `lib/logic/remote_service.dart`: nopol lokal, sinkronisasi, pending operation, logout offline.
- `lib/data/remote_repository.dart`: klien HTTP.
- `server/rules.py`, `store.py`, `schema.sql`, `app.py`: aturan, transaksi, skema, API dan server web.
- `test/`, `server/tests/`: pengujian SRS baru.
- `docs/legacy_v2/`: arsip dokumentasi, source, dan tes lama yang tidak lagi menjadi acuan perilaku v3.

Modul tunai/admin lama yang tidak dipanggil runtime tetap tersedia untuk referensi dan riwayat perubahan. Menu motor, tunai, pengaturan tarif/kapasitas, dan admin dinonaktifkan dari navigasi utama karena tidak sesuai lingkup SRS terbaru.

## Mengulang smoke test browser (opsional untuk developer)

Diperlukan Node.js, paket Playwright, serta Chromium Playwright. Komponen ini tidak diperlukan untuk menjalankan aplikasi biasa. Sesudah memasang `playwright` dan menjalankan `npx playwright install chromium`, jalankan `node scripts/browser_smoke.cjs` dari proyek. Skrip memakai database sementara, akun uji, tiga konteks browser, dan port 7358. Atur `PYTHON`, `QPARK_TEST_PORT`, atau `PLAYWRIGHT_CHROMIUM_EXECUTABLE` jika lingkungan Anda berbeda. Skenario berakhir dengan ringkasan JSON; tes tidak memakai uang atau gerbang nyata.
