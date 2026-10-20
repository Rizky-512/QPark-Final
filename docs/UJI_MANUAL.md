# Checklist demonstrasi QPark 4

- [ ] Login admin/admin123; terlihat Kelola, Riwayat, dan menu operasional.
- [ ] Login petugas/petugas123; Kelola tidak tersedia dan endpoint admin menolak peran Petugas.
- [ ] Catat Mobil dan Motor melalui input manual, lalu ulangi lewat foto uji.
- [ ] Tanpa verifikasi fisik, kendaraan ditolak. Saat kapasitas penuh, kendaraan berikutnya ditolak.
- [ ] Bayar QR oleh pengendara/keluarga; perangkat lain menerima status lunas/QR keluar.
- [ ] Bayar manual Motor: Rp2.000, uang diterima Rp5.000, kembalian Rp3.000.
- [ ] Uang kurang ditolak; nopol tidak cocok ditolak.
- [ ] Izin keluar belum menambah kapasitas; konfirmasi lewat menambah tepat satu.
- [ ] Tagihan yang lunas QR tidak boleh ditagih ulang manual; muat ulang menampilkan Rp0.
- [ ] Riwayat staf menampilkan dua metode dan dua kendaraan. Customer hanya nopol dipilih.
- [ ] Filter tanggal, metode, kendaraan, cari nopol, dan pagination riwayat.
- [ ] Perubahan tarif admin berlaku untuk kendaraan baru; sesi aktif mempertahankan tarif awal.
- [ ] Ubah password akun, restart server, pastikan password baru tetap berlaku.
- [ ] Migrasi data v3: sesi/tiket tetap ada; akun awal default tersedia sekali pada migrasi.
- [ ] Uji kamera fisik, browser HP, dua jaringan HTTPS, dan pengguna lapangan secara terpisah.


## Tambahan v5

1. Buka/reload aplikasi: Login customer muncul, Google belum aktif.
2. Masuk demo, tambah nopol, logout, masuk demo lagi: nopol tetap ada.
3. Login admin langsung dari bawah halaman customer; buka Analisis. Petugas tidak memiliki menu tersebut.
4. Catat mobil dan motor, lunasi satu dengan QR dan satu manual, konfirmasi keluar. Muat ulang Analisis dan cocokkan dengan riwayat.
5. Ubah filter tanggal; periksa periode kosong dan kendaraan menginap.
6. Periksa layar HP/desktop dan geser horizontal grafik panjang.
