# Regresi linear keterisian QPark

Modul riset opsional ini memperkirakan jumlah kendaraan tepat 30 menit mendatang.
Acuan: `Laporan_Riset_QPark_Tugas_1_Regresi (1).docx`, 20 Oktober 2026,
bagian 3.1, 4, 5 dan 6. Implementasi hanya regresi linear sesuai permintaan;
usulan logistic regression dan kartu Flutter dalam dokumen bukan bagian perubahan ini.

Seluruh berkas aplikasi lama dipertahankan. Tidak ada import modul ini dari server,
endpoint baru, perubahan UI, navigasi, autentikasi, aturan tarif/pembayaran atau
migrasi database operasional. Analisis deskriptif tetap memakai `server/analytics.py`.
CLI adalah titik masuk fitur riset, dijalankan oleh pengelola yang memiliki akses
filesystem database. Integrasi tampilan membutuhkan persetujuan terpisah.

## Variabel dan persamaan

Satu sampel setiap 15 menit. Target `y=N(t+1800)` dihitung dari kunjungan dengan
`entered_at <= t+1800` dan `exited_at` kosong atau lebih besar dari waktu target.
Fitur berurutan disimpan dalam artefak JSON:

- `occupied_now`: N(t), termasuk kendaraan yang telah membayar/diizinkan keluar
  tetapi belum memiliki waktu keluar fisik.
- `arrivals_30m`: jumlah masuk pada `(t-1800,t]`.
- `departures_30m`: jumlah keluar pada `(t-1800,t]`.
- `hour_sin`, `hour_cos`: sin/cos jam desimal WIB, periode 24 jam.
- `day_1` sampai `day_6`: indikator Selasa sampai Minggu; Senin referensi.

Model multiple linear regression OLS:
`N_pred(t+30m) = intercept + sum(coefficient[j] * feature[j])`.
StandardScaler dan LinearRegression dilatih hanya pada subset latih. Koefisien
kemudian dikonversi kembali ke satuan fitur asli, sehingga inferensi JSON hanya
memerlukan pustaka standar Python. Tidak ada koefisien buatan yang diklaim hasil ML.
Tidak ada pickle atau eksekusi kode dalam artefak model. Model tetap harus berasal
dari sumber tepercaya; validasi format bukan bukti keaslian.

Eksperimen mengikuti kapasitas tetap **20** pada riset. Kapasitas adalah prasyarat
coverage, bukan fitur bebas. Audit yang menandakan perubahan kapasitas membuang
jendela terkait. Data dengan kapasitas lain memerlukan desain/validasi ulang.

## Menjalankan secara terpisah

Gunakan Python 3.13 (lingkungan yang diuji) dan folder output baru di luar repository.
Perintah PowerShell dari root proyek, tanpa menjalankan launcher/build Android:

```powershell
python -m venv "$env:TEMP/qpark-linear-venv"
& "$env:TEMP/qpark-linear-venv/Scripts/python.exe" -m pip install -r qpark_ml/requirements.txt
$mlOut = Join-Path $env:TEMP ('qpark-ml-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $mlOut
& "$env:TEMP/qpark-linear-venv/Scripts/python.exe" -m qpark_ml simulate --out "$mlOut/simulation.json"
& "$env:TEMP/qpark-linear-venv/Scripts/python.exe" -m qpark_ml train --input "$mlOut/simulation.json" --until '2026-10-18T00:00:00+07:00' --out "$mlOut/model.json"
& "$env:TEMP/qpark-linear-venv/Scripts/python.exe" -m qpark_ml predict --input "$mlOut/simulation.json" --model "$mlOut/model.json" --as-of '2026-10-19T00:00:00+07:00'
```

Simulator default: seed 512, 56 hari mulai 24 Agustus 2026 WIB. Pola kedatangan
siang/malam, akhir pekan, dan durasi acak adalah asumsi generator, bukan temuan QPark.
Tidak ada nomor polisi, akun, token, pembayaran atau identitas orang. Semua artefak
berlabel `source_kind=simulation`. Model simulasi ditolak untuk input operasional.
Satu hari terakhir disisihkan dari pelatihan/evaluasi untuk demonstrasi inferensi.
Prediksi sesudah akhir coverage hanya diperbolehkan bila fitur sampai `as_of`
tercakup; label masa depan tidak dibutuhkan saat inferensi.

Output memakai create-only: file lama tidak ditimpa. Status `insufficient_data`
adalah hasil sah; exit code 2 menunjukkan input/file/dependensi tidak valid.
`model_unavailable` berarti artefak tidak memuat model. Penolakan input tidak
menampilkan isi sesi atau kredensial dalam pesan kesalahan.

## Ekstraksi riwayat operasional

Siapkan manifest coverage berdasarkan catatan pengumpulan yang diverifikasi, bukan
berdasarkan asumsi bahwa tidak ada transaksi berarti parkir kosong. Contoh struktur
berikut sengaja belum menyatakan periode apa pun lengkap:

```json
{
  "source_kind": "operational",
  "complete_history": true,
  "coverage": []
}
```

Isi `coverage` dengan objek `start`, `end` (ISO berzona waktu) dan `capacity:20`
hanya untuk rentang pencatatan utuh yang benar-benar diketahui. Jangan memakai
`complete_history:true` sebelum memastikan semua sesi yang masih aktif sebelum
awal coverage turut tersedia. Pisahkan periode gangguan menjadi rentang terpisah.

```powershell
python -m qpark_ml extract --db data/qpark_server_v3.db --coverage C:/temp/coverage.json --out C:/temp/history.json
& "$env:TEMP/qpark-linear-venv/Scripts/python.exe" -m qpark_ml train --input C:/temp/history.json --out C:/temp/result.json
```

Ekstraksi memakai SQLite `mode=ro`, `query_only` dan satu transaksi pembacaan.
Tidak memanggil `Store`, bootstrap, pemeliharaan, atau migrasi. Hanya ID kunjungan,
waktu masuk/keluar dan audit perubahan kapasitas yang dibaca; nopol dan kredensial
tidak diekspor. Snapshot harus disimpan dengan hak akses yang sesuai.
Adapter ini khusus SQLite server QPark; database SQLite klien/desktop lama maupun
tabel operasional Supabase tidak otomatis dianggap memiliki kontrak yang sama.

Nilai kosong/NaN/infinite, ID duplikat, waktu keluar sebelum masuk, waktu masa depan
dan keterisian melebihi 20 ditolak. Satu peristiwa rusak menolak snapshot, bukan
dihapus diam-diam karena dapat mengubah semua label keterisian. Jendela tanpa
riwayat 30 menit atau target matang 30 menit tidak dibentuk. Tidak memakai status
`state` terkini untuk merekonstruksi masa lalu.

## Evaluasi dan keterbatasan

Split kronologis berdasarkan rentang waktu: 60% latih, 20% validasi, 20% uji.
`target_at` latih harus lebih awal dari awal validasi; syarat yang sama diterapkan
ke validasi/uji. Pemeriksaan menggunakan timestamp, tetap berlaku ketika grid
memiliki jeda. Tidak ada pengacakan, tuning pada test, atau refit setelah evaluasi.
Koefisien yang disimpan adalah model yang benar-benar dievaluasi.

Baseline persistence memprediksi `N(t+30m)=N(t)`. Laporan menyertakan jumlah sesi,
sampel, baris yang dibuang, periode, versi dependensi, MAE, RMSE dan R² untuk model
serta baseline pada sampel yang sama, termasuk kelompok hari kerja/akhir pekan.
R² bernilai null bila target konstan atau sampel kurang dari dua; R² dapat negatif
dan **bukan persentase akurasi**. Metrik memakai prediksi mentah; hasil dibatasi ke
0..20 hanya pada keluaran `expected_occupied_bounded`.

Batas teknis awal: minimal 48 sampel latih, 12 validasi, 12 uji dan target latih
bervariasi. Ini bukan ambang ilmiah kecukupan data. Riset menyarankan pengumpulan
4-8 minggu; sampel berdekatan tidak independen. Status prediksi ditahan apabila
MAE model tidak lebih rendah dari persistence pada validasi dan uji. Lulus pada
simulasi tidak membuktikan manfaat operasional. Keterlambatan pencatatan keluar,
perubahan pola, kapasitas, dan ketidaklengkapan audit tetap menjadi keterbatasan.
Fitur cuaca/libur dan probabilitas hampir penuh tidak ditambahkan tanpa data/metode.

Kaitan Fundamental Sains Data: identifikasi target, audit kualitas, rekonstruksi
data, rekayasa fitur, supervised regression, baseline, evaluasi temporal, dan
interpretasi kesalahan. Analisis deskriptif menjelaskan riwayat; model ini menguji
estimasi masa depan, tanpa mengambil keputusan menerima kendaraan.

Dalam arsitektur client-server, pelatihan dijalankan offline pada sisi pengelola
server. Flutter tetap memakai layanan operasional yang ada. Tidak ada data atau
proses pelatihan yang dikirim ke klien. Endpoint inferensi dapat ditambahkan nanti
di bawah pemeriksaan ADMIN yang ada, setelah model operasional layak dan integrasi
disetujui; hasil regresi tidak boleh menggantikan hitungan kapasitas aktual.

## Menyimpan dummy pada Supabase

Schema khusus `qpark_ml` menyimpan satu snapshot per run dan baris kunjungan simulasi.
`supabase/ml/001_simulation.sql` dijalankan **terpisah** oleh pengelola database;
bukan migrasi otomatis aplikasi. RLS aktif tanpa policy klien; schema dan tabel
tidak diberikan kepada `anon`/`authenticated` dan tidak ditambahkan ke Data API.
Tidak ada perubahan pada schema `public`, tabel operasional, login atau RPC lama.

```powershell
python -m qpark_ml supabase-sql --input "$mlOut/simulation.json" --run-id qpark-linear-sim-v1-seed512 --out "$mlOut/upload.sql"
```

Jalankan SQL schema lalu SQL upload di proyek Supabase yang telah diverifikasi.
Generator SQL tidak mengunggah otomatis: statusnya `prepared`, `uploaded:false`.
Insert dalam transaksi, idempotent untuk run/snapshot sama; run ID sama dengan isi
berbeda ditolak oleh constraint NOT NULL. Verifikasi setelah unggah sebagai admin:

```sql
select run_id, source_kind, count(*)
from qpark_ml.simulation_sessions group by run_id, source_kind;
select snapshot from qpark_ml.simulation_runs
where run_id = 'qpark-linear-sim-v1-seed512';
```

Ekspor nilai `snapshot` sebagai JSON untuk menjalankan `train --input` pada data
yang dibaca balik dari Supabase. Bandingkan isinya dengan snapshot lokal sebelum
mengklaim unggahan berhasil. Publishable key aplikasi bukan akses pengelola untuk
membuat schema; jangan menambahkan service-role key ke Flutter atau repository.

## Pengujian

```powershell
& "$env:TEMP/qpark-linear-venv/Scripts/python.exe" -m unittest discover -s server/tests -v
flutter test --no-pub
flutter analyze --no-pub
```

Tes pelatihan memerlukan lingkungan ML; tanpa sklearn tes tersebut ditandai skip,
bukan dianggap lulus. Tes fitur lainnya menggunakan pustaka standar. Seluruh fixture
terpisah dari data operasional. Hasil eksekusi tercatat di `docs/HASIL_REGRESI_LINEAR.md`.

Rujukan implementasi: [LinearRegression](https://scikit-learn.org/stable/modules/generated/sklearn.linear_model.LinearRegression.html)
dan [pencegahan kebocoran data](https://scikit-learn.org/stable/common_pitfalls.html).
