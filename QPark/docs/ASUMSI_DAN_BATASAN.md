# Asumsi dan batas verifikasi

1. Tidak ada traceback Windows di masukan. Gejala yang diasumsikan: “jendela tidak muncul / langsung tertutup”. Diagnosis membedakan temuan kode dari hipotesis lingkungan perangkat.
2. Sasaran Windows 10/11 64-bit dengan Python 3.10+. Python 3.12 dianjurkan dan sintaks semua file diperiksa agar kompatibel dengan grammar Python 3.10. Interpreter yang benar-benar dipakai untuk tes adalah Python 3.12.14 di Linux.
3. Instalasi pertama memerlukan internet untuk wheel dan client Flet; launcher tidak dapat mengatasi tidak adanya Python, internet, pemblokiran antivirus, atau wheel platform yang belum diterbitkan. Flet dan flet-desktop dipin 1.0.2 untuk mencegah perubahan API minor tanpa pengujian.
4. Data demo berarti konfigurasi Motor 2/Rp2.000, Mobil 1/Rp5.000, dan dua akun awal. Tidak ada transaksi demo bawaan. Database dibuat ketika aplikasi pertama menyiapkan halaman.
5. Satu lokasi, satu operator pada satu waktu, sesuai SRS. Pengaman dua operasi bersamaan tetap diuji. Sesi lokal mengikat ID pengguna pada satu instance repository/proses; bukan token autentikasi layanan jaringan.
6. Waktu memakai jam lokal komputer. Diasumsikan disetel ke zona lokasi parkir, misalnya Asia/Jakarta. Perubahan jam mundur yang menghasilkan waktu keluar sebelum masuk ditolak. Pengguna tidak mengedit timestamp dari UI.
7. Input nominal adalah integer rupiah; titik hanya sebagai kelompok ribuan yang valid. Prefix Rp opsional. Pecahan dan notasi ilmiah ditolak. Batas angka SQLite signed 64-bit diberlakukan agar input besar tidak menimbulkan OverflowError.
8. Riwayat selesai tidak bisa diubah/dihapus dari aplikasi. Tidak ada refund, denda, diskon, lokasi tambahan, atau integrasi Supabase yang diimplementasikan.
9. Semua tes asli dipertahankan identik. Pengujian UI mengonstruksi kontrol dan menjalankan callback dengan serializer Flet 1.0.2 asli, tetapi memakai FakePage sebagai pengganti koneksi jendela. Keberhasilan ini tidak membuktikan layout pixel pada Windows.
10. Render visual 1366×768, keyboard/fokus native, perilaku launcher Windows/Microsoft Store/run.bat, dan unduhan client Windows belum diverifikasi langsung. Instalasi alat render tambahan di lingkungan ini tidak berhasil. `python main.py` berjalan sebagai server Flet karena Linux tanpa display, bukan sebagai jendela Windows.
11. Benchmark mengukur lapisan service/repository, tidak mencakup waktu render Flutter di laptop pengguna. NFR-02 tetap perlu dikonfirmasi pada perangkat tim; spesifikasi pengujian dan hasil lokal dicatat di HASIL_PENGUJIAN.md.
12. Rencana Supabase membutuhkan autentikasi server dan RPC atomik. Registry sesi lokal dan pengambilan hash tidak boleh dipakai sebagai keamanan jaringan. Tidak ada secret layanan dalam kode.
