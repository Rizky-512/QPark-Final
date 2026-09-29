# Checklist penerimaan di Windows

Belum dicentang karena pengujian native Windows belum dijalankan di lingkungan pengerjaan. Gunakan salinan proyek dengan database baru; jangan menghapus data demonstrasi yang ingin dipertahankan. Data awal: Motor 2 slot Rp2.000/jam; Mobil 1 slot Rp5.000/jam. Skenario independen menyiapkan ulang database uji.

| Cek | Uji | Langkah dan hasil yang harus terlihat |
|---|---|---|
| [ ] | AT-01 | Login petugas benar membuka Beranda; kata sandi salah dan akun nonaktif ditolak. Isi form masuk lalu Keluar akun: Kembali mempertahankan isian, Lanjut keluar membuang isian. Fungsi terlindungi harus meminta login lagi. |
| [ ] | AT-02 | Login Admin: menu masuk/bayar tidak ada. Login Petugas: pengaturan/pendapatan tidak ada. Tes service juga memastikan pemanggilan langsung ditolak. Buat username yang sudah ada atau kata sandi 7 karakter: ditolak. |
| [ ] | AT-03 | Simpan satu Motor: ID unik, waktu otomatis, tarif Rp2.000 dan Aktif/Belum Bayar tampil. Kembali ke Beranda: terisi 1, kosong 1. |
| [ ] | AT-04 | Saat AB1234CD aktif, masukkan `ab 1234 cd` sebagai Motor maupun Mobil: ditolak. Setelah dibayar, pelat yang sama boleh masuk lagi dengan ID baru. |
| [ ] | AT-05 | Simpan dua Motor, motor ketiga ditolak; Mobil tetap kosong 1. Coba isian kosong, `A1`, `AB-123`, dan pelat lebih dari 12 karakter: ditolak. |
| [ ] | AT-06 | Periksa hasil tes clock deterministik untuk 0/60/61 menit = 1/1/2 jam dan 23.30–00.30 = 1 jam. Untuk demonstrasi waktu nyata, masukkan kendaraan dan periksa estimasi sebelum/sesudah batas jam; waktu tidak dapat diedit dari UI. |
| [ ] | AT-07 | Pada biaya Rp4.000, uang Rp3.000 ditolak dan Rp5.000 memberi kembalian Rp1.000. Konfirmasi menghasilkan bukti lengkap, Selesai/Lunas, dan slot kosong bertambah. Coba `5.000`, `Rp5.000`, `1.5`, `-1`: dua pertama diterima, dua terakhir ditolak. |
| [ ] | AT-08 | Buka estimasi lalu Batal/Kembali pada dialog: kendaraan tetap aktif. Klik konfirmasi cepat dua kali: satu pembayaran. Jalankan tes rollback kegagalan simpan dan cek slot tidak terlepas sebelum sukses. |
| [ ] | AT-09 | Buka estimasi menjelang satu jam, tunggu melewati batas, lalu konfirmasi. Total dan kembalian baru harus tampil; transaksi tetap Aktif sampai dikonfirmasi ulang. Pengujian clock terkontrol tersedia agar tidak harus menunggu satu jam. |
| [ ] | AT-10 | Bayar Motor/Mobil, filter tanggal keluar dan jenis; cari pelat serta ID, buka detail. Periksa awal dan akhir hari pada tes deterministik. Admin melihat jumlah lunas dan total biaya (bukan uang diterima). Periode kosong = 0 dan Rp0; rentang terbalik ditolak. |
| [ ] | AT-11 | Dengan satu Motor aktif, kapasitas 0 ditolak. Tarif 0/negatif/pecahan ditolak. Naikkan tarif menjadi Rp3.000: kendaraan lama tetap Rp2.000, kendaraan baru Rp3.000. |
| [ ] | AT-12 | Tutup aplikasi lalu buka dengan launcher.py, run.bat, dan main.py melalui venv. Data harus tetap tersedia. Jalankan semua tes serta benchmark. Pada 1366×768, buka keenam halaman, scroll, dialog, Tab, Enter, cek tidak bertumpuk/terpotong dan status memakai ikon/teks. Periksa hash, akses peran, dan pesan database gagal pada pengujian tambahan. |

## Pemeriksaan launcher khusus

- [ ] Ekstraksi bersih tanpa .venv: Run pada launcher.py menyiapkan dependensi dan membuka login.
- [ ] Peluncuran kedua tidak memasang paket ulang.
- [ ] `run.bat` bekerja dari folder yang namanya mengandung spasi dan mempertahankan pesan saat gagal.
- [ ] Setelah penyiapan, `.venv\Scripts\python.exe main.py` atau `python main.py` dalam venv membuka aplikasi.
- [ ] Uji venv rusak pada salinan proyek: pemulihan tidak mengubah data/qpark.db.
- [ ] Jendela muncul di layar aktif dan berada di depan; periksa juga Windows scaling/DPI laptop pengguna.

Catat versi Windows, versi Python, RAM/CPU, skala tampilan, hasil, serta tanggal pemeriksaan sebelum menyatakan semua NFR diterima.
