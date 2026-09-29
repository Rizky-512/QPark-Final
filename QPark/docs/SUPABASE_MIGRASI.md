# Rencana migrasi Supabase

Dokumen ini hanya rencana. Versi final tetap SQLite; tidak ada dependensi, koneksi, proyek Supabase, atau secret Supabase yang dibuat.

## Skema PostgreSQL setara

| SQLite saat ini | Rancangan PostgreSQL |
|---|---|
| users.id_user INTEGER PK | bigint identity PK; tambahkan auth_user_id UUID unik yang merujuk identitas Supabase Auth |
| nama, username, role | text; username lowercase unik; role Admin/Petugas dibatasi CHECK |
| users.aktif 0/1 | boolean NOT NULL |
| password_hash | Jangan diekspos lewat Data API; rencanakan reset/migrasi Auth, bukan mengirim hash ke desktop |
| tarif_parkir | jenis_kendaraan text PK dengan CHECK Motor/Mobil; tarif_per_jam bigint positif |
| kapasitas_parkir | jenis_kendaraan FK/PK; kapasitas integer atau bigint nonnegatif |
| transaksi_parkir | id_transaksi text PK; semua field, status, FK, dan CHECK setara schema.sql |
| Waktu lokal ISO TEXT | timestamptz; konversi waktu lama secara eksplisit dari zona Asia/Jakarta sebelum impor |
| Rupiah INTEGER | bigint, tidak memakai float |

Pertahankan partial unique index pelat dengan kondisi Aktif, indeks status/jenis dan waktu_keluar, kelengkapan rincian lunas, serta larangan ubah/hapus transaksi selesai. Slot tetap hasil hitung transaksi aktif. Filter hari memakai batas hari Asia/Jakarta yang dikonversi menjadi instant UTC.

## Operasi atomik di server

Simpan masuk dan pembayaran wajib satu function/RPC server, bukan beberapa request HTTP dari desktop. Buat `SupabaseParkingRepository` sebagai adapter domain dan pilih melalui `create_repository` ketika tahap migrasi benar-benar disetujui.

- **Masuk:** identifikasi petugas dari sesi tervalidasi server; cek aktif/peran; lock baris konfigurasi jenis kendaraan; periksa pelat dan jumlah aktif; ambil tarif server; buat waktu/ID server; INSERT; kembalikan transaksi. Semua penulis masuk dan pengubah kapasitas harus memakai lock konfigurasi yang sama agar dua gerbang tidak melampaui kapasitas.
- **Pembayaran:** lock transaksi dengan `SELECT ... FOR UPDATE`; cek masih Aktif dan petugas aktif; hitung durasi/tarif snapshot dengan waktu server; bandingkan expected_total dari layar. Jika berubah, kembalikan kode PRICE_CHANGED dan total baru tanpa UPDATE. Jika sama dan uang cukup, UPDATE seluruh rincian keluar/pembayaran sekaligus. Permintaan kedua mendapat status sudah selesai.
- **Kapasitas/tarif:** lock konfigurasi jenis yang sama; hitung aktif; tolak kapasitas terlalu kecil; ubah kedua nilai atomik. Urutan lock harus konsisten untuk menghindari deadlock.
- Adapter memetakan respons server ke PaymentQuote/Transaction dan ParkingError. Server tidak mempercayai total, waktu, peran, atau ID petugas kiriman client; service lokal tetap memvalidasi untuk pengalaman pengguna.

Catatan kontrak: parameter waktu/jam/total yang ada pada repository lokal adalah hasil service tepercaya di satu proses. Dalam adapter jaringan kelak, total tersebut diperlakukan sebagai **expected_total**, sementara server menghitung ulang nilai otoritatif. Quote juga harus memakai waktu server agar konsisten. Perubahan penambahan operasi quote server pada kontrak harus disertai tes adapter; jangan menyamarkan jam lokal sebagai waktu server.

## Row Level Security dan identitas

Aktifkan RLS dan batasi EXECUTE fungsi pada role yang benar. Pemeriksaan `auth.uid()` dipetakan ke akun aktif; hak Admin/Petugas diambil dari data server. Penonaktifan akun harus ditinjau pada setiap RPC, bukan hanya klaim peran lama dalam token.

- Admin: konfigurasi, petugas, riwayat/detail, dan pendapatan; tidak boleh mencatat masuk/bayar.
- Petugas: baca dashboard/riwayat/detail dan jalankan RPC masuk/bayar; tidak mengubah konfigurasi atau membaca agregasi pendapatan khusus admin.
- Data hash dan pengelolaan autentikasi jangan dibuka melalui tabel publik.
- Service-role/secret key tidak boleh dimasukkan dalam desktop, .env.example, git, atau ZIP. Pakai autentikasi per pengguna dengan policy server.
- Gunakan fungsi security invoker bila cukup. Jika security definer diperlukan untuk mutasi terkontrol, tetapkan search_path aman, nama tabel lengkap, otorisasi eksplisit, dan cabut akses fungsi default yang tidak diperlukan.

API login lokal sekarang membaca hash melalui repository. Ini tidak boleh diterjemahkan menjadi download hash di Supabase. Pada migrasi jaringan, tambahkan adapter autentikasi server/Supabase Auth dan sesi token; UI tetap memanggil AuthService. SQLite dan bootstrap lokal tidak diubah sampai versi jaringan diuji.

## Tahapan

1. Buat proyek staging dan migrasi skema/policy/function; siapkan pemetaan identitas.
2. Tambah adapter dan konfigurasi backend tanpa mengubah SQL/UI secara langsung.
3. Jalankan kembali semua AT, termasuk konkurensi, rollback, pengguna nonaktif, dan pengujian RLS memakai token Admin/Petugas/anon.
4. Uji timeout jaringan dan respons pembayaran yang hilang; gunakan ID transaksi untuk membaca status sebelum mengulang pembayaran.
5. Cadangkan SQLite, konversi waktu, impor data, cocokkan jumlah transaksi serta total biaya, lalu lakukan perpindahan terencana.

Referensi: [Database Functions](https://supabase.com/docs/guides/database/functions), [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [keamanan secret](https://supabase.com/docs/guides/database/secure-data), [PostgreSQL locking](https://www.postgresql.org/docs/17/explicit-locking.html).
