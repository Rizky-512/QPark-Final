# Prediksi parkir dan pemasangan API Gemini

Halaman Analisis kini berisi prediksi 30 menit, dua ringkasan kunjungan, pie chart
motor/mobil dengan persentase, dan grafik jam kedatangan. Detail model dan tanggal
ada di bagian yang bisa dibuka. Kalender dapat berpindah bulan dan tahun.

## Peran supervised learning dan Gemini

Linear regression mempelajari jumlah seluruh kendaraan tepat 30 menit mendatang,
termasuk kendaraan baru yang masuk. Logistic regression mempelajari peluang jumlah
itu mencapai minimal 80% kapasitas. Keduanya dilatih dari riwayat masuk/keluar.
Gemini menjelaskan hasil model melalui tombol **Jelaskan dengan AI**, maksimal tiga
kalimat sederhana. API tidak membuat angka prediksi atau menggantikan data latih.
Jika Gemini belum aktif/gagal, prediksi regresi dan grafik tetap berjalan.

## Step by step memasang API

### 1. Siapkan key dan model

Buka https://aistudio.google.com/apikey. Buat/pilih API key Google untuk proyek Anda.
Pastikan kuota tersedia dan catat **model ID** teks yang dapat dipakai di AI Studio,
bukan nama tampilannya. Model sengaja tidak dikunci di kode karena ketersediaannya
berbeda antar akun dan dapat berubah. Jangan kirim API key ke chat.

### 2. Masukkan API key di sini

1. Buka **Supabase Dashboard > proyek QPark > Edge Functions > Secrets**.
2. Tambahkan nama **GEMINI_API_KEY**. Pada Value, tempel API key Google, lalu simpan.
3. Tambahkan nama **GEMINI_MODEL**. Value adalah model ID yang tersedia di AI Studio,
   tanpa awalan `models/` dan tanpa akhiran `:generateContent`.

Inilah tempat Anda memberikan API key. Jangan masukkan key Gemini di kode Dart,
`dart_defines.json`, frontend Vercel, SQL, atau GitHub. Function membaca key melalui
`Deno.env.get`. SUPABASE_URL dan SUPABASE_SERVICE_ROLE_KEY disediakan otomatis oleh
runtime Edge Function; jangan salin service role ke aplikasi.

### 3. Pasang migrasi database

Gunakan proyek Supabase yang sama dengan aplikasi. Jika migrasi lama sudah terpasang,
buka SQL Editor, salin seluruh isi satu file, klik Run, kemudian lanjut berikutnya:

1. `supabase/migrations/202610290001_parking_forecast.sql` jika belum pernah dipasang.
2. `supabase/migrations/202610290002_supervised_forecast.sql` untuk dataset model baru.
3. `supabase/migrations/202610290003_ai_explanation.sql` untuk akses admin dan pembatasan
   panggilan AI satu kali per menit per admin.

Jika seluruh migrasi dikelola dengan CLI, gunakan db push pada langkah berikut.
Jangan menandai migrasi manual sebagai terpasang tanpa memeriksa database.

### 4. Deploy Edge Function

Buka PowerShell di folder repo, lalu jalankan (gunakan .cmd pada Windows):

```powershell
npx.cmd supabase login
npx.cmd supabase link --project-ref PROJECT_REF_ANDA
# Jalankan hanya bila migrasi dikelola CLI, bukan sudah dipasang manual:
npx.cmd supabase db push
npx.cmd supabase functions deploy parking-explain
```

PROJECT_REF_ANDA adalah bagian sebelum `.supabase.co` pada URL proyek.
File function ada di `supabase/functions/parking-explain/index.ts` dan `handler.ts`.
`supabase/config.toml` mengatur verify_jwt=false khusus function ini karena admin
QPark memakai token sesi sendiri, bukan JWT Supabase Auth. Akses tetap diverifikasi
oleh RPC qpark_ai_claim: token aktif dan peran ADMIN wajib sebelum memanggil Gemini.
RPC hanya dapat dipanggil backend dengan service role. Jangan hapus pemeriksaan ini.

### 5. Coba dari aplikasi

1. Tunggu deployment Vercel terbaru selesai, refresh dengan Ctrl+F5, lalu login admin.
2. Buka Analisis > Muat ulang. Prediksi berada paling atas.
3. Klik Jelaskan dengan AI. Penjelasan akan muncul di bawah tombol.
4. Jika belum aktif, periksa Secrets dan deployment function. Jika kuota/model gagal,
   periksa proyek Google AI Studio. Jika sesi ditolak, login ulang dan cek migrasi AI.
   Tunggu satu menit sebelum mencoba lagi.
5. Jika model masih belajar, kumpulkan riwayat yang lengkap dan bervariasi. API key
   tidak dapat menggantikan riwayat yang kurang atau model yang belum lolos evaluasi.

Vercel melayani `rilis/web`. Build hasil revisi ikut di-push. Untuk perubahan berikutnya,
`python scripts/build_release.py` membangun web memakai konfigurasi koneksi lokal;
push hasil rilis bersama sumber. Database dan Edge Function tidak otomatis ter-deploy
hanya dengan push ke GitHub.

## Implementasi Fundamen Sains Data

Desain mengikuti bagian 3-6 laporan riset yang dilampirkan, menggantikan model satu
fitur sebelumnya. Implementasi aplikasi: `lib/data/parking_forecast.dart`. Modul CLI
`qpark_ml` tetap eksperimen OLS terpisah.

- Dataset setiap 15 menit, horizon 30 menit, maksimal 56 hari. Fitur: N(t), jumlah
  masuk/keluar 30 menit terakhir, sin/cos jam WIB, indikator Selasa-Minggu.
- Target linear: N(t+30m). Label logistik: 1 jika target >= ceil(0,8 x kapasitas),
  selain itu 0. Pembayaran tidak mengosongkan tempat; gunakan keluar fisik.
- Python/Supabase membentuk dataset agregat. Flutter melatih kedua model ketika
  laporan dimuat. Koefisien dipelajari dari data; bukan konstanta contoh. Belum ada
  registry model permanen atau pelatihan backend terjadwal pada versi aplikasi ini.
- Pembagian waktu 60% latih, 20% validasi, 20% uji. Label yang melintasi batas
  dibuang. Scaler dilatih hanya dari data latih. Tidak ada pengacakan masa depan.
- Linear: OLS dengan modified Gram-Schmidt, melewati kolom konstan/kolinear.
  Evaluasi prediksi mentah memakai MAE dan RMSE; hasil tampilan dibatasi 0-kapasitas.
  Hanya ditampilkan bila MAE lebih baik dari persistence pada validasi dan uji.
- Logistik: sigmoid, gradient descent 800 iterasi, learning rate 0,05, regularisasi
  L2 0,01 selain intercept. Minimal 10 positif dan 10 negatif di data latih. Brier
  score harus lebih baik dari proporsi positif latih pada validasi dan uji.
  Confusion matrix, precision dan recall juga dihitung pada ambang peluang 0,5.
- Minimal 48 latih dan masing-masing 12 validasi/uji. Ini pengaman implementasi,
  bukan jaminan ilmiah. Satu kelas/gagal pembanding menghasilkan status belajar.

Riwayat dimulai ulang setelah pengaturan berubah agar kapasitas tidak tercampur.
Awal pencatatan belum menjamin tidak ada jeda pencatatan; registry gangguan belum ada.
Data simulasi bisa dipakai demonstrasi tetapi bukan bukti akurasi operasional.
Uji prospektif, audit pencatatan, kurva kalibrasi, PR-AUC, analisis akhir pekan dan
registry model adalah pengembangan lanjutan sebelum penggunaan operasional.

Gemini menerima ringkasan numerik model dari admin terautentikasi, bukan transaksi,
nopol, atau identitas pengguna. Input dibatasi angka, waktu, kapasitas, dan frekuensi.
Edge Function tidak melatih ulang model. Teks AI dapat salah; angka kartu regresi
menjadi acuan. API hanya dipanggil saat tombol ditekan, bukan otomatis saat memuat
halaman. Backend Python mendukung dataset regresi, sementara fitur Gemini saat ini
khusus koneksi Supabase.

## Referensi integrasi

- https://ai.google.dev/api/generate-content
- https://supabase.com/docs/guides/functions/secrets
- https://supabase.com/docs/guides/functions/deploy
- https://supabase.com/docs/guides/functions/auth
