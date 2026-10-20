# Arsitektur QPark 3

## Revisi bertahap dari Flutter v2

Runtime tetap Flutter/Dart. `lib/ui/common.dart` dipertahankan tanpa perubahan: AppColors, buildTheme, SurfaceCard, PageHeading, StatusPill, EmptyState, tombol dan gaya input sama dengan sumber v2. Shell responsif masih sidebar pada lebar >= 1000 dan navigasi bawah pada HP. Halaman masuk, monitor, login, dan pembayaran direvisi sesuai alur baru; halaman pengendara dan keluar ditambahkan.

Backend baru memakai Python standard library + SQLite file terpusat. Pilihan ini membuat demo dapat dibuka dari launcher yang sebelumnya sudah membutuhkan Python, tanpa akun cloud atau pemasangan framework server tambahan. Semua klien membaca server yang sama. Ini server prototipe, belum diklaim deployment produksi.

## Batas tanggung jawab

- Pengendara: pilihan nopol lokal melalui SharedPreferences. Tidak ada akun atau daftar semua kendaraan.
- RemoteService: polling 2 detik, penyimpanan operasi yang belum terkonfirmasi, status offline, pencabutan logout yang tertunda. Jam tampilan mengacu sampel waktu server + Stopwatch monotonic, bukan jam dinding perangkat.
- RemoteRepository: HTTP JSON dengan timeout 8 detik, autentikasi bearer untuk petugas. Respons 5xx/offline tidak dianggap sukses.
- Store: koneksi SQLite per request, `BEGIN IMMEDIATE`, foreign key, WAL, indeks unik sesi aktif, satu invoice dasar aktif, satu pelunasan, satu penalti per jendela, satu persetujuan aktif.
- Rules: kapasitas, tarif, durasi dan normalisasi di luar UI. Clock hanya dapat diinjeksi dari tes Python; tidak ada endpoint/setelan pengguna untuk mengubah waktu.
- Server HTTP: hanya menyajikan folder build web, tidak direktori database/source. Default localhost, CORS origin eksplisit, opsi sertifikat HTTPS.

SQLite v2 per perangkat tidak disentuh. Database pusat menggunakan nama terpisah. `migrations` menyimpan versi skema awal 1; instalasi ulang tidak mereset tabel atau mengganti akun lama. Tidak ada fitur reset data otomatis.

## Idempotensi dan pemulihan

Operasi masuk, simulasi pembayaran, izin, batal izin dan selesai keluar memiliki kunci operasi acak yang persisten selama menunggu jawaban. Jika jawaban hilang, tombol **Periksa & coba ulang** mengirim payload serta kunci sama. Server menolak pemakaian kunci sama untuk payload berbeda. Permintaan sukses tersimpan melalui referensi resource; token QR mentah tidak disimpan dalam audit atau hasil operasi.

Tagihan menggunakan get-or-create atomik dan indeks unik. Dua perangkat yang menyiapkan tagihan memperoleh invoice sama. Pelunasan invoice yang telah dibayar selalu mengembalikan attempt sukses terdahulu, termasuk jika kunci perangkat kedua berbeda. Jendela tidak diperpanjang oleh retry.

Pending operasi pengendara bertahan ketika aplikasi dibuka ulang. Kredensial login tidak dipertahankan sebagai sesi aktif antarrestart. Operasi petugas yang belum terkonfirmasi tidak otomatis diterbitkan ulang setelah logout/restart: petugas login kembali dan membaca keadaan server terlebih dahulu. Sesi aktif unik dan status otorisasi mencegah mutasi ganda; respons yang hilang pada sesi sebelumnya dapat direkonsiliasi di monitor.

Logout langsung mengunci akses lokal; token untuk pencabutan yang belum berhasil disimpan terbatas sebagai antrean revokasi, dikirim ulang saat online, lalu dihapus. Server menolak token setelah dicabut atau mencapai 8 jam. Antrean token ini adalah keterbatasan penyimpanan prototipe web; bukan klaim vault perangkat.

## QR, gambar, dan keamanan

QR pembayaran hanya string simulasi; tidak mengandung data merchant bank. QR keluar menggunakan HMAC-SHA256 dengan secret acak server dan ID jendela acak. Server menyimpan digest token, menerbitkan kembali token deterministik untuk jendela sama, dan menolak versi sebelumnya setelah pembaruan. Secret berada dalam database server dan ikut dalam backup agar tiket tetap konsisten setelah restore.

Password di-hash PBKDF2-HMAC-SHA256, 310.000 iterasi, salt acak per akun. Akun awal mempunyai password acak yang hanya ditampilkan di terminal pertama kali. Endpoint petugas selalu memeriksa akun aktif, digest token, pencabutan, dan kedaluwarsa.

Gambar dari image picker divalidasi sebagai gambar yang bisa didekode, ditampilkan di memori, dan tidak diunggah. Nopol dibaca petugas, tanpa OCR. Pemindai keluar menggunakan mobile_scanner; ZXing JS pada web disertakan lokal untuk menghindari ketergantungan CDN saat demo. Kamera CCTV/IP gate belum diintegrasikan; input uji dan kamera perangkat merupakan adaptor prototipe.

## Batas perilaku yang dipertahankan

AS-01 sampai AS-09 dalam SRS dipakai sebagai keputusan kerja. Minimum panjang nopol implementasi 1, maksimum teknis 32 karakter alfanumerik, tanpa menebak karakter. Tidak ada aturan kepemilikan/perangkat eksklusif karena SRS mengizinkan nopol sama di banyak perangkat. Risiko akses berdasarkan nopol tetap ada dan wajib divalidasi sebelum layanan publik.

Tidak ada admin wajib, motor, kas tunai, reservasi, sensor slot, QRIS nyata, palang fisik, atau klaim akses dua jaringan. Menu lama dinonaktifkan; source dan pengujian lama disimpan sebagai arsip agar perubahan dapat ditinjau.
