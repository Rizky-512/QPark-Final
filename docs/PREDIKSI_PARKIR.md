# Prediksi parkir 30 menit mendatang

Halaman Analisis Parkir (admin) menampilkan peluang jumlah kendaraan mencapai
sedikitnya 80% kapasitas tepat 30 menit setelah laporan dimuat, serta perkiraan
jumlah seluruh kendaraan pada waktu tersebut. Termasuk kendaraan baru yang masuk;
bukan hanya kendaraan saat ini yang belum keluar. Tombol muat ulang memperbarui waktu.

## Model Fundamen Sains Data

Backend membentuk pasangan N(t), N(t+30 menit) setiap 30 menit dari waktu masuk
dan keluar fisik, maksimal 30 hari terakhir. Kendaraan yang sudah membayar tetapi
belum keluar tetap dihitung. Hanya pasangan yang target waktunya sudah teramati
yang dipakai. Filter tanggal berlaku untuk laporan historis, bukan data pelatihan.
Riwayat dimulai ulang setelah perubahan pengaturan agar kapasitas tidak tercampur.

Flutter menghitung dua model di `lib/data/parking_forecast.dart`:

- Regresi linear OLS: N(t+30) = intercept + slope × N(t). Hasil tampilan dibatasi
  antara nol dan kapasitas, lalu dibulatkan menjadi kendaraan.
- Regresi logistik: sigmoid(intercept + weight × N(t) terstandardisasi).
  Label positif adalah N(t+30) >= ceil(0,8 × kapasitas). Optimisasi gradient descent
  600 iterasi, learning rate 0,1 dan regularisasi L2 0,01 pada slope.

Minimal 48 pasangan dengan variasi N(t). Logistik juga membutuhkan masing-masing
10 label positif dan negatif. Bila syarat tidak terpenuhi, UI menunjukkan alasan,
bukan angka peluang buatan. Grafik peluang berskala 0–100%; grafik jumlah kendaraan
terpisah. 70% peluang hampir penuh tidak berarti 70% tempat terisi.

Ini model awal satu fitur, belum tervalidasi untuk keputusan operasional. Batas data
minimum bukan jaminan akurasi. Sebelum penggunaan operasional, evaluasi pada blok waktu
terakhir yang tidak digunakan melatih: MAE melawan baseline jumlah saat ini untuk linear,
Brier score dan kalibrasi peluang untuk logistik. Pola jam/hari, acara khusus dan perubahan
arus kendaraan belum menjadi fitur. Modul riset CLI `qpark_ml` tetap eksperimen terpisah.

## Aktivasi dan API

**Tidak perlu API AI, API key AI, atau biaya layanan AI.** Data berasal dari transaksi
parkir yang sudah tersimpan. Tidak ada nomor polisi dikirim ke model di Flutter;
payload prediksi hanya berisi jumlah agregat.

Untuk backend Supabase yang dipakai web:

1. Terapkan seluruh migrasi lama yang belum terpasang, lalu jalankan isi
   `supabase/migrations/202610290001_parking_forecast.sql` melalui SQL Editor proyek
   Supabase yang sama. Alternatif untuk proyek CLI yang sudah terhubung: `supabase db push`.
2. Build dan deploy ulang Flutter web sesuai panduan deployment proyek.
3. Login admin, buka Analisis Parkir dan muat ulang. Bila backend belum diperbarui,
   kartu akan meminta pembaruan backend. Bila data belum cukup, kumpulkan transaksi nyata.

Untuk backend Python, restart server dengan kode terbaru lalu build ulang Flutter.
Endpoint tetap `GET /api/admin/analytics`, autentikasi admin tetap berlaku.
Konfigurasi koneksi aplikasi tetap mengikuti `dart_defines.example.json` dan README.

Jika nanti menambahkan layanan AI eksternal untuk narasi, simpan kunci rahasia hanya
di environment backend atau Secrets Supabase Edge Function. Jangan taruh kunci rahasia
di Flutter, `dart_defines.json`, aset web, atau Git; browser dapat membacanya.
Fitur prediksi saat ini tidak memakai layanan tersebut dan tidak menyediakan kolom API key.

## Kalender

Pilih tanggal mulai lalu tanggal akhir. Dialog menyediakan panah bulan dan pemilih
tahun bawaan Flutter. Akhir tidak boleh sebelum awal, melebihi hari ini, atau membuat
periode lebih dari 366 hari. Membatalkan salah satu dialog mempertahankan filter sebelumnya.
