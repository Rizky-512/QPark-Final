# QPark v5 — login customer dan Analisis Parkir

Revisi bertahap dari ZIP v4. Tema hijau, pencatatan mobil/motor, QR simulasi, pembayaran manual, verifikasi petugas, riwayat tiga peran, tarif dan pengelolaan akun tetap digunakan.

## Login

Aplikasi membuka **Login customer** saat dimulai ulang. **Coba sebagai customer demo** membuka fitur customer tanpa akun formal. Ini bukan login Google. Nopol tetap tersimpan pada perangkat, termasuk setelah logout. Opsi **Login admin / petugas** berada di bawah form customer dan memakai autentikasi server yang sudah ada. Logout kembali ke halaman login customer.

Akun awal database baru: `admin / admin123` dan `petugas / petugas123`. Akun/password yang sudah diubah pada v4 tidak direset.

Tombol Google ditampilkan tetapi belum aktif. `CustomerAuthProvider` pada `lib/logic/customer_auth.dart` disiapkan untuk provider Supabase nanti. Implementasi `PendingSupabaseAuth` tidak menghubungi layanan cloud, tidak menyimpan kunci, dan tidak berpura-pura berhasil login. Provider dapat diinjeksi lewat konstruktor `RemoteService`.

Integrasi setelah persetujuan perlu mencakup OAuth, redirect web/Android, manajemen sesi, verifikasi token di backend, dan kebijakan akses tiket/riwayat. Mengaktifkan tombol saja belum cukup. Untuk saat ini akses customer berbasis nopol masih mengikuti prototipe v4; nopol bukan bukti kepemilikan akun.

## Analisis Parkir

Admin membuka menu **Analisis**. Endpoint `GET /api/admin/analytics` memeriksa token dan peran di server (401 tanpa login, 403 untuk petugas). Periode: 7, 30, 90 hari atau rentang tanggal maksimal 366 hari. Batas waktu kalender menggunakan WIB. Data dimuat saat menu dibuka dan melalui tombol muat ulang.

1. Kendaraan masuk menurut jam, tanggal dan nama hari: jumlah sesi dengan waktu masuk dalam periode, bukan nopol unik.
2. Rata-rata dan median durasi: menit sebenarnya dari masuk sampai keluar untuk sesi yang masuk dalam periode dan sudah selesai saat laporan dibuka. Keluar setelah akhir periode tetap dihitung dalam populasi tersebut. Sesi aktif dikecualikan, jumlahnya ditampilkan. Tanpa sesi selesai, hasil kosong, bukan nol menit.
3. Mobil vs motor: jumlah sesi masuk menurut jenis kendaraan.
4. QR vs manual: jumlah tagihan PAID dengan waktu pembayaran dalam periode, disertai total nominal masing-masing. Penalti dihitung sebagai tagihan terpisah; satu kendaraan bisa memakai kedua metode. Tagihan pending/gagal/kedaluwarsa tidak dihitung.
5. Keterisian menurut waktu: grafik harian dan peta warna hari × jam. Kendaraan dihitung sejak masuk sampai keluar fisik dikonfirmasi. Membayar atau memperoleh izin keluar belum membebaskan slot. Sesi yang masuk sebelum periode tetapi masih berada di area tetap dihitung.

Rata-rata keterisian = jumlah `(kendaraan aktif / kapasitas saat itu) × lama interval` dibagi lama pengamatan, dikalikan 100%. Perubahan kapasitas dibaca dari audit. Kapasitas sebelum perubahan pertama adalah kapasitas awal v4 (20). Perhitungan mengasumsikan audit tidak dihapus dan kapasitas tidak diubah langsung lewat SQL. API juga mengembalikan rata-rata jumlah kendaraan serta puncak kendaraan sekaligus.

Hari/jam paling terisi dipilih dari rata-rata persentase keterisian terbesar pada kombinasi hari dan jam yang teramati. Jika seri, label utama memakai urutan Senin–Minggu dan jam lebih awal; peta warna menampilkan seluruh kombinasi. Tanpa keterisian positif, aplikasi belum menyimpulkan waktu paling padat.

Pengamatan dimulai dari inisialisasi sistem atau sesi paling awal, mana yang lebih awal. Hari ini hanya dihitung sampai waktu pembaruan. Waktu sebelum data tersedia bernilai kosong; waktu teramati tanpa kendaraan bernilai nol. Populasi durasi, pembayaran, kedatangan dan keterisian berbeda, sehingga total tidak harus sama. Data menggambarkan catatan sistem, bukan validasi sensor independen; sampel singkat belum cukup untuk generalisasi jangka panjang.

## Lingkup FSD

Hanya statistik deskriptif, agregasi waktu, perbandingan kategori, rata-rata/median, dan visualisasi. Tidak ada prediksi, machine learning, rekomendasi otomatis atau sumber data eksternal. Database operasional tidak dicampur data contoh.

## Menjalankan dan data lama

Lihat `MULAI_DI_SINI.txt`. Server tetap Python standard library + SQLite. Tidak ada dependensi grafik baru. Android scaffold dipertahankan; ZIP ini bukan APK.

Untuk memakai data v4, hentikan server lama dan buat cadangan, lalu salin `data/qpark_server_v3.db` ke folder data v5. Jangan menyalin database saat server aktif. Nama database dan skema tetap dipertahankan pada v5; akun/transaksi tidak direset. Jangan mengganti database pengguna dengan data pengujian. ZIP tidak menyertakan database operasional.
