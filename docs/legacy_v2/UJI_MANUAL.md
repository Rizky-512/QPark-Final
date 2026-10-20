# Checklist AT-01–AT-12 untuk Flutter

Jalankan pada instalasi uji dengan data demo. Kotak ini untuk penerimaan manual pada perangkat pengguna; tidak otomatis dicentang berdasarkan unit test. Hasil otomatis dicatat terpisah.

| Cek | Uji | Langkah dan hasil |
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
| [ ] | AT-12 | Tutup/buka aplikasi atau browser pada origin yang sama: data tetap ada. Jalankan flutter analyze dan flutter test. Cek semua halaman pada 1366×768 dan layar HP 390×844/320×640, keyboard, scroll, dialog, Tab/Enter, status ikon+teks. Jalankan integration_test pada HP, lalu coba dua tab browser serentak. |
