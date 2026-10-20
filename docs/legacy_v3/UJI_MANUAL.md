# Checklist uji penerimaan pengguna

Dokumen ini adalah panduan pelaksanaan, bukan klaim hasil uji lapangan.

1. Jalankan `buka_web.bat`; catat kredensial awal. Buka pengendara pada browser A dan petugas pada browser B/profil berbeda.
2. Simpan B123AB di dua perangkat. Tambah, edit, hapus nopol lokal; pastikan sesi pusat tidak berubah.
3. Login petugas dengan password salah, lalu benar. Masukkan kendaraan dengan `samples/kendaraan_uji.png`. Tanpa centang verifikasi, tombol terima harus tidak aktif.
4. Amati tiket pada kedua perangkat. Lakukan simulasi pending, gagal, lalu sukses dari perangkat keluarga. Hanya sukses memulai 15 menit.
5. Pindai QR keluar memakai kamera perangkat petugas. Catat jenis perangkat, browser, HTTPS/localhost, pencahayaan, ukuran QR, dan keberhasilan baca.
6. Coba nopol kendaraan berbeda, QR pembayaran sebagai QR keluar, screenshot QR jendela lama, dan token sembarang.
7. Izinkan keluar: kapasitas belum bertambah. Konfirmasi kendaraan lewat: kapasitas bertambah sekali. Ulangi konfirmasi untuk memastikan tidak bertambah lagi.
8. Tunggu 15 menit untuk penalti; refresh berulang dan pastikan satu tambahan. Bayar tambahan, periksa 15 menit baru. Tidak ada tombol ubah jam pada build pengguna.
9. Berikan izin saat batas hampir habis lalu konfirmasi sebelum 120 detik; tidak ada penalti selama izin aktif. Uji pembatalan dan izin 120 detik habis.
10. Putuskan koneksi sebelum mutasi dan setelah server menerima mutasi. Jangan menerima indikator sukses palsu. Sambungkan lalu gunakan Periksa & coba ulang.
11. Logout offline, cek akses langsung terkunci, kemudian pulihkan koneksi dan pastikan sesi server dicabut.
12. Restart server dan lakukan backup/restore pada data uji. Tidak boleh ada kehilangan sesi/transaksi yang sudah commit.

## Format pencatatan

| AT | Tanggal / perangkat | Langkah | Hasil aktual | Lulus / gagal | Bukti / catatan |
|---|---|---|---|---|---|
| | | | | | |

Untuk NFR-06/AT-35, libatkan peserta uji, catat sedikitnya 10 percobaan tugas inti, jumlah selesai tanpa bantuan, waktu, kesalahan, dan komentar. Jangan mengganti hasil peserta dengan tes otomatis.

Untuk NFR-01, ukur 100 perubahan yang terlihat pada UI klien lain dengan profil 20 sesi dan 10 klien, bukan sekadar kecepatan HTTP. Untuk AT-38, gunakan dua jaringan berbeda melalui HTTPS jika ingin menyatakan skenario pembayaran dari rumah teruji. Jangan membuka server publik tanpa penyiapan dan otorisasi yang sesuai.
