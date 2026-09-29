# QPark

Prototipe desktop pencatatan kendaraan, ketersediaan slot, dan pembayaran tunai untuk satu lokasi. Acuan: SRS v1.0 tanggal 29 September 2026. Python 3.10+, Flet 1.0.2, SQLite persisten, dan pola repository.

## Menjalankan di Windows

1. Ekstrak `QPark-Final.zip` sepenuhnya, lalu buka folder **QPark** di VS Code.
2. Pastikan Python 3.10+ **64-bit** sudah terpasang. Python 3.12 dianjurkan untuk demonstrasi.
3. Buka `launcher.py`, lalu tekan **Run Python File**, atau jalankan `python launcher.py` di terminal.
4. Tunggu penyiapan otomatis pada penggunaan pertama. Internet diperlukan untuk paket Python dan unduhan client desktop Flet. Setelah dependensi dan client tercache, operasi parkir berjalan lokal.
5. Login menggunakan akun demo di bawah.

| Peran | Nama pengguna | Kata sandi | Digunakan untuk |
|---|---|---|---|
| Admin | `admin` | `Admin123!` | Kapasitas, tarif, akun petugas, riwayat, pendapatan |
| Petugas | `petugas` | `Petugas123!` | Kendaraan masuk, pembayaran, dashboard, riwayat |

Sesuai SRS, **Admin tidak dapat mencatat masuk atau menerima pembayaran**. Gunakan akun petugas untuk demonstrasi alur parkir.

Alternatif: klik ganda `run.bat`. File ini memilih Python melalui `py` atau `python`, berpindah ke folder proyek, dan mempertahankan pesan error.

Untuk menjalankan entry point secara langsung setelah launcher menyiapkan lingkungan:

```powershell
.\.venv\Scripts\python.exe main.py
```

Jika venv sudah diaktifkan, `python main.py` cukup. Apabila launcher menggunakan `.venv-qpark` untuk memulihkan venv yang terkunci oleh VS Code, gunakan interpreter di `.venv-qpark\Scripts\python.exe`.

## Database dan akun awal

Folder `data/` sengaja kosong di ZIP. Pada pembukaan aplikasi pertama, bootstrap membuat `data/qpark.db`, skema, dan akun demo; konfigurasi awal Motor **2 slot, Rp2.000/jam**, Mobil **1 slot, Rp5.000/jam**. Tidak ada transaksi fiktif yang dimasukkan.

Pembukaan berikutnya memakai database yang sama. Tarif, kapasitas, transaksi, dan status nonaktif petugas tidak direset. Kata sandi tersimpan sebagai PBKDF2-HMAC-SHA256 dengan salt acak, bukan plaintext. Kredensial pada panduan ini adalah akun demo publik, bukan secret layanan.

Konfigurasi opsional: salin `.env.example` menjadi `.env`. `DB_BACKEND=sqlite` adalah default. `SQLITE_PATH` relatif dihitung dari folder proyek, bukan folder terminal. Variabel environment mengalahkan `.env`. Backend selain SQLite ditolak dengan pesan jelas; **Supabase belum diimplementasikan**.

## Alur demonstrasi singkat

- Masuk sebagai petugas → Kendaraan masuk → isi `AB 1234 CD` dan Motor → simpan.
- Beranda menampilkan Motor terisi 1, kosong 1; coba pelat yang sama untuk memeriksa penolakan duplikasi.
- Keluar & bayar → pilih kendaraan → isi `5000` → konfirmasi → Ya, simpan. Biaya minimum Rp2.000, kembalian Rp3.000.
- Bukti pembayaran tampil dan slot kembali tersedia. Riwayat memuat transaksi selesai.
- Keluar akun → masuk sebagai admin → Pengaturan → periksa pendapatan, tarif, kapasitas, dan akun petugas.

Input uang menerima `5000`, `5.000`, atau `Rp5.000`. Pecahan seperti `1.5` dan `1,5`, nominal negatif, dan pengelompokan salah ditolak. Tanggal filter menggunakan `YYYY-MM-DD` dan mencakup seluruh hari awal/akhir. Enter tersedia untuk login, pencarian, simpan masuk, pembayaran, filter, dan pengaturan. Tab mengikuti urutan kontrol pada form.

## Pengujian

Setelah launcher selesai menyiapkan dependensi:

```powershell
.\.venv\Scripts\python.exe -m unittest discover -v
.\.venv\Scripts\python.exe scripts\benchmark_nfr02.py
python launcher.py --check
```

Dalam venv aktif, perintah pertama dapat ditulis `python -m unittest discover -v`. Pengujian memakai database sementara tersendiri; tidak mengubah `data/qpark.db`.

Lihat `docs/HASIL_PENGUJIAN.md` untuk hasil yang benar-benar dijalankan dan batas verifikasinya. Smoke test menggunakan kontrol dan serializer Flet asli dengan koneksi halaman tiruan; bukan render native Windows. Checklist demonstrasi terdapat pada `docs/UJI_MANUAL.md`.

## Jika aplikasi tidak terbuka

- Baca pesan terminal; launcher menahan jendela saat gagal. `run.bat` juga mempertahankan exit code dan melakukan pause.
- Rincian runtime tersimpan di `logs/qpark.log`. Jangan membagikan database pribadi saat meminta bantuan; cukup traceback/log yang relevan.
- Launcher memeriksa Python, pip, impor Flet, impor desktop, dan kecocokan versi. Venv rusak dicoba pulihkan; jika dibangun ulang, lingkungan lama dipindah ke `.venv-rusak-*`. Data parkir tidak disentuh.
- Bila VS Code sedang memakai executable venv rusak, launcher membangun `.venv-qpark` agar tidak memindahkan executable yang masih terkunci.
- Jika unduhan gagal, periksa koneksi/proxy dan pesan pip. Launcher hanya memakai wheel; bila versi Python terlalu baru dan wheel belum tersedia, pilih Python 3.12 64-bit yang terpasang. Python Microsoft Store tidak otomatis dianggap rusak; yang diperiksa adalah kemampuan interpreter menjalankan pip dan impor.
- Flet mengunduh client desktop secara terpisah pada pembukaan pertama. Firewall/antivirus dapat memblokir proses ini. Pesan “client berhenti sebelum halaman siap” dibedakan dari keluar normal.
- `main.py` memanggil `ft.run(main)` dengan mode desktop. `flet run` tidak diwajibkan, sehingga CLI/web tidak ikut dipasang oleh requirements.

## Struktur dan dokumen

- `app/main.py`, `app/config.py`, `app/bootstrap.py`: titik masuk dan pemilihan backend.
- `app/ui/`: enam halaman, sesi presentasi, dan palet hijau pada `common.py`.
- `app/logic/`: autentikasi, sesi, peran, validasi, dan perhitungan bisnis.
- `app/data/`: kontrak repository, implementasi SQLite, dan skema.
- `app/domain/`: model dan kesalahan domain.
- `tests/`: delapan tes asli dan tes tambahan penerimaan, launcher, konfigurasi, UI.
- `docs/TRACEABILITY_SRS.md`: pemetaan seluruh FR, BR, NFR, serta UC dan AT.
- `docs/DIAGNOSIS_LAUNCHER.md`, `docs/DESAIN.md`, `docs/SUPABASE_MIGRASI.md`: diagnosis dan keputusan desain.

Lingkup tetap satu lokasi, Motor/Mobil, tunai, tanpa refund, denda, diskon, sensor, atau gateway pembayaran.
