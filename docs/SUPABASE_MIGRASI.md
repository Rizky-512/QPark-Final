# Supabase dan Login Google

Integrasi tahap pertama sudah aktif untuk customer:

- Supabase Auth menangani login Google dan pemulihan sesi.
- `profiles` menyimpan profil serta role setiap pengguna.
- `customer_vehicles` menyimpan daftar nopol per akun dengan Row Level Security (RLS).
- Data mode demo tetap berada di perangkat dan tidak pernah otomatis diunggah ke akun Google.
- API Python yang ada masih menangani transaksi parkir, pembayaran simulasi, admin, dan petugas. Pemisahan ini disengaja agar aturan transaksi atomik yang ada tidak berubah menjadi CRUD langsung dari klien.

Jangan pernah memasukkan `service_role` key ke aplikasi Flutter. Build klien hanya memakai **publishable key** (atau legacy anon key) dan seluruh akses tabel dibatasi oleh RLS.

## 1. Membuat skema

Buat project di Supabase. Jalankan isi file berikut melalui **SQL Editor**:

`supabase/migrations/202610200001_customer_auth.sql`

Jika Supabase CLI sudah terhubung ke project, alternatifnya:

```sh
supabase link --project-ref PROJECT_REF
supabase db push
```

Migrasi membuat trigger profil untuk pengguna baru, melakukan backfill pengguna lama, mengaktifkan RLS, dan hanya mengizinkan pengguna terautentikasi mengakses nopol miliknya sendiri.

Untuk mengangkat pengguna menjadi petugas/admin di tahap backend Supabase berikutnya, ubah role dari SQL Editor (jangan sediakan perubahan role dari klien):

```sql
update public.profiles
set role = 'ADMIN'
where id = 'UUID_PENGGUNA';
```

## 2. Mengaktifkan Google di Supabase

1. Di Google Auth Platform, buat OAuth Client bertipe **Web application**.
2. Tambahkan URL aplikasi web pada **Authorized JavaScript origins**, misalnya `http://localhost:7357` dan domain produksi.
3. Tambahkan callback Supabase berikut pada **Authorized redirect URIs**:

   `https://PROJECT_REF.supabase.co/auth/v1/callback`

4. Di Supabase Dashboard buka **Authentication -> Providers -> Google**, aktifkan provider, lalu isi Client ID dan Client Secret dari Google.
5. Di **Authentication -> URL Configuration**:
   - untuk tahap lokal, isi Site URL dengan `http://localhost:7357`;
   - tambahkan redirect URL `http://localhost:7357/**`;
   - tambahkan `id.qpark.qpark://login-callback/` untuk Android dan iOS.

Domain produksi baru ditambahkan dan dijadikan Site URL setelah alur lokal sudah
berhasil diuji. Selama tahap ini Google Authorized JavaScript origin cukup
`http://localhost:7357`.

Android dan iOS di repository ini sudah memiliki deklarasi deep-link untuk callback tersebut. Bila application ID/bundle ID diubah, ubah scheme pada `AndroidManifest.xml`, `Info.plist`, dan `SUPABASE_MOBILE_REDIRECT_URL` secara bersamaan.

## 3. Menyuntikkan konfigurasi build

Salin `dart_defines.example.json` menjadi `dart_defines.json` (file tujuan sudah diabaikan Git), lalu isi nilai project dari panel **Connect** Supabase:

```json
{
  "API_BASE_URL": "http://localhost:7357",
  "QPARK_SIMULATION": "true",
  "SUPABASE_URL": "https://PROJECT_REF.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_...",
  "SUPABASE_MOBILE_REDIRECT_URL": "id.qpark.qpark://login-callback/"
}
```

Jalankan web di Windows (launcher otomatis membaca `dart_defines.json`):

```bat
jalankan_web.bat
```

Build Android:

```sh
flutter build apk --release --dart-define-from-file=dart_defines.json
```

Build web produksi harus menggunakan `API_BASE_URL` HTTPS yang dapat dijangkau browser. Jika kedua nilai Supabase dikosongkan, aplikasi tetap dapat digunakan dalam mode demo dan tombol Google dinonaktifkan. Jika hanya salah satunya terisi, startup menampilkan kesalahan konfigurasi agar build yang rusak tidak diam-diam dirilis.

## 4. Pemeriksaan sebelum produksi

- Login Google kembali ke aplikasi pada web, Android, dan iOS.
- Tutup/buka aplikasi dan pastikan sesi dipulihkan.
- Akun A tidak dapat membaca/mengubah nopol akun B.
- Logout mengembalikan daftar kendaraan demo lokal tanpa memperlihatkan data akun sebelumnya.
- Domain produksi tercantum eksplisit pada redirect allow-list Supabase.
- Leaked-password protection, CAPTCHA/rate limit, dan kebijakan retensi data ditinjau di Dashboard.
- API parkir hanya digunakan melalui HTTPS di produksi.

## Migrasi transaksi parkir selanjutnya

Tabel sesi, invoice, pembayaran, otorisasi keluar, operasi idempoten, dan audit belum dipindahkan dari API Python/SQLite. Migrasi tahap berikutnya harus menggunakan PostgreSQL RPC atau Edge Function atomik untuk mempertahankan penguncian kapasitas, waktu server, perhitungan tarif, retry idempoten, role petugas aktif, dan audit. Jangan menggantinya dengan rangkaian insert/update langsung dari Flutter.
